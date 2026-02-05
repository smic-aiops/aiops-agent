locals {
  n8n_logs_to_s3_enabled = var.create_ecs && lookup(local.logs_to_s3_service_map, "n8n", false)
  n8n_logs_bucket_name = lower(coalesce(
    var.n8n_logs_bucket_name,
    "${local.name_prefix}-${var.region}-${local.account_id}-n8n-logs"
  ))
  n8n_logs_prefix_effective = trim(coalesce(
    var.n8n_logs_prefix,
    "logs/realm=${local.ecs_n8n_shared_realm}/service=n8n/dt=!{timestamp:yyyy/MM/dd}/"
  ), "/")
  n8n_logs_error_prefix_effective = trim(coalesce(
    var.n8n_logs_error_prefix,
    "errors/!{firehose:error-output-type}/dt=!{timestamp:yyyy/MM/dd}/"
  ), "/")
  n8n_log_destination = lookup(local.ecs_log_destinations_by_realm_service, "${local.ecs_n8n_shared_realm}::n8n", null)
  n8n_log_group_names = local.n8n_log_destination != null ? distinct(
    length(local.n8n_log_destination.container_log_groups) > 0 ?
    local.n8n_log_destination.container_log_groups :
    [local.n8n_log_destination.service_log_group]
  ) : []
}

resource "aws_s3_bucket" "n8n_logs" {
  count  = local.n8n_logs_to_s3_enabled ? 1 : 0
  bucket = local.n8n_logs_bucket_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-logs" })
}

resource "aws_s3_bucket_ownership_controls" "n8n_logs" {
  count  = local.n8n_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.n8n_logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "n8n_logs" {
  count  = local.n8n_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.n8n_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "n8n_logs" {
  count  = local.n8n_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.n8n_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "n8n_logs" {
  count  = local.n8n_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.n8n_logs[0].id

  rule {
    id     = "expire-n8n-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.n8n_logs_retention_days
    }
  }
}

resource "aws_cloudwatch_log_group" "n8n_logs_firehose" {
  count = local.n8n_logs_to_s3_enabled ? 1 : 0

  name              = "/aws/kinesisfirehose/${local.name_prefix}-n8n-logs"
  retention_in_days = var.ecs_logs_retention_days

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-firehose-logs" })
}

resource "aws_cloudwatch_log_stream" "n8n_logs_firehose" {
  count = local.n8n_logs_to_s3_enabled ? 1 : 0

  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.n8n_logs_firehose[0].name
}

data "aws_iam_policy_document" "n8n_logs_firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "n8n_logs_firehose_inline" {
  count = local.n8n_logs_to_s3_enabled ? 1 : 0

  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.n8n_logs[0].arn,
      "${aws_s3_bucket.n8n_logs[0].arn}/*"
    ]
  }
  statement {
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      aws_lambda_function.logs_firehose_processor[0].arn
    ]
  }
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.n8n_logs_firehose[0].arn}:*"]
  }
}

resource "aws_iam_role" "n8n_logs_firehose" {
  count              = local.n8n_logs_to_s3_enabled ? 1 : 0
  name               = "${local.name_prefix}-n8n-logs-firehose"
  assume_role_policy = data.aws_iam_policy_document.n8n_logs_firehose_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-logs-firehose" })
}

resource "aws_iam_policy" "n8n_logs_firehose" {
  count  = local.n8n_logs_to_s3_enabled ? 1 : 0
  name   = "${local.name_prefix}-n8n-logs-firehose"
  policy = data.aws_iam_policy_document.n8n_logs_firehose_inline[0].json
}

resource "aws_iam_role_policy_attachment" "n8n_logs_firehose" {
  count      = local.n8n_logs_to_s3_enabled ? 1 : 0
  role       = aws_iam_role.n8n_logs_firehose[0].name
  policy_arn = aws_iam_policy.n8n_logs_firehose[0].arn
}

resource "aws_kinesis_firehose_delivery_stream" "n8n_logs" {
  count       = local.n8n_logs_to_s3_enabled ? 1 : 0
  name        = "${local.name_prefix}-n8n-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.n8n_logs_firehose[0].arn
    bucket_arn          = aws_s3_bucket.n8n_logs[0].arn
    prefix              = "${local.n8n_logs_prefix_effective}/"
    error_output_prefix = "${local.n8n_logs_error_prefix_effective}/"
    buffering_interval  = 300
    buffering_size      = 64
    compression_format  = "GZIP"
    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.n8n_logs_firehose[0].name
      log_stream_name = aws_cloudwatch_log_stream.n8n_logs_firehose[0].name
    }

    processing_configuration {
      enabled = local.logs_firehose_processing_enabled

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.logs_firehose_processor[0].arn
        }
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-logs-firehose" })
}

data "aws_iam_policy_document" "n8n_logs_cw_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "n8n_logs_cw_inline" {
  count = local.n8n_logs_to_s3_enabled ? 1 : 0

  statement {
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch"
    ]
    resources = [aws_kinesis_firehose_delivery_stream.n8n_logs[0].arn]
  }
}

resource "aws_iam_role" "n8n_logs_cw" {
  count              = local.n8n_logs_to_s3_enabled ? 1 : 0
  name               = "${local.name_prefix}-n8n-logs-cw"
  assume_role_policy = data.aws_iam_policy_document.n8n_logs_cw_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-logs-cw" })
}

resource "aws_iam_policy" "n8n_logs_cw" {
  count  = local.n8n_logs_to_s3_enabled ? 1 : 0
  name   = "${local.name_prefix}-n8n-logs-cw"
  policy = data.aws_iam_policy_document.n8n_logs_cw_inline[0].json
}

resource "aws_iam_role_policy_attachment" "n8n_logs_cw" {
  count      = local.n8n_logs_to_s3_enabled ? 1 : 0
  role       = aws_iam_role.n8n_logs_cw[0].name
  policy_arn = aws_iam_policy.n8n_logs_cw[0].arn
}

resource "aws_cloudwatch_log_subscription_filter" "n8n_logs" {
  for_each = local.n8n_logs_to_s3_enabled ? {
    for name in local.n8n_log_group_names : name => name
  } : {}

  name            = "${local.name_prefix}-n8n-logs-to-s3"
  log_group_name  = each.value
  filter_pattern  = var.n8n_logs_subscription_filter_pattern
  destination_arn = aws_kinesis_firehose_delivery_stream.n8n_logs[0].arn
  role_arn        = aws_iam_role.n8n_logs_cw[0].arn
}
