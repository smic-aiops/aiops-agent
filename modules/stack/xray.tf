resource "aws_xray_sampling_rule" "all" {
  count = local.xray_enabled ? 1 : 0

  rule_name      = "${local.name_prefix}-xray-all"
  priority       = 1
  fixed_rate     = var.xray_sampling_rate
  reservoir_size = 1
  resource_arn   = "*"
  service_name   = "*"
  service_type   = "*"
  host           = "*"
  http_method    = "*"
  url_path       = "*"
  version        = 1

  attributes = {
    "service" = "ecs"
  }
}
