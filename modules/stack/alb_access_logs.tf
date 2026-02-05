locals {
  alb_access_logs_enabled = var.create_ecs && var.enable_alb_access_logs
  alb_access_logs_bucket_name = lower(coalesce(
    var.alb_access_logs_bucket_name,
    "${local.name_prefix}-${var.region}-${local.account_id}-alb-logs"
  ))
  alb_access_logs_prefix_effective = trim(coalesce(
    var.alb_access_logs_prefix,
    "alb/realm/${local.keycloak_realm_effective}"
  ), "/")
  alb_access_logs_resource_prefix = local.alb_access_logs_prefix_effective != "" ? "${local.alb_access_logs_prefix_effective}/" : ""
}

resource "aws_s3_bucket" "alb_access_logs" {
  count  = local.alb_access_logs_enabled ? 1 : 0
  bucket = local.alb_access_logs_bucket_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-access-logs" })
}

resource "aws_s3_bucket_ownership_controls" "alb_access_logs" {
  count  = local.alb_access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  count  = local.alb_access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  count  = local.alb_access_logs_enabled && length(aws_s3_bucket.alb_access_logs) > 0 ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  count  = local.alb_access_logs_enabled && length(aws_s3_bucket.alb_access_logs) > 0 ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    id     = "expire-alb-access-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.alb_access_logs_retention_days
    }
  }
}

data "aws_iam_policy_document" "alb_access_logs" {
  count = local.alb_access_logs_enabled && length(aws_s3_bucket.alb_access_logs) > 0 ? 1 : 0

  statement {
    sid = "AllowALBLogDeliveryWrite"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.alb_access_logs[0].arn}/${local.alb_access_logs_resource_prefix}AWSLogs/${local.account_id}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid = "AllowALBLogDeliveryAclCheck"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.alb_access_logs[0].arn]
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  count  = local.alb_access_logs_enabled && length(aws_s3_bucket.alb_access_logs) > 0 ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id
  policy = data.aws_iam_policy_document.alb_access_logs[0].json
}
