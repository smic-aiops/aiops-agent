locals {
  control_subdomain_effective = coalesce(
    var.control_subdomain != null && var.control_subdomain != "" ? var.control_subdomain : null,
    "control"
  )
  control_site_domain       = "${local.control_subdomain_effective}.${local.hosted_zone_name_input}"
  control_site_bucket_name  = "${local.name_prefix}-${replace(local.hosted_zone_name_input, ".", "-")}-control-site"
  control_site_enabled      = var.enable_service_control
  control_site_auth_enabled = local.control_site_enabled && var.enable_control_site_oidc_auth
  service_control_api_base_url_effective = trim(
    coalesce(
      var.service_control_api_base_url != "" ? var.service_control_api_base_url : null,
      try(aws_apigatewayv2_stage.service_control[0].invoke_url, null),
      ""
    ),
    "/"
  )
  control_api_base_url_effective = local.service_control_api_base_url_effective
  keycloak_base_url_effective = coalesce(
    var.keycloak_base_url != null && var.keycloak_base_url != "" ? var.keycloak_base_url : null,
    "https://keycloak.${local.hosted_zone_name_input}"
  )
  control_site_keycloak_realm = local.keycloak_realm_effective
  control_site_auth_edge_source = templatefile("${path.module}/templates/control_site_auth_edge.js.tftpl", {
    keycloak_base_url               = local.keycloak_base_url_effective,
    keycloak_realm                  = local.control_site_keycloak_realm,
    service_control_ui_client_id    = var.service_control_ui_client_id,
    control_site_auth_allowed_group = var.control_site_auth_allowed_group,
    control_site_auth_callback_path = var.control_site_auth_callback_path
  })
  service_control_autostop_flags = {
    keycloak = var.enable_keycloak_autostop
    zulip    = var.enable_zulip_autostop
    odoo     = var.enable_odoo_autostop
    n8n      = var.enable_n8n_autostop
    sulu     = var.enable_sulu_autostop
    exastro  = local.exastro_service_enabled && (var.enable_exastro_autostop || var.enable_exastro_autostop)
    gitlab   = var.enable_gitlab_autostop
    pgadmin  = var.enable_pgadmin_autostop
  }
  service_control_enabled_services = keys(local.service_control_api_services)
  control_site_realms              = length(var.realms) > 0 ? var.realms : [local.keycloak_realm_effective]
  control_site_realm_service_hosts = {
    for realm in local.control_site_realms :
    realm => {
      n8n     = lookup(local.n8n_realm_hosts, realm, null)
      sulu    = lookup(local.sulu_realm_hosts, realm, null)
      zulip   = lookup(local.zulip_realm_host_map, realm, null)
      grafana = lookup(local.grafana_realm_hosts, realm, null)
    }
  }
  control_site_schedule_defaults = {
    weekday_start = "17:00"
    weekday_stop  = "22:00"
    holiday_start = "08:00"
    holiday_stop  = "23:00"
    idle_minutes  = 60
  }
  control_site_index = templatefile("${path.module}/templates/control-index.html.tftpl", {
    api_base_url                     = local.control_api_base_url_effective,
    default_realm                    = local.control_site_keycloak_realm,
    keycloak_base_url                = local.keycloak_base_url_effective,
    keycloak_realm                   = local.control_site_keycloak_realm,
    service_control_ui_client_id     = var.service_control_ui_client_id,
    service_control_jwt_enabled      = local.service_control_jwt_enabled,
    pgadmin_admin_username           = "admin@${local.hosted_zone_name_input}",
    pgadmin_password_ssm_parameter   = local.pgadmin_default_password_parameter_name,
    n8n_subdomain                    = local.n8n_subdomain,
    control_site_realms              = jsonencode(local.control_site_realms),
    control_site_realm_service_hosts = jsonencode(local.control_site_realm_service_hosts),
    service_control_autostop_flags   = jsonencode(local.service_control_autostop_flags),
    service_control_enabled_svcs     = jsonencode(local.service_control_enabled_services),
    locked_schedule_services         = jsonencode(var.locked_schedule_services),
    DEFAULT_WEEKDAY_START_JST        = local.control_site_schedule_defaults.weekday_start,
    DEFAULT_WEEKDAY_STOP_JST         = local.control_site_schedule_defaults.weekday_stop,
    DEFAULT_HOLIDAY_START_JST        = local.control_site_schedule_defaults.holiday_start,
    DEFAULT_HOLIDAY_STOP_JST         = local.control_site_schedule_defaults.holiday_stop,
    DEFAULT_IDLE_MINUTES             = local.control_site_schedule_defaults.idle_minutes
  })
  wildcard_cf_cert_name = "${local.name_prefix}-cf-wildcard-cert"
  control_site_aliases  = [local.control_site_domain]
}

resource "aws_acm_certificate" "cloudfront_wildcard" {
  provider = aws.us_east_1
  count    = local.control_site_enabled ? 1 : 0

  domain_name       = "*.${local.hosted_zone_name_input}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = local.wildcard_cf_cert_name })
}

resource "aws_route53_record" "cloudfront_wildcard_validation" {
  for_each = local.control_site_enabled ? {
    for dvo in aws_acm_certificate.cloudfront_wildcard[0].domain_validation_options :
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

resource "aws_acm_certificate_validation" "cloudfront_wildcard" {
  provider = aws.us_east_1
  count    = local.control_site_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.cloudfront_wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cloudfront_wildcard_validation : r.fqdn]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "control_site" {
  count  = local.control_site_enabled ? 1 : 0
  bucket = local.control_site_bucket_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-control-site-s3" })
}

resource "aws_s3_bucket_ownership_controls" "control_site" {
  count  = local.control_site_enabled ? 1 : 0
  bucket = aws_s3_bucket.control_site[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "control_site" {
  count  = local.control_site_enabled ? 1 : 0
  bucket = aws_s3_bucket.control_site[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "control_site" {
  count  = local.control_site_enabled ? 1 : 0
  bucket = aws_s3_bucket.control_site[0].id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_object" "control_index" {
  count         = local.control_site_enabled ? 1 : 0
  bucket        = aws_s3_bucket.control_site[0].id
  key           = "index.html"
  content       = local.control_site_index
  content_type  = "text/html"
  cache_control = "no-store, no-cache, must-revalidate"

  depends_on = [
    aws_s3_bucket_public_access_block.control_site,
    aws_s3_bucket_ownership_controls.control_site
  ]
}

resource "aws_s3_object" "control_favicon" {
  count         = local.control_site_enabled ? 1 : 0
  bucket        = aws_s3_bucket.control_site[0].id
  key           = "favicon.ico"
  source        = "${path.module}/templates/favicon.ico"
  content_type  = "image/x-icon"
  cache_control = "public, max-age=86400"

  depends_on = [
    aws_s3_bucket_public_access_block.control_site,
    aws_s3_bucket_ownership_controls.control_site
  ]
}

data "archive_file" "control_site_auth_edge" {
  count = local.control_site_auth_enabled ? 1 : 0

  type                    = "zip"
  source_content          = local.control_site_auth_edge_source
  source_content_filename = "index.js"
  output_path             = "${path.module}/templates/control_site_auth_edge.zip"
}

data "aws_iam_policy_document" "control_site_auth_edge_assume" {
  count = local.control_site_auth_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "control_site_auth_edge" {
  count              = local.control_site_auth_enabled ? 1 : 0
  name               = "${local.name_prefix}-control-site-auth-edge"
  assume_role_policy = data.aws_iam_policy_document.control_site_auth_edge_assume[0].json

  tags = merge(local.tags, { Name = "${local.name_prefix}-control-site-auth-edge" })
}

resource "aws_iam_role_policy_attachment" "control_site_auth_edge_basic" {
  count      = local.control_site_auth_enabled ? 1 : 0
  role       = aws_iam_role.control_site_auth_edge[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "control_site_auth_edge" {
  count    = local.control_site_auth_enabled ? 1 : 0
  provider = aws.us_east_1

  function_name = "${local.name_prefix}-control-site-auth-edge"
  role          = aws_iam_role.control_site_auth_edge[0].arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 5
  memory_size   = 128
  publish       = true

  filename         = data.archive_file.control_site_auth_edge[0].output_path
  source_code_hash = data.archive_file.control_site_auth_edge[0].output_base64sha256

  tags = merge(local.tags, { Name = "${local.name_prefix}-control-site-auth-edge" })
}

resource "aws_cloudfront_origin_access_control" "control_site" {
  count                             = local.control_site_enabled ? 1 : 0
  name                              = "${local.name_prefix}-control-site-oac"
  description                       = "OAC for control site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "time_sleep" "control_site_auth_edge_replica_cleanup" {
  count = local.control_site_enabled ? 1 : 0

  destroy_duration = local.control_site_auth_enabled ? var.control_site_auth_edge_replica_cleanup_wait : "0s"
  triggers = {
    control_site_auth_enabled = tostring(local.control_site_auth_enabled)
  }

  depends_on = [aws_lambda_function.control_site_auth_edge]
}

resource "aws_cloudfront_distribution" "control_site" {
  count = local.control_site_enabled ? 1 : 0

  enabled             = true
  default_root_object = "index.html"
  aliases             = local.control_site_aliases

  origin {
    domain_name              = aws_s3_bucket.control_site[0].bucket_regional_domain_name
    origin_id                = "s3-control-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.control_site[0].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    target_origin_id       = "s3-control-site"
    viewer_protocol_policy = "redirect-to-https"

    dynamic "lambda_function_association" {
      for_each = local.control_site_auth_enabled ? [1] : []
      content {
        event_type   = "viewer-request"
        lambda_arn   = aws_lambda_function.control_site_auth_edge[0].qualified_arn
        include_body = false
      }
    }

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["JP", "VN"]
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront_wildcard[0].certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-control-site-cf" })

  depends_on = [
    aws_acm_certificate_validation.cloudfront_wildcard,
    time_sleep.control_site_auth_edge_replica_cleanup[0]
  ]
}

resource "aws_s3_bucket_policy" "control_site" {
  count  = local.control_site_enabled ? 1 : 0
  bucket = aws_s3_bucket.control_site[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.control_site[0].arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.control_site[0].arn
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.control_site,
    aws_s3_bucket_ownership_controls.control_site,
    aws_cloudfront_distribution.control_site
  ]
}

resource "aws_route53_record" "control_site_alias" {
  count   = local.control_site_enabled ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = local.control_site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.control_site[0].domain_name
    zone_id                = aws_cloudfront_distribution.control_site[0].hosted_zone_id
    evaluate_target_health = false
  }
}
