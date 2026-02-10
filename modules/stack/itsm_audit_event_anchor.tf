locals {
  itsm_audit_event_anchor_enabled = var.itsm_audit_event_anchor_enabled
  itsm_audit_event_anchor_bucket_name = lower(coalesce(
    var.itsm_audit_event_anchor_bucket_name,
    "${local.name_prefix}-${var.region}-${local.account_id}-itsm-audit-anchor"
  ))
  itsm_audit_event_anchor_bucket_sse_algorithm = (
    var.itsm_audit_event_anchor_bucket_kms_key_arn != null && var.itsm_audit_event_anchor_bucket_kms_key_arn != ""
  ) ? "aws:kms" : "AES256"
}

resource "aws_s3_bucket" "itsm_audit_event_anchor" {
  count         = local.itsm_audit_event_anchor_enabled ? 1 : 0
  bucket        = local.itsm_audit_event_anchor_bucket_name
  force_destroy = true

  object_lock_enabled = var.itsm_audit_event_anchor_object_lock_enabled

  tags = merge(local.tags, { Name = "${local.name_prefix}-itsm-audit-anchor-s3" })
}

resource "aws_s3_bucket_ownership_controls" "itsm_audit_event_anchor" {
  count  = local.itsm_audit_event_anchor_enabled ? 1 : 0
  bucket = aws_s3_bucket.itsm_audit_event_anchor[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "itsm_audit_event_anchor" {
  count  = local.itsm_audit_event_anchor_enabled ? 1 : 0
  bucket = aws_s3_bucket.itsm_audit_event_anchor[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "itsm_audit_event_anchor" {
  count  = local.itsm_audit_event_anchor_enabled ? 1 : 0
  bucket = aws_s3_bucket.itsm_audit_event_anchor[0].id

  versioning_configuration {
    status = var.itsm_audit_event_anchor_object_lock_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "itsm_audit_event_anchor" {
  count  = local.itsm_audit_event_anchor_enabled ? 1 : 0
  bucket = aws_s3_bucket.itsm_audit_event_anchor[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.itsm_audit_event_anchor_bucket_sse_algorithm
      kms_master_key_id = local.itsm_audit_event_anchor_bucket_sse_algorithm == "aws:kms" ? var.itsm_audit_event_anchor_bucket_kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "itsm_audit_event_anchor" {
  count  = local.itsm_audit_event_anchor_enabled ? 1 : 0
  bucket = aws_s3_bucket.itsm_audit_event_anchor[0].id

  rule {
    id     = "expire-anchors"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.itsm_audit_event_anchor_retention_days
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.itsm_audit_event_anchor_object_lock_enabled ? [1] : []
      content {
        noncurrent_days = var.itsm_audit_event_anchor_retention_days
      }
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "itsm_audit_event_anchor" {
  count  = local.itsm_audit_event_anchor_enabled && var.itsm_audit_event_anchor_object_lock_enabled ? 1 : 0
  bucket = aws_s3_bucket.itsm_audit_event_anchor[0].id

  rule {
    default_retention {
      mode = var.itsm_audit_event_anchor_object_lock_mode
      days = var.itsm_audit_event_anchor_object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.itsm_audit_event_anchor]
}

