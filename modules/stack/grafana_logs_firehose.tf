locals {
  grafana_logs_to_s3_enabled = var.create_ecs && lookup(local.logs_to_s3_service_map, "grafana", false) && var.create_grafana
  grafana_logs_bucket_name = lower(coalesce(
    var.grafana_logs_bucket_name,
    "${local.name_prefix}-${var.region}-${local.account_id}-grafana-logs"
  ))
  grafana_logs_prefix_effective = trim(coalesce(
    var.grafana_logs_prefix,
    "logs/realm=!{partitionKeyFromQuery:realm}/service=grafana/dt=!{timestamp:yyyy/MM/dd}/"
  ), "/")
  grafana_logs_error_prefix_effective = trim(coalesce(
    var.grafana_logs_error_prefix,
    "errors/!{firehose:error-output-type}/dt=!{timestamp:yyyy/MM/dd}/"
  ), "/")
  grafana_log_destinations_by_realm = {
    for realm in local.grafana_realms :
    realm => lookup(local.ecs_log_destinations_by_realm_service, "${realm}::grafana", null)
  }
  grafana_log_group_names_by_realm = {
    for realm, entry in local.grafana_log_destinations_by_realm :
    realm => entry != null ? distinct(
      length(entry.container_log_groups) > 0 ?
      entry.container_log_groups :
      [entry.service_log_group]
    ) : []
  }
  grafana_log_subscription_targets = {
    for item in flatten([
      for realm, groups in local.grafana_log_group_names_by_realm : [
        for group in groups : { realm = realm, group = group }
      ]
    ]) : "${item.realm}::${item.group}" => item
  }
}

resource "aws_s3_bucket" "grafana_logs" {
  count  = local.grafana_logs_to_s3_enabled ? 1 : 0
  bucket = local.grafana_logs_bucket_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-logs" })
}

resource "aws_s3_bucket_ownership_controls" "grafana_logs" {
  count  = local.grafana_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.grafana_logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "grafana_logs" {
  count  = local.grafana_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.grafana_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "grafana_logs" {
  count  = local.grafana_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.grafana_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "grafana_logs" {
  count  = local.grafana_logs_to_s3_enabled ? 1 : 0
  bucket = aws_s3_bucket.grafana_logs[0].id

  rule {
    id     = "expire-grafana-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.grafana_logs_retention_days
    }
  }
}

resource "aws_cloudwatch_log_group" "grafana_logs_firehose" {
  for_each = local.grafana_logs_to_s3_enabled ? toset(local.grafana_realms) : []

  name              = "/aws/kinesisfirehose/${local.name_prefix}-grafana-logs-${each.key}"
  retention_in_days = var.ecs_logs_retention_days

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-grafana-${each.key}-firehose-logs" })
}

resource "aws_cloudwatch_log_stream" "grafana_logs_firehose" {
  for_each = aws_cloudwatch_log_group.grafana_logs_firehose

  name           = "S3Delivery"
  log_group_name = each.value.name
}

data "aws_iam_policy_document" "grafana_logs_firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "grafana_logs_firehose_inline" {
  count = local.grafana_logs_to_s3_enabled ? 1 : 0

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
      aws_s3_bucket.grafana_logs[0].arn,
      "${aws_s3_bucket.grafana_logs[0].arn}/*"
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
    resources = [for group in aws_cloudwatch_log_group.grafana_logs_firehose : "${group.arn}:*"]
  }
}

resource "aws_iam_role" "grafana_logs_firehose" {
  count              = local.grafana_logs_to_s3_enabled ? 1 : 0
  name               = "${local.name_prefix}-grafana-logs-firehose"
  assume_role_policy = data.aws_iam_policy_document.grafana_logs_firehose_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-logs-firehose" })
}

resource "aws_iam_policy" "grafana_logs_firehose" {
  count  = local.grafana_logs_to_s3_enabled ? 1 : 0
  name   = "${local.name_prefix}-grafana-logs-firehose"
  policy = data.aws_iam_policy_document.grafana_logs_firehose_inline[0].json
}

resource "aws_iam_role_policy_attachment" "grafana_logs_firehose" {
  count      = local.grafana_logs_to_s3_enabled ? 1 : 0
  role       = aws_iam_role.grafana_logs_firehose[0].name
  policy_arn = aws_iam_policy.grafana_logs_firehose[0].arn
}

resource "aws_kinesis_firehose_delivery_stream" "grafana_logs" {
  for_each    = local.grafana_logs_to_s3_enabled ? toset(local.grafana_realms) : []
  name        = "${local.name_prefix}-grafana-logs-${each.key}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.grafana_logs_firehose[0].arn
    bucket_arn          = aws_s3_bucket.grafana_logs[0].arn
    prefix              = "${replace(local.grafana_logs_prefix_effective, "!{partitionKeyFromQuery:realm}", each.key)}/"
    error_output_prefix = "${local.grafana_logs_error_prefix_effective}/"
    buffering_interval  = 300
    buffering_size      = 64
    compression_format  = "GZIP"
    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.grafana_logs_firehose[each.key].name
      log_stream_name = aws_cloudwatch_log_stream.grafana_logs_firehose[each.key].name
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

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-grafana-logs-firehose" })
}

data "aws_iam_policy_document" "grafana_logs_cw_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "grafana_logs_cw_inline" {
  count = local.grafana_logs_to_s3_enabled ? 1 : 0

  statement {
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch"
    ]
    resources = [for stream in aws_kinesis_firehose_delivery_stream.grafana_logs : stream.arn]
  }
}

resource "aws_iam_role" "grafana_logs_cw" {
  count              = local.grafana_logs_to_s3_enabled ? 1 : 0
  name               = "${local.name_prefix}-grafana-logs-cw"
  assume_role_policy = data.aws_iam_policy_document.grafana_logs_cw_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-logs-cw" })
}

resource "aws_iam_policy" "grafana_logs_cw" {
  count  = local.grafana_logs_to_s3_enabled ? 1 : 0
  name   = "${local.name_prefix}-grafana-logs-cw"
  policy = data.aws_iam_policy_document.grafana_logs_cw_inline[0].json
}

resource "aws_iam_role_policy_attachment" "grafana_logs_cw" {
  count      = local.grafana_logs_to_s3_enabled ? 1 : 0
  role       = aws_iam_role.grafana_logs_cw[0].name
  policy_arn = aws_iam_policy.grafana_logs_cw[0].arn
}

resource "aws_cloudwatch_log_subscription_filter" "grafana_logs" {
  for_each = local.grafana_logs_to_s3_enabled ? local.grafana_log_subscription_targets : {}

  name            = "${local.name_prefix}-grafana-logs-to-s3"
  log_group_name  = each.value.group
  filter_pattern  = var.grafana_logs_subscription_filter_pattern
  destination_arn = aws_kinesis_firehose_delivery_stream.grafana_logs[each.value.realm].arn
  role_arn        = aws_iam_role.grafana_logs_cw[0].arn
}
