locals {
  aiops_cloudwatch_alarm_sns_enabled = (
    var.create_ecs &&
    coalesce(var.enable_aiops_cloudwatch_alarm_sns, false)
  )

  aiops_cloudwatch_alarm_ingest_path = "ingest/cloudwatch"
  aiops_cloudwatch_alarm_webhook_urls_by_realm = (
    var.create_ecs && var.create_n8n
    ? { for realm, host in local.n8n_realm_hosts : realm => "https://${host}/webhook/${local.aiops_cloudwatch_alarm_ingest_path}" }
    : {}
  )
  aiops_cloudwatch_alarm_forwarder_enabled = local.aiops_cloudwatch_alarm_sns_enabled && length(local.aiops_cloudwatch_alarm_webhook_urls_by_realm) > 0
}

resource "aws_sns_topic" "aiops_cloudwatch_alarms" {
  count = local.aiops_cloudwatch_alarm_sns_enabled ? 1 : 0

  name = "${local.name_prefix}-aiops-cloudwatch-alarms"

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-cloudwatch-alarms" })
}

data "archive_file" "aiops_cloudwatch_alarm_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/templates/aiops_cloudwatch_alarm_forwarder.mjs"
  output_path = "${path.module}/templates/aiops_cloudwatch_alarm_forwarder.zip"
}

data "aws_iam_policy_document" "aiops_cloudwatch_alarm_forwarder_assume" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aiops_cloudwatch_alarm_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  name               = "${local.name_prefix}-aiops-cloudwatch-forwarder"
  assume_role_policy = data.aws_iam_policy_document.aiops_cloudwatch_alarm_forwarder_assume[0].json

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-cloudwatch-forwarder" })
}

data "aws_iam_policy_document" "aiops_cloudwatch_alarm_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "aiops_cloudwatch_alarm_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  name   = "${local.name_prefix}-aiops-cloudwatch-forwarder"
  role   = aws_iam_role.aiops_cloudwatch_alarm_forwarder[0].id
  policy = data.aws_iam_policy_document.aiops_cloudwatch_alarm_forwarder[0].json
}

resource "aws_cloudwatch_log_group" "aiops_cloudwatch_alarm_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-aiops-cloudwatch-forwarder"
  retention_in_days = 30

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-cloudwatch-forwarder-logs" })
}

resource "aws_lambda_function" "aiops_cloudwatch_alarm_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  function_name = "${local.name_prefix}-aiops-cloudwatch-forwarder"
  role          = aws_iam_role.aiops_cloudwatch_alarm_forwarder[0].arn
  handler       = "aiops_cloudwatch_alarm_forwarder.handler"
  runtime       = "nodejs20.x"
  timeout       = 30

  filename         = data.archive_file.aiops_cloudwatch_alarm_forwarder[0].output_path
  source_code_hash = data.archive_file.aiops_cloudwatch_alarm_forwarder[0].output_base64sha256

  environment {
    variables = {
      TARGET_WEBHOOK_URLS_BY_REALM = jsonencode(local.aiops_cloudwatch_alarm_webhook_urls_by_realm)
      WEBHOOK_TOKENS_BY_REALM      = jsonencode(local.aiops_cloudwatch_webhook_secret_value_by_realm)
      VERIFY_SNS_SIGNATURE         = "true"
      REQUEST_TIMEOUT_MS           = "8000"
      MAX_TARGETS                  = "50"
    }
  }

  depends_on = [aws_cloudwatch_log_group.aiops_cloudwatch_alarm_forwarder]

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-cloudwatch-forwarder" })
}

resource "aws_lambda_permission" "aiops_cloudwatch_alarm_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  statement_id  = "AllowSnsInvokeAIOpsCloudWatchForwarder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aiops_cloudwatch_alarm_forwarder[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.aiops_cloudwatch_alarms[0].arn
}

resource "aws_sns_topic_subscription" "aiops_cloudwatch_alarms_to_forwarder" {
  count = local.aiops_cloudwatch_alarm_forwarder_enabled ? 1 : 0

  topic_arn = aws_sns_topic.aiops_cloudwatch_alarms[0].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.aiops_cloudwatch_alarm_forwarder[0].arn

  depends_on = [aws_lambda_permission.aiops_cloudwatch_alarm_forwarder]
}

resource "aws_cloudwatch_metric_alarm" "sulu_updown" {
  count = local.aiops_cloudwatch_alarm_sns_enabled && var.create_sulu && coalesce(var.enable_sulu_updown_alarm, false) ? 1 : 0

  alarm_name          = "${local.name_prefix}-sulu-updown"
  alarm_description   = "Notify AIOps when Sulu becomes unhealthy OR when the service is stopped (desired=0)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0

  # If the underlying time series disappears (e.g., after a full stop), we still want to notify.
  treat_missing_data = "breaching"

  metric_query {
    id          = "m_unhealthy"
    return_data = false

    metric {
      metric_name = "UnHealthyHostCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Average"

      dimensions = {
        LoadBalancer = aws_lb.app[0].arn_suffix
        TargetGroup  = local.sulu_primary_realm != null ? aws_lb_target_group.sulu[local.sulu_primary_realm].arn_suffix : ""
      }
    }
  }

  metric_query {
    id          = "m_desired"
    return_data = false

    metric {
      metric_name = "DesiredTaskCount"
      # NOTE: This environment publishes ECS service DesiredTaskCount via Container Insights.
      # If you don't enable Container Insights, this metric may be missing and the alarm won't
      # trigger on desired=0 (TreatMissingData=notBreaching).
      namespace = "ECS/ContainerInsights"
      period    = 60
      stat      = "Average"

      dimensions = {
        ClusterName = local.ecs_cluster_name
        ServiceName = local.sulu_primary_realm != null ? "${local.name_prefix}-sulu-${local.sulu_primary_realm}" : ""
      }
    }
  }

  # When desired < 1 (planned/accidental stop), emit 1 to trigger ALARM.
  # NOTE: Container Insights metrics can become missing when the service is fully stopped.
  # Use FILL to treat missing desired count as 0 so the stop signal remains ALARM.
  # Otherwise, pass through UnHealthyHostCount.
  metric_query {
    id          = "e_sulu_updown"
    expression  = "IF(FILL(m_desired, 0) < 1, 1, m_unhealthy)"
    label       = "sulu-updown-or-desired-zero"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops_cloudwatch_alarms[0].arn]
  ok_actions    = [aws_sns_topic.aiops_cloudwatch_alarms[0].arn]

  tags = merge(local.tags, { Name = "${local.name_prefix}-sulu-updown" })
}
