resource "aws_s3_bucket" "aiops" {
  for_each = var.create_ecs && var.create_n8n ? local.aiops_s3_bucket_names_by_realm : {}

  bucket = each.value

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-aiops-${each.key}" })
}

resource "aws_s3_bucket_ownership_controls" "aiops" {
  for_each = aws_s3_bucket.aiops

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "aiops" {
  for_each = aws_s3_bucket.aiops

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aiops" {
  for_each = aws_s3_bucket.aiops

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
