locals {
  gitlab_efs_mirror_enabled = (
    var.create_ecs
    && var.create_n8n
    && var.create_gitlab
    && var.enable_gitlab_efs_mirror
    # local.n8n_efs_id is often unknown during the first plan (fresh bootstrap).
    # Use a plan-stable predicate instead.
    && local.n8n_has_efs_effective
    && local.gitlab_admin_token_write_enabled
    && length(var.gitlab_efs_mirror_project_paths) > 0
  )

  gitlab_efs_mirror_parent_group_full_path_effective = (
    var.gitlab_efs_mirror_parent_group_full_path != null && trimspace(var.gitlab_efs_mirror_parent_group_full_path) != ""
    ? trimspace(var.gitlab_efs_mirror_parent_group_full_path)
    : ""
  )

  gitlab_admin_token_param_arn = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${local.gitlab_admin_token_parameter_name}"
  gitlab_efs_mirror_lock_root  = "${var.n8n_filesystem_path}/qdrant"
  gitlab_efs_mirror_log_group  = local.gitlab_efs_mirror_enabled ? aws_cloudwatch_log_group.ecs["n8n"].name : null

  gitlab_efs_mirror_state_machine_definition = local.gitlab_efs_mirror_enabled ? jsonencode({
    Comment = "Looped GitLab->EFS mirror runner (per realm, sequential)"
    StartAt = "Init"
    States = {
      Init = {
        Type = "Pass"
        Result = {
          realms           = local.n8n_realms
          interval_seconds = var.gitlab_efs_mirror_interval_seconds
        }
        ResultPath = "$"
        Next       = "SyncAllRealms"
      }
      SyncAllRealms = {
        Type           = "Map"
        ItemsPath      = "$.realms"
        MaxConcurrency = 1
        ItemSelector = {
          "realm.$" = "$$.Map.Item.Value"
        }
        Iterator = {
          StartAt = "RunMirrorTask"
          States = {
            RunMirrorTask = {
              Type     = "Task"
              Resource = "arn:aws:states:::ecs:runTask.sync"
              Parameters = {
                # Use try() to avoid "Invalid index" during type-checking when the mirror feature is disabled
                # (and count = 0, making these resources empty tuples).
                Cluster        = try(aws_ecs_cluster.this[0].arn, null)
                TaskDefinition = try(aws_ecs_task_definition.gitlab_efs_mirror[0].arn, null)
                LaunchType     = "FARGATE"
                NetworkConfiguration = {
                  AwsvpcConfiguration = {
                    Subnets        = [local.service_subnet_id]
                    SecurityGroups = [aws_security_group.ecs_service[0].id]
                    AssignPublicIp = "DISABLED"
                  }
                }
                Overrides = {
                  ContainerOverrides = [
                    {
                      Name = "gitlab-mirror"
                      Environment = [
                        { Name = "REALM", "Value.$" = "$.realm" }
                      ]
                    }
                  ]
                }
              }
              End = true
            }
          }
        }
        ResultPath = "$.last_run"
        Next       = "WaitInterval"
      }
      WaitInterval = {
        Type        = "Wait"
        SecondsPath = "$.interval_seconds"
        Next        = "SyncAllRealms"
      }
    }
  }) : null
}

resource "aws_ecs_task_definition" "gitlab_efs_mirror" {
  count = local.gitlab_efs_mirror_enabled ? 1 : 0

  family                   = "${local.name_prefix}-gitlab-efs-mirror"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  volume {
    name = "n8n-data"
    efs_volume_configuration {
      file_system_id     = local.n8n_efs_id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = null
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "gitlab-mirror"
      image     = local.alpine_image_3_19
      essential = true
      entryPoint = [
        "/bin/sh",
        "-c"
      ]
      environment = [
        { name = "GITLAB_BASE_URL", value = "https://${local.gitlab_host}" },
        { name = "GITLAB_PARENT_GROUP_FULL_PATH", value = local.gitlab_efs_mirror_parent_group_full_path_effective },
        { name = "PROJECT_PATHS", value = join(" ", var.gitlab_efs_mirror_project_paths) },
        { name = "N8N_FILESYSTEM_PATH", value = var.n8n_filesystem_path },
        { name = "LOCK_ROOT", value = local.gitlab_efs_mirror_lock_root },
        { name = "DRY_RUN", value = "false" }
      ]
      secrets = [
        { name = "GITLAB_TOKEN", valueFrom = local.gitlab_admin_token_param_arn }
      ]
      mountPoints = [
        {
          sourceVolume  = "n8n-data"
          containerPath = var.n8n_filesystem_path
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.gitlab_efs_mirror_log_group
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
      command = [
        <<-EOT
          set -euo pipefail

          apk add --no-cache ca-certificates git openssh-client util-linux coreutils >/dev/null

          realm="$${REALM:-}"
          if [ -z "$realm" ]; then
            echo "[mirror] REALM is required" >&2
            exit 1
          fi

          gitlab_base_url="$${GITLAB_BASE_URL%/}"
          if [ -z "$gitlab_base_url" ]; then
            echo "[mirror] GITLAB_BASE_URL is required" >&2
            exit 1
          fi

          token="$${GITLAB_TOKEN:-}"
          if [ -z "$token" ]; then
            echo "[mirror] GITLAB_TOKEN is required" >&2
            exit 1
          fi

          parent_group="$${GITLAB_PARENT_GROUP_FULL_PATH:-}"
          group_full_path="$realm"
          if [ -n "$parent_group" ]; then
            group_full_path="$${parent_group%/}/$realm"
          fi

          project_paths="$${PROJECT_PATHS:-}"
          if [ -z "$project_paths" ]; then
            echo "[mirror] PROJECT_PATHS is required" >&2
            exit 1
          fi

          n8n_fs="$${N8N_FILESYSTEM_PATH:-}"
          if [ -z "$n8n_fs" ]; then
            echo "[mirror] N8N_FILESYSTEM_PATH is required" >&2
            exit 1
          fi

          lock_root="$${LOCK_ROOT:-}"
          if [ -z "$lock_root" ]; then
            lock_root="$n8n_fs/qdrant"
          fi
          lock_dir="$${lock_root%/}/$realm"
          mkdir -p "$lock_dir"
          lock_file="$lock_dir/.gitlab_mirror.lock"

          dry_run="$${DRY_RUN:-false}"

          run() {
            if [ "$dry_run" = "true" ]; then
              echo "[mirror] DRY_RUN: $*"
              return 0
            fi
            "$@"
          }

          echo "[mirror] realm=$realm group=$group_full_path base=$gitlab_base_url"

          exec 9>"$lock_file"
          flock -w 600 9

          mirror_root="$${n8n_fs%/}/qdrant/$realm/gitlab/$group_full_path"
          mkdir -p "$mirror_root"

          git_host="$(printf "%s" "$gitlab_base_url" | sed -E "s#^https?://##")"

          for project in $project_paths; do
            dest="$mirror_root/$project.git"
            src="https://$${git_host}/$group_full_path/$${project}.git"

            echo "[mirror] syncing $group_full_path/$project -> $dest"
            if [ -d "$dest" ] && [ -f "$dest/HEAD" ]; then
              run git -C "$dest" remote set-url origin "$src"
              run git -C "$dest" -c "http.extraHeader=PRIVATE-TOKEN: $${token}" remote update --prune
            else
              run rm -rf "$dest"
              run git -c "http.extraHeader=PRIVATE-TOKEN: $${token}" clone --mirror "$src" "$dest"
            fi
          done

          echo "[mirror] done: $realm"
        EOT
      ]
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-mirror-td" })
}

data "aws_iam_policy_document" "gitlab_efs_mirror_sfn_assume" {
  count = local.gitlab_efs_mirror_enabled ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "gitlab_efs_mirror_sfn_policy" {
  count = local.gitlab_efs_mirror_enabled ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "ecs:DescribeTasks",
      "ecs:DescribeTaskDefinition",
      "ecs:StopTask"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "events:DeleteRule",
      "events:DescribeRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource"
    ]
    resources = ["*"]
  }
  statement {
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution[0].arn,
      aws_iam_role.ecs_task[0].arn
    ]
  }
}

resource "aws_iam_role" "gitlab_efs_mirror_sfn" {
  count              = local.gitlab_efs_mirror_enabled ? 1 : 0
  name               = "${local.name_prefix}-gitlab-efs-mirror-sfn"
  assume_role_policy = data.aws_iam_policy_document.gitlab_efs_mirror_sfn_assume[0].json
  tags               = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-mirror-sfn" })
}

resource "aws_iam_policy" "gitlab_efs_mirror_sfn" {
  count  = local.gitlab_efs_mirror_enabled ? 1 : 0
  name   = "${local.name_prefix}-gitlab-efs-mirror-sfn"
  policy = data.aws_iam_policy_document.gitlab_efs_mirror_sfn_policy[0].json
  tags   = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-mirror-sfn" })
}

resource "aws_iam_role_policy_attachment" "gitlab_efs_mirror_sfn" {
  count      = local.gitlab_efs_mirror_enabled ? 1 : 0
  role       = aws_iam_role.gitlab_efs_mirror_sfn[0].name
  policy_arn = aws_iam_policy.gitlab_efs_mirror_sfn[0].arn
}

resource "aws_sfn_state_machine" "gitlab_efs_mirror" {
  count = local.gitlab_efs_mirror_enabled ? 1 : 0

  name       = "${local.name_prefix}-gitlab-efs-mirror"
  role_arn   = aws_iam_role.gitlab_efs_mirror_sfn[0].arn
  definition = local.gitlab_efs_mirror_state_machine_definition
  tags       = merge(local.tags, { Name = "${local.name_prefix}-gitlab-efs-mirror" })
}
