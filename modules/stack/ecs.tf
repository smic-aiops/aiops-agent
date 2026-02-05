locals {
  ecs_cluster_name        = "${local.name_prefix}-ecs"
  ecs_execution_role_name = "${local.name_prefix}-ecs-exec"
  ecs_task_role_name      = "${local.name_prefix}-ecs-task"
  ecs_xray_enabled        = local.xray_enabled
}

resource "aws_ecs_cluster" "this" {
  count = var.create_ecs ? 1 : 0

  name = local.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.tags, { Name = local.ecs_cluster_name })
}

data "aws_iam_policy_document" "ecs_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  count              = var.create_ecs ? 1 : 0
  name               = local.ecs_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_execution_assume.json

  tags = merge(local.tags, { Name = local.ecs_execution_role_name })
}

data "aws_iam_policy_document" "ecs_execution_ssm" {
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/*"]
  }

  # ECS Exec セッション確立に必要な SSM Messages
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ssm:UpdateInstanceInformation"
    ]
    resources = ["*"]
  }

  # SecureString の復号とセッション暗号化で使用されるキー（AWS マネージドキー alias/aws/ssm）
  statement {
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"]
  }

  statement {
    actions = [
      "ssm:StartSession",
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus"
    ]
    resources = ["*"]
  }

  statement {
    actions   = ["ecs:ExecuteCommand"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecs_execution_ssm" {
  count  = var.create_ecs ? 1 : 0
  name   = "${local.name_prefix}-ecs-exec-ssm"
  policy = data.aws_iam_policy_document.ecs_execution_ssm.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count      = var.create_ecs ? 1 : 0
  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_execution_ecr_ro" {
  count      = var.create_ecs ? 1 : 0
  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ecs_execution_ssm" {
  count      = var.create_ecs ? 1 : 0
  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = aws_iam_policy.ecs_execution_ssm[0].arn
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = length(var.ecs_task_additional_trust_principal_arns) > 0 ? [1] : []
    content {
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = var.ecs_task_additional_trust_principal_arns
      }
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  count              = var.create_ecs ? 1 : 0
  name               = local.ecs_task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = merge(local.tags, { Name = local.ecs_task_role_name })
}

data "aws_iam_policy_document" "ecs_task_ssm" {
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/*"]
  }

  # ECS Exec セッション確立に必要な SSM Messages
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ssm:UpdateInstanceInformation"
    ]
    resources = ["*"]
  }

  # セッション暗号化で使用されるキー（AWS マネージドキー alias/aws/ssm）
  statement {
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"]
  }
}

resource "aws_iam_policy" "ecs_task_ssm" {
  count  = var.create_ecs ? 1 : 0
  name   = "${local.name_prefix}-ecs-task-ssm"
  policy = data.aws_iam_policy_document.ecs_task_ssm.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_ssm" {
  count      = var.create_ecs ? 1 : 0
  role       = aws_iam_role.ecs_task[0].name
  policy_arn = aws_iam_policy.ecs_task_ssm[0].arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_xray" {
  count      = local.ecs_xray_enabled ? 1 : 0
  role       = aws_iam_role.ecs_task[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
