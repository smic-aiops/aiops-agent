locals {
  sulu_image_builder_enabled      = local.service_control_enabled && var.create_sulu
  sulu_image_builder_project_name = "${local.name_prefix}-sulu-image-builder"
  sulu_image_builder_log_group    = "/aws/codebuild/${local.name_prefix}-sulu-image-builder"
  sulu_ecr_repository_arns = [
    "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_namespace}/${var.ecr_repo_sulu}",
    "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_namespace}/${var.ecr_repo_sulu_nginx}",
  ]
}

data "aws_iam_policy_document" "sulu_image_builder_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sulu_image_builder" {
  count = local.sulu_image_builder_enabled ? 1 : 0

  name               = "${local.name_prefix}-sulu-image-builder"
  assume_role_policy = data.aws_iam_policy_document.sulu_image_builder_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-sulu-image-builder" })
}

resource "aws_cloudwatch_log_group" "sulu_image_builder" {
  count = local.sulu_image_builder_enabled ? 1 : 0

  name              = local.sulu_image_builder_log_group
  retention_in_days = 30

  tags = merge(local.tags, { Name = local.sulu_image_builder_project_name })
}

data "aws_iam_policy_document" "sulu_image_builder" {
  count = local.sulu_image_builder_enabled ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.sulu_image_builder[0].arn}:*"]
  }

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = local.sulu_ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "sulu_image_builder" {
  count = local.sulu_image_builder_enabled ? 1 : 0

  name   = "${local.name_prefix}-sulu-image-builder"
  role   = aws_iam_role.sulu_image_builder[0].id
  policy = data.aws_iam_policy_document.sulu_image_builder[0].json
}

resource "aws_codebuild_project" "sulu_image_builder" {
  count = local.sulu_image_builder_enabled ? 1 : 0

  name          = local.sulu_image_builder_project_name
  description   = "Build patched Sulu PHP/Nginx images and push an explicit version tag to ECR"
  service_role  = aws_iam_role.sulu_image_builder[0].arn
  build_timeout = 60

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = var.image_architecture_cpu == "ARM64" ? "aws/codebuild/amazonlinux2-aarch64-standard:3.0" : "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = var.image_architecture_cpu == "ARM64" ? "ARM_CONTAINER" : "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.region
    }

    environment_variable {
      name  = "ECR_PREFIX"
      value = var.ecr_namespace
    }

    environment_variable {
      name  = "ECR_REPO_SULU"
      value = var.ecr_repo_sulu
    }

    environment_variable {
      name  = "ECR_REPO_SULU_NGINX"
      value = var.ecr_repo_sulu_nginx
    }

    environment_variable {
      name  = "IMAGE_ARCH"
      value = var.image_architecture_cpu == "ARM64" ? "linux/arm64" : "linux/amd64"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-YAML
      version: 0.2
      env:
        shell: bash
      phases:
        install:
          commands:
            - set -euo pipefail
            - test -n "$${SULU_IMAGE_TAG:-}"
            - test -n "$${SULU_SOURCE_VERSION:-}"
            - test -n "$${SOURCE_REF:-}"
            - test "$${SULU_IMAGE_TAG}" != "latest"
            - rm -rf /tmp/sulu-aiops-source
            - git clone --filter=blob:none --no-checkout https://github.com/smic-aiops/aiops-agent.git /tmp/sulu-aiops-source
            - cd /tmp/sulu-aiops-source && git fetch --depth 1 origin "$${SOURCE_REF}" && git checkout --detach FETCH_HEAD
        pre_build:
          commands:
            - cd /tmp/sulu-aiops-source
            - if [[ "$${ALLOW_TAG_OVERWRITE:-false}" != "true" ]]; then for repo in "$${ECR_PREFIX}/$${ECR_REPO_SULU}" "$${ECR_PREFIX}/$${ECR_REPO_SULU_NGINX}"; do if aws ecr describe-images --region "$${AWS_REGION}" --repository-name "$${repo}" --image-ids imageTag="$${SULU_IMAGE_TAG}" >/dev/null 2>&1; then echo "ERROR tag already exists $${repo}:$${SULU_IMAGE_TAG}"; exit 1; fi; done; fi
            - SULU_VERSION="$${SULU_SOURCE_VERSION}" N8N_BUILD_ADMIN_ASSETS=true SKIP_SULU_COMPOSER_INSTALL=false scripts/itsm/sulu/pull_sulu_image.sh
        build:
          commands:
            - cd /tmp/sulu-aiops-source
            - export SULU_PHP_URI="$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com/$${ECR_PREFIX}/$${ECR_REPO_SULU}:$${SULU_IMAGE_TAG}"
            - export SULU_NGINX_URI="$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com/$${ECR_PREFIX}/$${ECR_REPO_SULU_NGINX}:$${SULU_IMAGE_TAG}"
            - aws ecr get-login-password --region "$${AWS_REGION}" | docker login --username AWS --password-stdin "$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com"
            - docker build --platform "$${IMAGE_ARCH}" --build-arg SULU_VERSION="$${SULU_SOURCE_VERSION}" --label "org.opencontainers.image.version=$${SULU_IMAGE_TAG}" --label "org.opencontainers.image.title=Sulu PHP" -t "$${SULU_PHP_URI}" docker/sulu
            - docker push "$${SULU_PHP_URI}"
            - docker build --platform "$${IMAGE_ARCH}" --file docker/sulu/nginx/Dockerfile --label "org.opencontainers.image.version=$${SULU_IMAGE_TAG}" --label "org.opencontainers.image.title=Sulu Nginx" -t "$${SULU_NGINX_URI}" docker/sulu
            - docker push "$${SULU_NGINX_URI}"
        post_build:
          commands:
            - aws ecr describe-images --region "$${AWS_REGION}" --repository-name "$${ECR_PREFIX}/$${ECR_REPO_SULU}" --image-ids imageTag="$${SULU_IMAGE_TAG}"
            - aws ecr describe-images --region "$${AWS_REGION}" --repository-name "$${ECR_PREFIX}/$${ECR_REPO_SULU_NGINX}" --image-ids imageTag="$${SULU_IMAGE_TAG}"
    YAML
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.sulu_image_builder[0].name
      stream_name = "build"
    }
  }

  tags = merge(local.tags, { Name = local.sulu_image_builder_project_name })
}
