locals {
  service_control_metrics_stream_enabled_services = [
    for svc, enabled in var.service_control_metrics_stream_services :
    svc if enabled && (svc == "synthetics" || lookup(local.service_control_api_service_flags, svc, false))
  ]
  service_control_metrics_stream_enabled = local.service_control_enabled && length(local.service_control_metrics_stream_enabled_services) > 0
  service_control_metrics_bucket_name = lower(coalesce(
    var.service_control_metrics_bucket_name,
    "${local.name_prefix}-${var.region}-${local.account_id}-metrics"
  ))
  service_control_metrics_bucket_sse_algorithm = (
    var.service_control_metrics_bucket_kms_key_arn != null && var.service_control_metrics_bucket_kms_key_arn != ""
  ) ? "aws:kms" : "AES256"
  service_control_metrics_firehose_name = "${local.name_prefix}-svc-metrics"
  service_control_metrics_stream_name   = "${local.name_prefix}-svc-metrics"
  service_control_metrics_filter_lambda = "${local.name_prefix}-svc-metrics-filter"
  service_control_metrics_metadata_extraction_query = replace(replace(trimspace(<<-JQ
    def attrs:
      (.resourceMetrics // .resource_metrics // [])[]?.resource?.attributes[]?;
    def attr($key):
      first(attrs | select(.key == $key).value.stringValue) // empty;
    def dim($key):
      (.dimensions // {})[$key]? // empty;
    def canary_name:
      dim("CanaryName")
      // dim("canary_name")
      // attr("aws.synthetics.canary.name");
    def container_name:
      attr("aws.ecs.container.name")
      // attr("container.name")
      // attr("ContainerName")
      // dim("ContainerName")
      // dim("containerName")
      // dim("container")
      // (if canary_name == null or canary_name == "" then empty else "synthetics" end);
    def service_name:
      attr("aws.ecs.service.name")
      // attr("ServiceName")
      // attr("TaskDefinitionFamily")
      // attr("service.name")
      // dim("ServiceName")
      // dim("TaskDefinitionFamily")
      // dim("service")
      // canary_name;
    def service_base($name):
      if $name == null then empty
      else ($name | sub("^${local.name_prefix}-"; ""))
      end;
    def realm_from_container($name):
      if $name == null then empty
      elif ($name == "n8n-db-init" or $name == "n8n-fs-init") then empty
      elif ($name | startswith("n8n-")) then ($name | sub("^n8n-"; ""))
      elif ($name == "grafana-db-init" or $name == "grafana-fs-init") then empty
      elif ($name | startswith("grafana-")) then ($name | sub("^grafana-"; ""))
      elif ($name == "sulu-fs-init" or $name == "redis") then empty
      elif ($name | startswith("loupe-indexer-")) then ($name | sub("^loupe-indexer-"; ""))
      elif ($name | startswith("init-db-")) then ($name | sub("^init-db-"; ""))
      elif ($name | startswith("php-fpm-")) then ($name | sub("^php-fpm-"; ""))
      elif ($name | startswith("nginx-")) then ($name | sub("^nginx-"; ""))
      else empty
      end;
    def container_partition($name):
      if $name == null or $name == "" then "service"
      else $name
      end;
    def default_realm_for_service($service):
      if $service == "n8n" then "${local.ecs_n8n_shared_realm}"
      elif $service == "grafana" then "${local.ecs_grafana_shared_realm}"
      elif $service == "sulu" then "${local.ecs_sulu_shared_realm}"
      else "${local.ecs_default_realm}"
      end;
    {
      service: (
        service_base(service_name)
        // "unknown"
      ),
      task: (
        attr("aws.ecs.task.id")
        // attr("TaskId")
        // attr("task.id")
        // dim("TaskId")
        // "unknown"
      ),
      container: (
        container_partition(container_name)
      ),
      realm: (
        realm_from_container(container_name)
        // default_realm_for_service(service_base(service_name))
        // "${local.ecs_default_realm}"
      )
    }
    JQ
  ), "\r", ""), "\n", " ")
}

resource "aws_s3_bucket" "service_control_metrics" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  bucket = local.service_control_metrics_bucket_name

  object_lock_enabled = var.service_control_metrics_object_lock_enabled

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-metrics-s3" })
}

resource "aws_s3_bucket_ownership_controls" "service_control_metrics" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  bucket = aws_s3_bucket.service_control_metrics[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "service_control_metrics" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  bucket = aws_s3_bucket.service_control_metrics[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "service_control_metrics" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  bucket = aws_s3_bucket.service_control_metrics[0].id

  versioning_configuration {
    status = var.service_control_metrics_object_lock_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "service_control_metrics" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  bucket = aws_s3_bucket.service_control_metrics[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.service_control_metrics_bucket_sse_algorithm
      kms_master_key_id = local.service_control_metrics_bucket_sse_algorithm == "aws:kms" ? var.service_control_metrics_bucket_kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "service_control_metrics" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  bucket = aws_s3_bucket.service_control_metrics[0].id

  rule {
    id     = "expire-metrics"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.service_control_metrics_retention_days
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.service_control_metrics_object_lock_enabled ? [1] : []
      content {
        noncurrent_days = var.service_control_metrics_retention_days
      }
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "service_control_metrics" {
  count  = local.service_control_metrics_stream_enabled && var.service_control_metrics_object_lock_enabled ? 1 : 0
  bucket = aws_s3_bucket.service_control_metrics[0].id

  rule {
    default_retention {
      mode = var.service_control_metrics_object_lock_mode
      days = var.service_control_metrics_object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.service_control_metrics]
}

data "archive_file" "service_control_metrics_filter" {
  type        = "zip"
  source_file = "${path.module}/templates/service_control_metric_stream_filter.py"
  output_path = "${path.module}/templates/service_control_metric_stream_filter.zip"
}

data "aws_iam_policy_document" "service_control_metrics_filter_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service_control_metrics_filter" {
  count              = local.service_control_metrics_stream_enabled ? 1 : 0
  name               = "${local.service_control_metrics_filter_lambda}-lambda"
  assume_role_policy = data.aws_iam_policy_document.service_control_metrics_filter_assume.json

  tags = merge(local.tags, { Name = "${local.service_control_metrics_filter_lambda}-lambda" })
}

resource "aws_iam_role_policy_attachment" "service_control_metrics_filter_basic" {
  count      = local.service_control_metrics_stream_enabled ? 1 : 0
  role       = aws_iam_role.service_control_metrics_filter[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "service_control_metrics_filter" {
  count = local.service_control_metrics_stream_enabled ? 1 : 0

  function_name = local.service_control_metrics_filter_lambda
  role          = aws_iam_role.service_control_metrics_filter[0].arn
  handler       = "service_control_metric_stream_filter.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.service_control_metrics_filter.output_path
  source_code_hash = data.archive_file.service_control_metrics_filter.output_base64sha256

  environment {
    variables = {
      NAME_PREFIX      = local.name_prefix
      ENABLED_SERVICES = jsonencode(local.service_control_metrics_stream_enabled_services)
    }
  }

  tags = merge(local.tags, { Name = local.service_control_metrics_filter_lambda })
}

data "aws_iam_policy_document" "service_control_metrics_firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service_control_metrics_firehose" {
  count              = local.service_control_metrics_stream_enabled ? 1 : 0
  name               = "${local.name_prefix}-svc-metrics-firehose"
  assume_role_policy = data.aws_iam_policy_document.service_control_metrics_firehose_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-metrics-firehose" })
}

data "aws_iam_policy_document" "service_control_metrics_firehose_inline" {
  count = local.service_control_metrics_stream_enabled ? 1 : 0

  dynamic "statement" {
    for_each = aws_s3_bucket.service_control_metrics[*].arn

    content {
      actions = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ]
      resources = [
        statement.value,
        "${statement.value}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = aws_lambda_function.service_control_metrics_filter[*].arn

    content {
      actions = [
        "lambda:InvokeFunction",
        "lambda:GetFunctionConfiguration"
      ]
      resources = [
        statement.value,
        "${statement.value}:*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.service_control_metrics_bucket_kms_key_arn != null && var.service_control_metrics_bucket_kms_key_arn != "" ? [1] : []
    content {
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:ReEncrypt*"
      ]
      resources = [var.service_control_metrics_bucket_kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "service_control_metrics_firehose" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  name   = "${local.name_prefix}-svc-metrics-firehose"
  policy = data.aws_iam_policy_document.service_control_metrics_firehose_inline[0].json
}

resource "aws_iam_role_policy_attachment" "service_control_metrics_firehose_inline" {
  count      = local.service_control_metrics_stream_enabled ? 1 : 0
  role       = aws_iam_role.service_control_metrics_firehose[0].name
  policy_arn = aws_iam_policy.service_control_metrics_firehose[0].arn
}

resource "aws_kinesis_firehose_delivery_stream" "service_control_metrics" {
  count       = local.service_control_metrics_stream_enabled ? 1 : 0
  name        = local.service_control_metrics_firehose_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.service_control_metrics_firehose[0].arn
    bucket_arn          = aws_s3_bucket.service_control_metrics[0].arn
    prefix              = var.service_control_metrics_firehose_prefix
    error_output_prefix = var.service_control_metrics_firehose_error_prefix
    buffering_interval  = var.service_control_metrics_firehose_buffer_interval
    buffering_size      = var.service_control_metrics_firehose_buffer_size
    compression_format  = var.service_control_metrics_firehose_compression_format
    kms_key_arn         = local.service_control_metrics_bucket_sse_algorithm == "aws:kms" ? var.service_control_metrics_bucket_kms_key_arn : null

    dynamic_partitioning_configuration {
      enabled = true
    }

    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.service_control_metrics_filter[0].arn
        }
      }

      processors {
        type = "MetadataExtraction"
        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = local.service_control_metrics_metadata_extraction_query
        }
      }

      processors {
        type = "AppendDelimiterToRecord"
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-metrics-firehose" })
}

resource "aws_lambda_permission" "service_control_metrics_firehose" {
  count         = local.service_control_metrics_stream_enabled ? 1 : 0
  statement_id  = "AllowFirehoseInvokeServiceControlMetricsFilter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.service_control_metrics_filter[0].function_name
  principal     = "firehose.amazonaws.com"
  source_arn    = try(aws_kinesis_firehose_delivery_stream.service_control_metrics[0].arn, null)
}

data "aws_iam_policy_document" "service_control_metrics_stream_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["streams.metrics.cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service_control_metrics_stream" {
  count              = local.service_control_metrics_stream_enabled ? 1 : 0
  name               = "${local.name_prefix}-svc-metrics-stream"
  assume_role_policy = data.aws_iam_policy_document.service_control_metrics_stream_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-metrics-stream" })
}

data "aws_iam_policy_document" "service_control_metrics_stream_inline" {
  count = local.service_control_metrics_stream_enabled ? 1 : 0

  dynamic "statement" {
    for_each = aws_kinesis_firehose_delivery_stream.service_control_metrics[*].arn

    content {
      actions = [
        "firehose:PutRecord",
        "firehose:PutRecordBatch"
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_policy" "service_control_metrics_stream" {
  count  = local.service_control_metrics_stream_enabled ? 1 : 0
  name   = "${local.name_prefix}-svc-metrics-stream"
  policy = data.aws_iam_policy_document.service_control_metrics_stream_inline[0].json
}

resource "aws_iam_role_policy_attachment" "service_control_metrics_stream_inline" {
  count      = local.service_control_metrics_stream_enabled ? 1 : 0
  role       = aws_iam_role.service_control_metrics_stream[0].name
  policy_arn = aws_iam_policy.service_control_metrics_stream[0].arn
}

resource "aws_cloudwatch_metric_stream" "service_control_metrics" {
  count = local.service_control_metrics_stream_enabled ? 1 : 0

  name          = local.service_control_metrics_stream_name
  firehose_arn  = try(aws_kinesis_firehose_delivery_stream.service_control_metrics[0].arn, null)
  role_arn      = aws_iam_role.service_control_metrics_stream[0].arn
  output_format = var.service_control_metrics_stream_output_format

  dynamic "include_filter" {
    for_each = var.service_control_metrics_stream_include_filters
    content {
      namespace    = include_filter.value.namespace
      metric_names = try(length(include_filter.value.metric_names), 0) > 0 ? include_filter.value.metric_names : null
    }
  }

  dynamic "exclude_filter" {
    for_each = var.service_control_metrics_stream_exclude_filters
    content {
      namespace    = exclude_filter.value.namespace
      metric_names = try(length(exclude_filter.value.metric_names), 0) > 0 ? exclude_filter.value.metric_names : null
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-metrics-stream" })
}
