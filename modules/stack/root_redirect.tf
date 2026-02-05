locals {
  root_redirect_enabled = var.root_redirect_target_url != null && trimspace(var.root_redirect_target_url) != "" && local.hosted_zone_name_input != null && local.hosted_zone_id != null
  root_redirect_target  = trimspace(var.root_redirect_target_url)
  redirect_domains      = local.root_redirect_enabled ? { root = local.hosted_zone_name_input, www = "www.${local.hosted_zone_name_input}" } : {}
  redirect_aliases      = values(local.redirect_domains)
  apex_domain           = local.hosted_zone_name_input
  s3_website_zone_ids = {
    "ap-northeast-1" = "Z2M4EHUR26P7ZW"
  }
  redirect_s3_zone_id = lookup(local.s3_website_zone_ids, var.region, "Z2M4EHUR26P7ZW")
}

resource "aws_s3_bucket" "redirect" {
  for_each = local.redirect_domains

  bucket        = each.value
  force_destroy = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}-redirect-s3" })
}

resource "aws_s3_bucket_ownership_controls" "redirect" {
  for_each = aws_s3_bucket.redirect

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "redirect" {
  for_each = aws_s3_bucket.redirect

  bucket                  = each.value.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "redirect" {
  for_each = aws_s3_bucket.redirect

  bucket = each.value.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_object" "redirect_index" {
  for_each = aws_s3_bucket.redirect

  bucket           = each.value.id
  key              = "index.html"
  content          = ""
  content_type     = "text/html"
  website_redirect = local.root_redirect_target
  acl              = "public-read"

  depends_on = [
    aws_s3_bucket_public_access_block.redirect,
    aws_s3_bucket_ownership_controls.redirect
  ]
}

resource "aws_s3_bucket_policy" "redirect" {
  for_each = aws_s3_bucket.redirect

  bucket = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${each.value.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.redirect]
}

resource "aws_acm_certificate" "root_redirect" {
  provider                  = aws.us_east_1
  count                     = local.root_redirect_enabled ? 1 : 0
  domain_name               = local.apex_domain
  subject_alternative_names = ["www.${local.apex_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-root-redirect-cert" })
}

resource "aws_route53_record" "root_redirect_cert_validation" {
  for_each = local.root_redirect_enabled ? {
    for dvo in aws_acm_certificate.root_redirect[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = local.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  allow_overwrite = true
  ttl             = 60
}

resource "aws_acm_certificate_validation" "root_redirect" {
  provider = aws.us_east_1
  count    = local.root_redirect_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.root_redirect[0].arn
  validation_record_fqdns = [for r in aws_route53_record.root_redirect_cert_validation : r.fqdn]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "root_redirect" {
  count = local.root_redirect_enabled ? 1 : 0

  enabled             = true
  default_root_object = "index.html"
  aliases             = local.redirect_aliases

  origin {
    domain_name = aws_s3_bucket_website_configuration.redirect["root"].website_endpoint
    origin_id   = "s3-root-redirect-website"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-root-redirect-website"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.root_redirect[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-root-redirect-cf" })

  depends_on = [aws_acm_certificate_validation.root_redirect]
}

resource "aws_route53_record" "root_redirect" {
  for_each = local.redirect_domains

  zone_id = local.hosted_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.root_redirect[0].domain_name
    zone_id                = aws_cloudfront_distribution.root_redirect[0].hosted_zone_id
    evaluate_target_health = false
  }
}
