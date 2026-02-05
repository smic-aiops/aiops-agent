locals {
  ssm_key_expiry_checker_enabled = var.create_ssm_parameters && var.enable_ssm_key_expiry_checker
}

data "archive_file" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/templates/ssm_key_expiry_checker.py"
  output_path = "${path.module}/templates/ssm_key_expiry_checker.zip"
}

resource "aws_sns_topic" "ssm_key_expiry" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  name = "${local.name_prefix}-ssm-key-expiry"

  tags = merge(local.tags, { Name = "${local.name_prefix}-ssm-key-expiry" })
}

resource "aws_sns_topic_subscription" "ssm_key_expiry_email" {
  count = local.ssm_key_expiry_checker_enabled && var.ssm_key_expiry_sns_email != null && trimspace(var.ssm_key_expiry_sns_email) != "" ? 1 : 0

  topic_arn = aws_sns_topic.ssm_key_expiry[0].arn
  protocol  = "email"
  endpoint  = var.ssm_key_expiry_sns_email
}

data "aws_iam_policy_document" "ssm_key_expiry_checker_assume" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  name               = "${local.name_prefix}-ssm-key-expiry"
  assume_role_policy = data.aws_iam_policy_document.ssm_key_expiry_checker_assume[0].json

  tags = merge(local.tags, { Name = "${local.name_prefix}-ssm-key-expiry" })
}

data "aws_iam_policy_document" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "ssm:DescribeParameters",
      "ssm:ListTagsForResource",
      "ssm:AddTagsToResource"
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = aws_sns_topic.ssm_key_expiry[*].arn

    content {
      actions   = ["sns:Publish"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  name   = "${local.name_prefix}-ssm-key-expiry"
  role   = aws_iam_role.ssm_key_expiry_checker[0].id
  policy = data.aws_iam_policy_document.ssm_key_expiry_checker[0].json
}

resource "aws_cloudwatch_log_group" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-ssm-key-expiry"
  retention_in_days = 30

  tags = merge(local.tags, { Name = "${local.name_prefix}-ssm-key-expiry-logs" })
}

resource "aws_lambda_function" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  function_name = "${local.name_prefix}-ssm-key-expiry"
  role          = aws_iam_role.ssm_key_expiry_checker[0].arn
  handler       = "ssm_key_expiry_checker.handler"
  runtime       = "python3.12"
  timeout       = 60

  filename         = data.archive_file.ssm_key_expiry_checker[0].output_path
  source_code_hash = data.archive_file.ssm_key_expiry_checker[0].output_base64sha256

  environment {
    variables = {
      SSM_PATH_PREFIX       = "/${local.name_prefix}/"
      SNS_TOPIC_ARN         = aws_sns_topic.ssm_key_expiry[0].arn
      MAX_AGE_DAYS          = tostring(var.ssm_key_expiry_max_age_days)
      WARN_DAYS             = tostring(var.ssm_key_expiry_warn_days)
      EXPIRES_AT_TAG_KEY    = "expires_at"
      MANAGE_EXPIRES_AT_TAG = tostring(var.ssm_key_expiry_manage_expires_at_tag)
    }
  }

  depends_on = [aws_cloudwatch_log_group.ssm_key_expiry_checker]

  tags = merge(local.tags, { Name = "${local.name_prefix}-ssm-key-expiry" })
}

resource "aws_cloudwatch_event_rule" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  name                = "${local.name_prefix}-ssm-key-expiry"
  schedule_expression = var.ssm_key_expiry_schedule_expression

  tags = merge(local.tags, { Name = "${local.name_prefix}-ssm-key-expiry" })
}

resource "aws_cloudwatch_event_target" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ssm_key_expiry_checker[0].name
  target_id = "ssm-key-expiry-checker"
  arn       = aws_lambda_function.ssm_key_expiry_checker[0].arn
  input     = "{}"
}

resource "aws_lambda_permission" "ssm_key_expiry_checker" {
  count = local.ssm_key_expiry_checker_enabled ? 1 : 0

  statement_id  = "AllowEventBridgeInvokeSsmKeyExpiryChecker"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ssm_key_expiry_checker[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ssm_key_expiry_checker[0].arn
}
