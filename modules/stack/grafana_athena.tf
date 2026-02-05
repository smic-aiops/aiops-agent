locals {
  grafana_athena_output_bucket_name = lower(coalesce(
    var.grafana_athena_output_bucket_name,
    "${local.name_prefix}-${var.region}-${data.aws_caller_identity.current.account_id}-grafana-athena"
  ))
}

resource "aws_s3_bucket" "grafana_athena_output" {
  count  = var.create_ecs && var.create_grafana ? 1 : 0
  bucket = local.grafana_athena_output_bucket_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-athena-s3" })
}

resource "aws_s3_bucket_ownership_controls" "grafana_athena_output" {
  count  = var.create_ecs && var.create_grafana ? 1 : 0
  bucket = aws_s3_bucket.grafana_athena_output[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "grafana_athena_output" {
  count  = var.create_ecs && var.create_grafana ? 1 : 0
  bucket = aws_s3_bucket.grafana_athena_output[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "grafana_athena_output" {
  count  = var.create_ecs && var.create_grafana ? 1 : 0
  bucket = aws_s3_bucket.grafana_athena_output[0].id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "grafana_athena_output" {
  count  = var.create_ecs && var.create_grafana ? 1 : 0
  bucket = aws_s3_bucket.grafana_athena_output[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "grafana_athena" {
  count = var.create_ecs && var.create_grafana ? 1 : 0

  statement {
    actions = [
      "athena:GetDataCatalog",
      "athena:GetDatabase",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
      "athena:ListDataCatalogs",
      "athena:ListDatabases",
      "athena:ListTableMetadata",
      "athena:ListWorkGroups",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "glue:GetDataCatalog",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables"
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = aws_s3_bucket.grafana_athena_output[*].arn

    content {
      actions = [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads"
      ]
      resources = [statement.value]
    }
  }

  dynamic "statement" {
    for_each = aws_s3_bucket.grafana_athena_output[*].arn

    content {
      actions = [
        "s3:AbortMultipartUpload",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject"
      ]
      resources = ["${statement.value}/*"]
    }
  }
}

resource "aws_iam_policy" "grafana_athena" {
  count  = var.create_ecs && var.create_grafana ? 1 : 0
  name   = "${local.name_prefix}-grafana-athena"
  policy = data.aws_iam_policy_document.grafana_athena[0].json
}

resource "aws_iam_role_policy_attachment" "grafana_athena" {
  count      = var.create_ecs && var.create_grafana ? 1 : 0
  role       = aws_iam_role.ecs_task[0].name
  policy_arn = aws_iam_policy.grafana_athena[0].arn
}
