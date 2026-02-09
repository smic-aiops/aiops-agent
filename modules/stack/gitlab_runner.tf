locals {
  gitlab_runner_task_cpu_effective    = coalesce(var.gitlab_runner_task_cpu, var.ecs_task_cpu)
  gitlab_runner_task_memory_effective = coalesce(var.gitlab_runner_task_memory, var.ecs_task_memory)
}

resource "aws_ecs_task_definition" "gitlab_runner" {
  count = var.create_ecs && var.create_gitlab_runner ? 1 : 0

  family                   = "${local.name_prefix}-gitlab-runner"
  cpu                      = local.gitlab_runner_task_cpu_effective
  memory                   = local.gitlab_runner_task_memory_effective
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "ephemeral_storage" {
    for_each = var.gitlab_runner_ephemeral_storage_gib != null ? [1] : []
    content {
      size_in_gib = var.gitlab_runner_ephemeral_storage_gib
    }
  }

  container_definitions = jsonencode([
    merge(local.ecs_base_container, {
      name  = "gitlab-runner"
      image = local.ecr_uri_gitlab_runner
      entryPoint = [
        "/bin/sh",
        "-lc"
      ]
      command = [
        <<-EOT
          set -eu

          CONFIG_DIR="/etc/gitlab-runner"
          CONFIG_TOML="$${CONFIG_DIR}/config.toml"

          RUNNER_URL="$${GITLAB_RUNNER_URL:-}"
          RUNNER_TOKEN="$${GITLAB_RUNNER_TOKEN:-}"
          RUNNER_NAME="$${GITLAB_RUNNER_NAME:-gitlab-runner}"

          CONCURRENT="$${GITLAB_RUNNER_CONCURRENT:-1}"
          CHECK_INTERVAL="$${GITLAB_RUNNER_CHECK_INTERVAL:-0}"
          BUILDS_DIR="$${GITLAB_RUNNER_BUILDS_DIR:-/tmp/gitlab-runner/builds}"
          CACHE_DIR="$${GITLAB_RUNNER_CACHE_DIR:-/tmp/gitlab-runner/cache}"
          TAG_LIST="$${GITLAB_RUNNER_TAG_LIST:-}"
          RUN_UNTAGGED="$${GITLAB_RUNNER_RUN_UNTAGGED:-true}"

          mkdir -p "$${CONFIG_DIR}" "$${BUILDS_DIR}" "$${CACHE_DIR}"

          if [ -z "$${RUNNER_URL}" ] || [ -z "$${RUNNER_TOKEN}" ]; then
            echo "ERROR: Missing runner settings. Required: GITLAB_RUNNER_URL, GITLAB_RUNNER_TOKEN" >&2
            exit 1
          fi

          if [ ! -s "$${CONFIG_TOML}" ]; then
            echo "[gitlab-runner] Writing $${CONFIG_TOML}"
            {
              printf '%s\\n' "concurrent = $${CONCURRENT}"
              printf '%s\\n' "check_interval = $${CHECK_INTERVAL}"
              printf '%s\\n' "builds_dir = \\\"$${BUILDS_DIR}\\\""
              printf '%s\\n' "cache_dir = \\\"$${CACHE_DIR}\\\""
              printf '%s\\n' ""
              printf '%s\\n' "[[runners]]"
              printf '%s\\n' "  name = \\\"$${RUNNER_NAME}\\\""
              printf '%s\\n' "  url = \\\"$${RUNNER_URL}\\\""
              printf '%s\\n' "  token = \\\"$${RUNNER_TOKEN}\\\""
              printf '%s\\n' "  executor = \\\"shell\\\""
              if [ -n "$${TAG_LIST}" ]; then
                printf '%s\\n' "  tag_list = ["
                oldifs="$${IFS}"
                IFS=,
                for t in $${TAG_LIST}; do
                  t_trim="$(printf '%s' "$${t}" | tr -d '[:space:]')"
                  if [ -n "$${t_trim}" ]; then
                    printf '%s\\n' "    \\\"$${t_trim}\\\","
                  fi
                done
                IFS="$${oldifs}"
                printf '%s\\n' "  ]"
              fi
              printf '%s\\n' "  run_untagged = $${RUN_UNTAGGED}"
              printf '%s\\n' "  locked = false"
            } > "$${CONFIG_TOML}"
          fi

          echo "[gitlab-runner] Starting (shell executor)"
          exec gitlab-runner run --config "$${CONFIG_TOML}" --working-directory "/tmp/gitlab-runner"
        EOT
      ]
      environment = [for k, v in local.gitlab_runner_environment_effective : { name = k, value = v }]
      secrets     = local.gitlab_runner_secrets_effective
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "gitlab-runner--gitlab-runner", aws_cloudwatch_log_group.ecs["gitlab-runner"].name)
        })
      })
    })
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-runner-td" })
}

resource "aws_ecs_service" "gitlab_runner" {
  count = var.create_ecs && var.create_gitlab_runner ? 1 : 0

  name                   = "${local.name_prefix}-gitlab-runner"
  cluster                = aws_ecs_cluster.this[0].id
  task_definition        = aws_ecs_task_definition.gitlab_runner[0].arn
  desired_count          = var.gitlab_runner_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-runner-svc" })
}

