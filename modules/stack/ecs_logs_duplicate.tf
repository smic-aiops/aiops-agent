locals {
  ecs_logs_duplicate_enabled = var.create_ecs && length(local.ecs_container_log_groups) > 0
}

data "archive_file" "ecs_logs_duplicate_lambda" {
  count = local.ecs_logs_duplicate_enabled ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/templates/ecs_logs_duplicate_lambda.py"
  output_path = "${path.module}/templates/ecs_logs_duplicate_lambda.zip"
}

data "aws_iam_policy_document" "ecs_logs_duplicate_assume" {
  count = local.ecs_logs_duplicate_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_logs_duplicate_inline" {
  count = local.ecs_logs_duplicate_enabled ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/*/${local.name_prefix}-*",
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/*/${local.name_prefix}-*:*"
    ]
  }
}

resource "aws_iam_role" "ecs_logs_duplicate" {
  count              = local.ecs_logs_duplicate_enabled ? 1 : 0
  name               = "${local.name_prefix}-ecs-logs-duplicate"
  assume_role_policy = data.aws_iam_policy_document.ecs_logs_duplicate_assume[0].json

  tags = merge(local.tags, { Name = "${local.name_prefix}-ecs-logs-duplicate" })
}

resource "aws_iam_policy" "ecs_logs_duplicate" {
  count  = local.ecs_logs_duplicate_enabled ? 1 : 0
  name   = "${local.name_prefix}-ecs-logs-duplicate"
  policy = data.aws_iam_policy_document.ecs_logs_duplicate_inline[0].json
}

resource "aws_iam_role_policy_attachment" "ecs_logs_duplicate_basic" {
  count      = local.ecs_logs_duplicate_enabled ? 1 : 0
  role       = aws_iam_role.ecs_logs_duplicate[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ecs_logs_duplicate_inline" {
  count      = local.ecs_logs_duplicate_enabled ? 1 : 0
  role       = aws_iam_role.ecs_logs_duplicate[0].name
  policy_arn = aws_iam_policy.ecs_logs_duplicate[0].arn
}

resource "aws_lambda_function" "ecs_logs_duplicate" {
  count = local.ecs_logs_duplicate_enabled ? 1 : 0

  function_name = "${local.name_prefix}-ecs-logs-duplicate"
  role          = aws_iam_role.ecs_logs_duplicate[0].arn
  handler       = "ecs_logs_duplicate_lambda.handler"
  runtime       = "python3.11"

  filename         = data.archive_file.ecs_logs_duplicate_lambda[0].output_path
  source_code_hash = data.archive_file.ecs_logs_duplicate_lambda[0].output_base64sha256

  environment {
    variables = {
      NAME_PREFIX = local.name_prefix
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-ecs-logs-duplicate" })
}

resource "aws_lambda_permission" "ecs_logs_duplicate" {
  count = local.ecs_logs_duplicate_enabled ? 1 : 0

  statement_id  = "AllowCloudWatchLogsInvoke-${local.name_prefix}-ecs-logs-duplicate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_logs_duplicate[0].function_name
  principal     = "logs.${var.region}.amazonaws.com"
  source_arn    = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/*/${local.name_prefix}-*/*:*"
}

resource "aws_cloudwatch_log_subscription_filter" "ecs_logs_duplicate" {
  for_each = local.ecs_logs_duplicate_enabled ? aws_cloudwatch_log_group.ecs_container : {}

  name            = "${local.name_prefix}-${each.key}-to-service-log"
  log_group_name  = each.value.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.ecs_logs_duplicate[0].arn
  distribution    = "ByLogStream"

  depends_on = [aws_lambda_permission.ecs_logs_duplicate]
}
