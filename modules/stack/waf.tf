locals {
  waf_name = "${local.name_prefix}-alb-waf"
  waf_n8n_hosts = (
    length(local.n8n_realm_hosts) > 0 ? sort(values(local.n8n_realm_hosts)) : ["__disabled__"]
  )
  waf_qdrant_hosts = (
    length(local.qdrant_realm_hosts) > 0 ? sort(values(local.qdrant_realm_hosts)) : ["__disabled__"]
  )
  waf_sulu_hosts = (
    length(local.sulu_realm_hosts) > 0 ? sort(values(local.sulu_realm_hosts)) : ["__disabled__"]
  )
  waf_grafana_hosts = (
    length(local.grafana_realm_hosts) > 0 ? sort(values(local.grafana_realm_hosts)) : ["__disabled__"]
  )
}

resource "aws_wafv2_web_acl" "alb" {
  count = var.create_ecs && var.waf_enable ? 1 : 0

  name        = local.waf_name
  description = "Allow all, count JP traffic per host for n8n/qdrant/zulip/exastro/pgadmin/odoo/keycloak/gitlab/grafana"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "count-jp-n8n"
    priority = 10

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_n8n_hosts) == 1 ? [1] : []
          content {
            byte_match_statement {
              positional_constraint = "EXACTLY"
              search_string         = local.waf_n8n_hosts[0]
              field_to_match {
                single_header {
                  name = "host"
                }
              }
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_n8n_hosts) > 1 ? [1] : []
          content {
            or_statement {
              dynamic "statement" {
                for_each = local.waf_n8n_hosts
                content {
                  byte_match_statement {
                    positional_constraint = "EXACTLY"
                    search_string         = statement.value
                    field_to_match {
                      single_header {
                        name = "host"
                      }
                    }
                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-n8n"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-qdrant"
    priority = 12

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_qdrant_hosts) == 1 ? [1] : []
          content {
            byte_match_statement {
              positional_constraint = "EXACTLY"
              search_string         = local.waf_qdrant_hosts[0]
              field_to_match {
                single_header {
                  name = "host"
                }
              }
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_qdrant_hosts) > 1 ? [1] : []
          content {
            or_statement {
              dynamic "statement" {
                for_each = local.waf_qdrant_hosts
                content {
                  byte_match_statement {
                    positional_constraint = "EXACTLY"
                    search_string         = statement.value
                    field_to_match {
                      single_header {
                        name = "host"
                      }
                    }
                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-qdrant"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-zulip"
    priority = 20

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = local.zulip_host
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-zulip"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-exastro-web"
    priority = 22

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = local.exastro_web_host
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-exastro-web"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-exastro-api"
    priority = 24

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = local.exastro_api_host
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-exastro-api"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-pgadmin"
    priority = 25

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = local.pgadmin_host
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-pgadmin"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-odoo"
    priority = 27

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = local.odoo_host
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-odoo"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-sulu"
    priority = 28

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_sulu_hosts) == 1 ? [1] : []
          content {
            byte_match_statement {
              positional_constraint = "EXACTLY"
              search_string         = local.waf_sulu_hosts[0]
              field_to_match {
                single_header {
                  name = "host"
                }
              }
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_sulu_hosts) > 1 ? [1] : []
          content {
            or_statement {
              dynamic "statement" {
                for_each = local.waf_sulu_hosts
                content {
                  byte_match_statement {
                    positional_constraint = "EXACTLY"
                    search_string         = statement.value
                    field_to_match {
                      single_header {
                        name = "host"
                      }
                    }
                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-sulu"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-keycloak"
    priority = 30

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = local.keycloak_host
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-keycloak"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-gitlab"
    priority = 35

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = local.gitlab_host
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-gitlab"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "count-jp-grafana"
    priority = 37

    action {
      count {}
    }

    statement {
      and_statement {
        statement {
          geo_match_statement {
            country_codes = var.waf_geo_country_codes
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_grafana_hosts) == 1 ? [1] : []
          content {
            byte_match_statement {
              positional_constraint = "EXACTLY"
              search_string         = local.waf_grafana_hosts[0]
              field_to_match {
                single_header {
                  name = "host"
                }
              }
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
        dynamic "statement" {
          for_each = length(local.waf_grafana_hosts) > 1 ? [1] : []
          content {
            or_statement {
              dynamic "statement" {
                for_each = local.waf_grafana_hosts
                content {
                  byte_match_statement {
                    positional_constraint = "EXACTLY"
                    search_string         = statement.value
                    field_to_match {
                      single_header {
                        name = "host"
                      }
                    }
                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-count-jp-grafana"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-alb-waf"
    sampled_requests_enabled   = false
  }

  tags = merge(local.tags, { Name = local.waf_name })
}

resource "aws_wafv2_web_acl_association" "alb" {
  count = var.create_ecs ? 1 : 0

  resource_arn = aws_lb.app[0].arn
  web_acl_arn  = aws_wafv2_web_acl.alb[0].arn
}

resource "aws_cloudwatch_log_group" "waf" {
  count = var.create_ecs && var.waf_enable ? 1 : 0

  # WAF ロググループは aws-waf-logs- プレフィックスが必須
  name              = "aws-waf-logs-${local.waf_name}"
  retention_in_days = var.waf_log_retention_in_days

  tags = merge(local.tags, { Name = "${local.waf_name}-logs" })
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  count = var.create_ecs && var.waf_enable ? 1 : 0

  resource_arn = aws_wafv2_web_acl.alb[0].arn
  # Use the log group ARN directly; WAF logging API rejects wildcard-suffixed ARNs.
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  count = var.create_ecs && var.waf_enable ? 1 : 0

  policy_name = "${local.waf_name}-logs"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSWAFLoggingPermissions"
        Effect    = "Allow"
        Principal = { Service = "wafv2.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "${aws_cloudwatch_log_group.waf[0].arn}:*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:wafv2:${var.region}:${data.aws_caller_identity.current.account_id}:regional/webacl/*"
          }
        }
      }
    ]
  })
}
