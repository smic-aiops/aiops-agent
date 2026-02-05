locals {
  logs_to_s3_allowed_services = ["sulu"]
  logs_to_s3_service_map = {
    for entry in var.enable_logs_to_s3 : entry.service => entry.enabled
    if contains(local.logs_to_s3_allowed_services, entry.service)
  }
  logs_to_s3_services_effective = sort([
    for service in local.enabled_services :
    service if lookup(local.logs_to_s3_service_map, service, false)
  ])
  logs_to_s3_generic_services = [
    for service in local.logs_to_s3_services_effective :
    service if service != "n8n" && service != "grafana"
  ]
  service_logs_realms_by_service = {
    for service in local.logs_to_s3_generic_services :
    service => sort([
      for realm, services in local.ecs_log_destinations_by_realm :
      realm if contains(keys(services), service)
    ])
  }
  service_logs_enabled_services = [
    for service, realms in local.service_logs_realms_by_service :
    service if length(realms) > 0
  ]
  service_logs_bucket_name_by_service = {
    for service in local.service_logs_enabled_services :
    service => lower("${local.name_prefix}-${var.region}-${local.account_id}-${service}-logs")
  }
  service_logs_prefix_by_service_realm = {
    for service, realms in local.service_logs_realms_by_service :
    service => {
      for realm in realms :
      realm => trim("logs/realm=${realm}/service=${service}/dt=!{timestamp:yyyy/MM/dd}/", "/")
    }
  }
  service_logs_error_prefix_by_service = {
    for service in local.service_logs_enabled_services :
    service => trim("errors/!{firehose:error-output-type}/dt=!{timestamp:yyyy/MM/dd}/", "/")
  }
  service_logs_destinations_by_service_realm = {
    for service, realms in local.service_logs_realms_by_service :
    service => {
      for realm in realms :
      realm => lookup(local.ecs_log_destinations_by_realm[realm], service, null)
    }
  }
  service_logs_log_group_names_by_service_realm = {
    for service, realms in local.service_logs_destinations_by_service_realm :
    service => {
      for realm, entry in realms :
      realm => entry != null ? distinct(
        length(entry.container_log_groups) > 0 ?
        entry.container_log_groups :
        [entry.service_log_group]
      ) : []
    }
  }
  service_logs_firehose_targets = {
    for item in flatten([
      for service, realms in local.service_logs_realms_by_service : [
        for realm in realms : { service = service, realm = realm }
      ]
    ]) : "${item.service}::${item.realm}" => item
  }
  service_logs_subscription_targets = {
    for item in flatten([
      for service, realms in local.service_logs_log_group_names_by_service_realm : [
        for realm, groups in realms : [
          for group in groups : { service = service, realm = realm, group = group }
        ]
      ]
    ]) : "${item.service}::${item.realm}::${item.group}" => item
  }
}

resource "aws_s3_bucket" "service_logs" {
  for_each = toset(local.service_logs_enabled_services)

  bucket = local.service_logs_bucket_name_by_service[each.key]

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}-logs" })
}

resource "aws_s3_bucket_ownership_controls" "service_logs" {
  for_each = aws_s3_bucket.service_logs

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "service_logs" {
  for_each = aws_s3_bucket.service_logs

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "service_logs" {
  for_each = aws_s3_bucket.service_logs

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "service_logs" {
  for_each = aws_s3_bucket.service_logs

  bucket = each.value.id

  rule {
    id     = "expire-service-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.service_logs_retention_days
    }
  }
}

data "aws_iam_policy_document" "service_logs_firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "service_logs_firehose_inline" {
  for_each = aws_s3_bucket.service_logs

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
      each.value.arn,
      "${each.value.arn}/*"
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
}

resource "aws_iam_role" "service_logs_firehose" {
  for_each = aws_s3_bucket.service_logs

  name               = "${local.name_prefix}-${each.key}-logs-firehose"
  assume_role_policy = data.aws_iam_policy_document.service_logs_firehose_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}-logs-firehose" })
}

resource "aws_iam_policy" "service_logs_firehose" {
  for_each = aws_s3_bucket.service_logs

  name   = "${local.name_prefix}-${each.key}-logs-firehose"
  policy = data.aws_iam_policy_document.service_logs_firehose_inline[each.key].json
}

resource "aws_iam_role_policy_attachment" "service_logs_firehose" {
  for_each = aws_s3_bucket.service_logs

  role       = aws_iam_role.service_logs_firehose[each.key].name
  policy_arn = aws_iam_policy.service_logs_firehose[each.key].arn
}

resource "aws_kinesis_firehose_delivery_stream" "service_logs" {
  for_each    = local.service_logs_firehose_targets
  name        = "${local.name_prefix}-${each.value.service}-logs-${each.value.realm}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.service_logs_firehose[each.value.service].arn
    bucket_arn          = aws_s3_bucket.service_logs[each.value.service].arn
    prefix              = "${local.service_logs_prefix_by_service_realm[each.value.service][each.value.realm]}/"
    error_output_prefix = "${local.service_logs_error_prefix_by_service[each.value.service]}/"
    buffering_interval  = 300
    buffering_size      = 64
    compression_format  = "GZIP"

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

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.value.service}-logs-firehose" })
}

data "aws_iam_policy_document" "service_logs_cw_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
  }
}

locals {
  service_logs_firehose_arns_by_service = {
    for service in local.service_logs_enabled_services :
    service => [
      for key, stream in aws_kinesis_firehose_delivery_stream.service_logs :
      stream.arn if local.service_logs_firehose_targets[key].service == service
    ]
  }
}

data "aws_iam_policy_document" "service_logs_cw_inline" {
  for_each = toset(local.service_logs_enabled_services)

  statement {
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch"
    ]
    resources = local.service_logs_firehose_arns_by_service[each.key]
  }
}

resource "aws_iam_role" "service_logs_cw" {
  for_each = toset(local.service_logs_enabled_services)

  name               = "${local.name_prefix}-${each.key}-logs-cw"
  assume_role_policy = data.aws_iam_policy_document.service_logs_cw_assume.json

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}-logs-cw" })
}

resource "aws_iam_policy" "service_logs_cw" {
  for_each = toset(local.service_logs_enabled_services)

  name   = "${local.name_prefix}-${each.key}-logs-cw"
  policy = data.aws_iam_policy_document.service_logs_cw_inline[each.key].json
}

resource "aws_iam_role_policy_attachment" "service_logs_cw" {
  for_each = toset(local.service_logs_enabled_services)

  role       = aws_iam_role.service_logs_cw[each.key].name
  policy_arn = aws_iam_policy.service_logs_cw[each.key].arn
}

resource "aws_cloudwatch_log_subscription_filter" "service_logs" {
  for_each = local.service_logs_subscription_targets

  name            = "${local.name_prefix}-${each.value.service}-${each.value.realm}-logs-to-s3"
  log_group_name  = each.value.group
  filter_pattern  = var.service_logs_subscription_filter_pattern
  destination_arn = aws_kinesis_firehose_delivery_stream.service_logs["${each.value.service}::${each.value.realm}"].arn
  role_arn        = aws_iam_role.service_logs_cw[each.value.service].arn
}
