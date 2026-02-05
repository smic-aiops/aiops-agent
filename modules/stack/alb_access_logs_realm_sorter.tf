locals {
  alb_access_logs_realm_sorter_enabled              = local.alb_access_logs_enabled && var.enable_alb_access_logs_realm_sorter
  alb_access_logs_realm_sorter_source_prefix        = trim(var.alb_access_logs_realm_sorter_source_prefix, "/")
  alb_access_logs_realm_sorter_source_prefix_filter = local.alb_access_logs_realm_sorter_source_prefix != "" ? "${local.alb_access_logs_realm_sorter_source_prefix}/" : ""
  alb_access_logs_realm_sorter_target_prefix        = trim(var.alb_access_logs_realm_sorter_target_prefix, "/")
  alb_access_logs_realm_sorter_realms               = length(var.realms) > 0 ? var.realms : [local.keycloak_realm_effective]
  alb_access_logs_realm_sorter_realms_csv           = join(",", local.alb_access_logs_realm_sorter_realms)
}

data "archive_file" "alb_access_logs_realm_sorter_lambda" {
  type        = "zip"
  source_file = "${path.module}/templates/alb_access_logs_realm_sorter_lambda.py"
  output_path = "${path.module}/templates/alb_access_logs_realm_sorter_lambda.zip"
}

data "aws_iam_policy_document" "alb_access_logs_realm_sorter_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_access_logs_realm_sorter" {
  count              = local.alb_access_logs_realm_sorter_enabled ? 1 : 0
  name               = "${local.name_prefix}-alb-access-logs-sorter-lambda"
  assume_role_policy = data.aws_iam_policy_document.alb_access_logs_realm_sorter_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-access-logs-sorter-lambda" })
}

data "aws_iam_policy_document" "alb_access_logs_realm_sorter_inline" {
  count = local.alb_access_logs_realm_sorter_enabled ? 1 : 0

  dynamic "statement" {
    for_each = aws_s3_bucket.alb_access_logs[*].arn

    content {
      actions = concat(
        ["s3:GetObject", "s3:PutObject"],
        var.alb_access_logs_realm_sorter_delete_source ? ["s3:DeleteObject"] : []
      )
      resources = ["${statement.value}/*"]
    }
  }
}

resource "aws_iam_policy" "alb_access_logs_realm_sorter" {
  count  = local.alb_access_logs_realm_sorter_enabled ? 1 : 0
  name   = "${local.name_prefix}-alb-access-logs-sorter"
  policy = data.aws_iam_policy_document.alb_access_logs_realm_sorter_inline[0].json
}

resource "aws_iam_role_policy_attachment" "alb_access_logs_realm_sorter_basic" {
  count      = local.alb_access_logs_realm_sorter_enabled ? 1 : 0
  role       = aws_iam_role.alb_access_logs_realm_sorter[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "alb_access_logs_realm_sorter_inline" {
  count      = local.alb_access_logs_realm_sorter_enabled ? 1 : 0
  role       = aws_iam_role.alb_access_logs_realm_sorter[0].name
  policy_arn = aws_iam_policy.alb_access_logs_realm_sorter[0].arn
}

resource "aws_lambda_function" "alb_access_logs_realm_sorter" {
  count = local.alb_access_logs_realm_sorter_enabled ? 1 : 0

  function_name = "${local.name_prefix}-alb-access-logs-sorter"
  role          = aws_iam_role.alb_access_logs_realm_sorter[0].arn
  handler       = "alb_access_logs_realm_sorter_lambda.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.alb_access_logs_realm_sorter_lambda.output_path
  source_code_hash = data.archive_file.alb_access_logs_realm_sorter_lambda.output_base64sha256

  environment {
    variables = {
      SOURCE_PREFIX = local.alb_access_logs_realm_sorter_source_prefix_filter
      TARGET_PREFIX = local.alb_access_logs_realm_sorter_target_prefix
      DEFAULT_REALM = local.keycloak_realm_effective
      REALMS        = local.alb_access_logs_realm_sorter_realms_csv
      DELETE_SOURCE = var.alb_access_logs_realm_sorter_delete_source ? "true" : "false"
      LOG_LEVEL     = "INFO"
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-access-logs-sorter" })
}

resource "aws_lambda_permission" "alb_access_logs_realm_sorter" {
  count = local.alb_access_logs_realm_sorter_enabled ? 1 : 0

  statement_id  = "AllowS3InvokeAlbAccessLogsSorter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alb_access_logs_realm_sorter[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.alb_access_logs[0].arn
}

resource "aws_s3_bucket_notification" "alb_access_logs_realm_sorter" {
  count  = local.alb_access_logs_realm_sorter_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  lambda_function {
    lambda_function_arn = aws_lambda_function.alb_access_logs_realm_sorter[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = local.alb_access_logs_realm_sorter_source_prefix_filter
    filter_suffix       = ".log.gz"
  }

  depends_on = [aws_lambda_permission.alb_access_logs_realm_sorter]
}
