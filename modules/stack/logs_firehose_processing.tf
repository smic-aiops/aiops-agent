locals {
  logs_firehose_processing_enabled = var.create_ecs && length(local.logs_to_s3_services_effective) > 0
  logs_firehose_arns_by_key = merge(
    local.n8n_logs_to_s3_enabled ? { "n8n" = aws_kinesis_firehose_delivery_stream.n8n_logs[0].arn } : {},
    { for key, stream in aws_kinesis_firehose_delivery_stream.grafana_logs : "grafana::${key}" => stream.arn },
    { for key, stream in aws_kinesis_firehose_delivery_stream.service_logs : "service::${key}" => stream.arn }
  )
}

data "archive_file" "logs_firehose_processor" {
  type        = "zip"
  source_file = "${path.module}/templates/cloudwatch_logs_to_json_lambda.py"
  output_path = "${path.module}/templates/cloudwatch_logs_to_json_lambda.zip"
}

data "aws_iam_policy_document" "logs_firehose_processor_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "logs_firehose_processor" {
  count              = local.logs_firehose_processing_enabled ? 1 : 0
  name               = "${local.name_prefix}-logs-firehose-processor"
  assume_role_policy = data.aws_iam_policy_document.logs_firehose_processor_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-logs-firehose-processor" })
}

resource "aws_iam_role_policy_attachment" "logs_firehose_processor_basic" {
  count      = local.logs_firehose_processing_enabled ? 1 : 0
  role       = aws_iam_role.logs_firehose_processor[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "logs_firehose_processor" {
  count = local.logs_firehose_processing_enabled ? 1 : 0

  function_name = "${local.name_prefix}-logs-firehose-processor"
  role          = aws_iam_role.logs_firehose_processor[0].arn
  handler       = "cloudwatch_logs_to_json_lambda.handler"
  runtime       = "python3.12"
  timeout       = 60

  filename         = data.archive_file.logs_firehose_processor.output_path
  source_code_hash = data.archive_file.logs_firehose_processor.output_base64sha256

  tags = merge(local.tags, { Name = "${local.name_prefix}-logs-firehose-processor" })
}

resource "aws_lambda_permission" "logs_firehose_processor" {
  for_each = local.logs_firehose_processing_enabled ? local.logs_firehose_arns_by_key : {}

  statement_id  = "AllowFirehoseInvoke-${replace(each.key, ":", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.logs_firehose_processor[0].arn
  principal     = "firehose.amazonaws.com"
  source_arn    = "${each.value}*"
}
