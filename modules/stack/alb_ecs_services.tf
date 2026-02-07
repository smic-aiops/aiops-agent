locals {
  alb_name              = "${local.name_prefix}-alb"
  alb_sg_name           = "${local.name_prefix}-alb-sg"
  ecs_service_sg        = "${local.name_prefix}-ecs-sg"
  tg_zulip_name         = "${local.name_prefix}-zulip-tg"
  tg_exastro_web_name   = "${local.name_prefix}-exastro-web-tg"
  tg_exastro_api_name   = "${local.name_prefix}-exastro-api-tg"
  tg_pgadmin_name       = "${local.name_prefix}-pgadmin-tg"
  tg_keycloak_name      = "${local.name_prefix}-keycloak-tg"
  tg_odoo_name          = "${local.name_prefix}-odoo-tg"
  tg_gitlab_name        = "${local.name_prefix}-gitlab-tg"
  tg_gitlab_ssh_name    = "${local.name_prefix}-gitlab-ssh-tg"
  nlb_gitlab_ssh_name   = "${local.name_prefix}-gitlab-ssh-nlb"
  zulip_host            = "${local.service_subdomain_map["zulip"]}.${local.hosted_zone_name_input}"
  zulip_realm_host_map  = { for realm in var.realms : realm => "${realm}.zulip.${local.hosted_zone_name_input}" }
  zulip_realms_sorted   = sort(var.realms)
  zulip_oidc_idps_doc   = var.zulip_oidc_idps_yaml != null ? tomap(yamldecode(var.zulip_oidc_idps_yaml)) : {}
  zulip_oidc_by_realm   = { for k, v in local.zulip_oidc_idps_doc : replace(k, "keycloak_", "") => v if startswith(k, "keycloak_") }
  zulip_allowed_hosts   = [local.zulip_host]
  exastro_web_host      = "${local.service_subdomain_map["exastro_web"]}.${local.hosted_zone_name_input}"
  exastro_api_host      = "${local.service_subdomain_map["exastro_api"]}.${local.hosted_zone_name_input}"
  pgadmin_host          = "${local.service_subdomain_map["pgadmin"]}.${local.hosted_zone_name_input}"
  keycloak_host         = "${local.service_subdomain_map["keycloak"]}.${local.hosted_zone_name_input}"
  odoo_host             = "${local.service_subdomain_map["odoo"]}.${local.hosted_zone_name_input}"
  gitlab_host           = "${local.service_subdomain_map["gitlab"]}.${local.hosted_zone_name_input}"
  gitlab_ssh_host       = coalesce(var.gitlab_ssh_host, "gitlab-ssh.${local.hosted_zone_name_input}")
  alb_cert_name         = "${local.name_prefix}-alb-cert"
  service_subnet_keys   = sort(keys(local.private_subnet_ids))
  service_subnet_id     = local.private_subnet_ids[local.service_subnet_keys[0]]
  exastro_desired_count = var.exastro_desired_count
  gitlab_ssh_enabled    = var.create_gitlab && length(var.gitlab_ssh_cidr_blocks) > 0
  public_subnet_cidrs   = [for s in local.public_subnets : s.cidr]
}

resource "aws_security_group" "alb" {
  count = var.create_ecs ? 1 : 0

  name        = local.alb_sg_name
  description = "ALB security group"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.create_n8n ? local.n8n_realm_ports : {}
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.alb_sg_name })
}

resource "aws_security_group" "ecs_service" {
  count = var.create_ecs ? 1 : 0

  name        = local.ecs_service_sg
  description = "ECS service security group"
  vpc_id      = local.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.create_gitlab && length(var.gitlab_ssh_cidr_blocks) > 0 ? [1] : []
    content {
      description = "GitLab SSH access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.gitlab_ssh_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = local.gitlab_ssh_enabled ? [1] : []
    content {
      description = "GitLab SSH health checks (from NLB subnets)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = local.public_subnet_cidrs
    }
  }

  dynamic "ingress" {
    for_each = var.create_keycloak ? [1] : []
    content {
      description = "Keycloak JGroups cluster"
      from_port   = 7800
      to_port     = 7800
      protocol    = "tcp"
      self        = true
    }
  }

  tags = merge(local.tags, { Name = local.ecs_service_sg })
}

resource "aws_lb" "app" {
  count = var.create_ecs ? 1 : 0

  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = values(local.public_subnet_ids)

  dynamic "access_logs" {
    for_each = local.alb_access_logs_enabled ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_access_logs[0].bucket
      prefix  = local.alb_access_logs_prefix_effective
      enabled = true
    }
  }

  tags = merge(local.tags, { Name = local.alb_name })

  depends_on = [
    aws_s3_bucket_policy.alb_access_logs,
    aws_s3_bucket_ownership_controls.alb_access_logs
  ]
}

resource "aws_lb" "gitlab_ssh" {
  count = local.gitlab_ssh_enabled ? 1 : 0

  name               = local.nlb_gitlab_ssh_name
  internal           = false
  load_balancer_type = "network"
  subnets            = values(local.public_subnet_ids)

  tags = merge(local.tags, { Name = local.nlb_gitlab_ssh_name })
}

resource "aws_lb_target_group" "gitlab_ssh" {
  count = local.gitlab_ssh_enabled ? 1 : 0

  name        = local.tg_gitlab_ssh_name
  port        = 22
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    protocol = "TCP"
    port     = "22"
  }

  tags = merge(local.tags, { Name = local.tg_gitlab_ssh_name })
}

resource "aws_lb_listener" "gitlab_ssh" {
  count = local.gitlab_ssh_enabled ? 1 : 0

  load_balancer_arn = aws_lb.gitlab_ssh[0].arn
  port              = var.gitlab_ssh_port
  protocol          = "TCP"

  default_action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.gitlab_ssh[0].arn
      }
    }
  }
}

resource "aws_lb_target_group" "n8n" {
  for_each = var.create_ecs && var.create_n8n ? local.n8n_realm_hosts : {}

  name_prefix = "n8n-"
  port        = local.n8n_realm_ports[each.key]
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/healthz"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { realm = each.key, Name = local.n8n_target_group_name_by_realm[each.key] })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "qdrant" {
  for_each = var.create_ecs && var.create_n8n && var.enable_n8n_qdrant && local.n8n_has_efs_effective ? local.qdrant_realm_hosts : {}

  name_prefix = "qdr-"
  port        = local.qdrant_realm_http_ports[each.key]
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/healthz"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-qdrant-${each.key}-tg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "zulip" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  name_prefix = "zul-"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/public/"
    matcher             = "200-499" # Zulip returns 400 for invalid Host headers used by ALB health checks
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { Name = local.tg_zulip_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "exastro_web" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  name_prefix = "itaw-"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/healthz"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { Name = local.tg_exastro_web_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "exastro_api_admin" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  name_prefix = "itaa-"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/healthz"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { Name = local.tg_exastro_api_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "sulu" {
  for_each = var.create_ecs && var.create_sulu ? local.sulu_realm_hosts : {}

  name_prefix = "mains-"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    # Serve a lightweight 200 from nginx without touching Symfony/Sulu.
    path                = "/healthz"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { realm = each.key, Name = local.sulu_target_group_name_by_realm[each.key] })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "keycloak" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  name_prefix = "kc-"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    # Keycloak 26 exposes health endpoints on the management port 9000
    path                = "/health/ready"
    port                = "9000"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { Name = local.tg_keycloak_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "odoo" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  name_prefix = "odoo-"
  port        = 8069
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { Name = local.tg_odoo_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "pgadmin" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  name_prefix = "pgadm-"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/misc/ping"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { Name = local.tg_pgadmin_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "gitlab" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  name_prefix = "gitlb-"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    # GitLab Omnibus exposes a lightweight health endpoint
    path                = "/-/health"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
  }

  tags = merge(local.tags, { Name = local.tg_gitlab_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "grafana" {
  for_each = var.create_ecs && var.create_gitlab && var.create_grafana ? local.grafana_realm_hosts : {}

  name_prefix = "gfn-"
  port        = local.grafana_realm_ports[each.key]
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path                = "/api/health"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = merge(local.tags, { realm = each.key, Name = local.grafana_target_group_name_by_realm[each.key] })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  count = var.create_ecs ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_acm_certificate" "alb" {
  count       = var.create_ecs ? 1 : 0
  domain_name = "*.${local.hosted_zone_name_input}"
  subject_alternative_names = [
    "*.${local.hosted_zone_name_input}",
    "*.grafana.${local.hosted_zone_name_input}",
    "*.${local.n8n_subdomain}.${local.hosted_zone_name_input}",
    "*.${local.qdrant_subdomain}.${local.hosted_zone_name_input}",
    "*.${local.service_subdomain_map["sulu"]}.${local.hosted_zone_name_input}",
    "*.zulip.${local.hosted_zone_name_input}",
    "sse.zulip.${local.hosted_zone_name_input}",
  ]
  validation_method = "DNS"
  tags              = merge(local.tags, { Name = local.alb_cert_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "alb_cert_validation" {
  for_each = var.create_ecs ? {
    for dvo in aws_acm_certificate.alb[0].domain_validation_options :
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
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "alb" {
  count                   = var.create_ecs ? 1 : 0
  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for r in aws_route53_record.alb_cert_validation : r.fqdn]

  timeouts {
    create = "2h"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  count = var.create_ecs ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.alb[0].certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "http_to_https" {
  count = var.create_ecs ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 1

  action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_lb_listener" "n8n_http_internal" {
  for_each = var.create_ecs && var.create_n8n ? local.n8n_realm_ports : {}

  load_balancer_arn = aws_lb.app[0].arn
  port              = each.value
  protocol          = "HTTP"

  default_action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.n8n[each.key].arn
      }
    }
  }
}

resource "aws_lb_listener_rule" "n8n" {
  for_each = var.create_ecs && var.create_n8n ? local.n8n_realm_hosts : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = local.n8n_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.n8n[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-n8n-${each.key}-https-rule" })
}

resource "aws_lb_listener_rule" "qdrant" {
  for_each = var.create_ecs && var.create_n8n && var.enable_n8n_qdrant && local.n8n_has_efs_effective ? local.qdrant_realm_hosts : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = local.qdrant_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.qdrant[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-qdrant-${each.key}-https-rule" })
}

resource "aws_lb_listener_rule" "n8n_header" {
  count = var.create_ecs && var.create_n8n && local.n8n_primary_realm != null ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 5

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.n8n[local.n8n_primary_realm].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["n8n"]
    }
  }
}

resource "aws_lb_listener_rule" "n8n_http" {
  for_each = var.create_ecs && var.create_n8n ? local.n8n_realm_hosts : {}

  listener_arn = aws_lb_listener.http[0].arn
  priority     = local.n8n_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.n8n[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-n8n-${each.key}-http-rule" })
}

resource "aws_lb_listener_rule" "qdrant_http" {
  for_each = var.create_ecs && var.create_n8n && var.enable_n8n_qdrant && local.n8n_has_efs_effective ? local.qdrant_realm_hosts : {}

  listener_arn = aws_lb_listener.http[0].arn
  priority     = local.qdrant_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.qdrant[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-qdrant-${each.key}-http-rule" })
}

resource "aws_lb_listener_rule" "n8n_http_header" {
  count = var.create_ecs && var.create_n8n && local.n8n_primary_realm != null ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 5

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.n8n[local.n8n_primary_realm].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["n8n"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_header" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 17

  action {
    type  = "forward"
    order = 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["zulip"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_invite_no_oidc_signup" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 13

  action {
    type  = "forward"
    order = 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    host_header {
      values = local.zulip_allowed_hosts
    }
  }

  condition {
    path_pattern {
      values = ["/new/*", "/realm/register", "/realm/register/", "/realm/register/*"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_invite_no_oidc_static" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 14

  action {
    type  = "forward"
    order = 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    host_header {
      values = local.zulip_allowed_hosts
    }
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_realms_signup_no_oidc" {
  for_each = var.create_ecs && var.create_zulip ? local.zulip_realm_host_map : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 80 + index(local.zulip_realms_sorted, each.key)

  action {
    type  = "forward"
    order = 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  condition {
    path_pattern {
      values = ["/new/*", "/static/*"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 18

  action {
    type  = "forward"
    order = 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    host_header {
      values = local.zulip_allowed_hosts
    }
  }
}

resource "aws_lb_listener_rule" "zulip_api_no_oidc" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 16

  action {
    type  = "forward"
    order = 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    host_header {
      values = local.zulip_allowed_hosts
    }
  }

  condition {
    path_pattern {
      values = ["/api/v1/*"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_realms" {
  for_each = var.create_ecs && var.create_zulip ? local.zulip_realm_host_map : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 90 + index(local.zulip_realms_sorted, each.key)

  dynamic "action" {
    for_each = var.enable_zulip_alb_oidc && try(local.zulip_oidc_by_realm[each.key], null) != null ? [1] : []
    content {
      type  = "authenticate-oidc"
      order = 1
      authenticate_oidc {
        authorization_endpoint     = "${trim(local.zulip_oidc_by_realm[each.key].oidc_url, "/")}/protocol/openid-connect/auth"
        token_endpoint             = "${trim(local.zulip_oidc_by_realm[each.key].oidc_url, "/")}/protocol/openid-connect/token"
        user_info_endpoint         = coalesce(try(local.zulip_oidc_by_realm[each.key].api_url, null), "${trim(local.zulip_oidc_by_realm[each.key].oidc_url, "/")}/protocol/openid-connect/userinfo")
        issuer                     = trim(local.zulip_oidc_by_realm[each.key].oidc_url, "/")
        client_id                  = local.zulip_oidc_by_realm[each.key].client_id
        client_secret              = local.zulip_oidc_by_realm[each.key].secret
        on_unauthenticated_request = "authenticate"
        scope                      = coalesce(try(local.zulip_oidc_by_realm[each.key].extra_params.scope, null), "openid email profile")
        session_cookie_name        = "${local.name_prefix}-zulip-auth"
        session_timeout            = 86400
      }
    }
  }

  action {
    type  = "forward"
    order = var.enable_zulip_alb_oidc ? 2 : 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_realms_api_no_oidc" {
  for_each = var.create_ecs && var.create_zulip ? local.zulip_realm_host_map : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 70 + index(local.zulip_realms_sorted, each.key)

  action {
    type  = "forward"
    order = 1
    forward {
      target_group {
        arn = aws_lb_target_group.zulip[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  condition {
    path_pattern {
      values = ["/api/v1/*"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_http_header" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 17

  dynamic "action" {
    for_each = var.enable_zulip_alb_oidc ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_302"
      }
    }
  }

  dynamic "action" {
    for_each = var.enable_zulip_alb_oidc ? [] : [1]
    content {
      type = "forward"
      forward {
        target_group {
          arn = aws_lb_target_group.zulip[0].arn
        }
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["zulip"]
    }
  }
}

resource "aws_lb_listener_rule" "zulip_http" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 18

  dynamic "action" {
    for_each = var.enable_zulip_alb_oidc ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_302"
      }
    }
  }

  dynamic "action" {
    for_each = var.enable_zulip_alb_oidc ? [] : [1]
    content {
      type = "forward"
      forward {
        target_group {
          arn = aws_lb_target_group.zulip[0].arn
        }
      }
    }
  }

  condition {
    host_header {
      values = local.zulip_allowed_hosts
    }
  }
}

resource "aws_lb_listener_rule" "zulip_realms_http" {
  for_each = var.create_ecs && var.create_zulip ? local.zulip_realm_host_map : {}

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 90 + index(local.zulip_realms_sorted, each.key)

  dynamic "action" {
    for_each = var.enable_zulip_alb_oidc ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_302"
      }
    }
  }

  dynamic "action" {
    for_each = var.enable_zulip_alb_oidc ? [] : [1]
    content {
      type = "forward"
      forward {
        target_group {
          arn = aws_lb_target_group.zulip[0].arn
        }
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_web_http_header" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 22

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_web[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["exastro-web"]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_web_http" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 24

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_web[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.exastro_web_host]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_api_http_header" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 26

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_api_admin[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["exastro-api"]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_api_http" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 28

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_api_admin[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.exastro_api_host]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_web_header" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 22

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_web[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["exastro-web"]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_web" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 24

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_web[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.exastro_web_host]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_api_header" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 26

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_api_admin[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["exastro-api"]
    }
  }
}

resource "aws_lb_listener_rule" "exastro_api" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 28

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.exastro_api_admin[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.exastro_api_host]
    }
  }
}

resource "aws_lb_listener_rule" "sulu" {
  for_each = var.create_ecs && var.create_sulu ? local.sulu_realm_hosts : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = local.sulu_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.sulu[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-sulu-${each.key}-https-rule" })
}

resource "aws_lb_listener_rule" "sulu_http" {
  for_each = var.create_ecs && var.create_sulu ? local.sulu_realm_hosts : {}

  listener_arn = aws_lb_listener.http[0].arn
  priority     = local.sulu_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.sulu[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-sulu-${each.key}-http-rule" })
}

resource "aws_lb_listener_rule" "keycloak" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 41

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.keycloak[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.keycloak_host]
    }
  }
}

resource "aws_lb_listener_rule" "odoo_header" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 42

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.odoo[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["odoo"]
    }
  }
}

resource "aws_lb_listener_rule" "odoo" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 44

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.odoo[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.odoo_host]
    }
  }
}

resource "aws_lb_listener_rule" "keycloak_root_redirect" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 37

  action {
    type = "redirect"
    redirect {
      host        = local.keycloak_host
      path        = "/realms/${local.default_realm}/"
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_302"
    }
  }

  condition {
    host_header {
      values = [local.keycloak_host]
    }
  }

  condition {
    path_pattern {
      values = ["/", "/index.html"]
    }
  }
}

resource "aws_lb_listener_rule" "keycloak_header" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 39

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.keycloak[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["keycloak"]
    }
  }
}

resource "aws_lb_listener_rule" "pgadmin_header" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 43

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.pgadmin[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["pgadmin"]
    }
  }
}

resource "aws_lb_listener_rule" "pgadmin" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 50

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.pgadmin[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.pgadmin_host]
    }
  }
}

resource "aws_lb_listener_rule" "gitlab_header" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 55

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.gitlab[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["gitlab"]
    }
  }
}

resource "aws_lb_listener_rule" "gitlab" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 60

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.gitlab[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.gitlab_host]
    }
  }
}

resource "aws_lb_listener_rule" "grafana" {
  for_each = var.create_ecs && var.create_gitlab && var.create_grafana ? local.grafana_realm_hosts : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = local.grafana_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.grafana[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-grafana-${each.key}-https-rule" })
}

resource "aws_lb_listener_rule" "keycloak_http" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 41

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.keycloak[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.keycloak_host]
    }
  }
}

resource "aws_lb_listener_rule" "keycloak_http_root_redirect" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 37

  action {
    type = "redirect"
    redirect {
      host        = local.keycloak_host
      path        = "/realms/${local.default_realm}/"
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_302"
    }
  }

  condition {
    host_header {
      values = [local.keycloak_host]
    }
  }

  condition {
    path_pattern {
      values = ["/", "/index.html"]
    }
  }
}

resource "aws_lb_listener_rule" "keycloak_http_header" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 39

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.keycloak[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["keycloak"]
    }
  }
}

resource "aws_lb_listener_rule" "odoo_http_header" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 42

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.odoo[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["odoo"]
    }
  }
}

resource "aws_lb_listener_rule" "odoo_http" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 44

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.odoo[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.odoo_host]
    }
  }
}

resource "aws_lb_listener_rule" "pgadmin_http_header" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 43

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.pgadmin[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["pgadmin"]
    }
  }
}

resource "aws_lb_listener_rule" "pgadmin_http" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 51

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.pgadmin[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.pgadmin_host]
    }
  }
}

resource "aws_lb_listener_rule" "gitlab_http_header" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 55

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.gitlab[0].arn
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Service-Key"
      values           = ["gitlab"]
    }
  }
}

resource "aws_lb_listener_rule" "gitlab_http" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 60

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.gitlab[0].arn
      }
    }
  }

  condition {
    host_header {
      values = [local.gitlab_host]
    }
  }
}

resource "aws_lb_listener_rule" "grafana_http" {
  for_each = var.create_ecs && var.create_gitlab && var.create_grafana ? local.grafana_realm_hosts : {}

  listener_arn = aws_lb_listener.http[0].arn
  priority     = local.grafana_listener_priority_by_realm[each.key]

  action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.grafana[each.key].arn
      }
    }
  }

  condition {
    host_header {
      values = [each.value]
    }
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-grafana-${each.key}-http-rule" })
}

resource "aws_route53_record" "n8n" {
  for_each = var.create_ecs && var.create_n8n ? local.n8n_realm_hosts : {}

  zone_id         = local.hosted_zone_id
  name            = each.value
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "qdrant" {
  for_each = var.create_ecs && var.create_n8n && var.enable_n8n_qdrant && local.n8n_has_efs_effective ? local.qdrant_realm_hosts : {}

  zone_id         = local.hosted_zone_id
  name            = each.value
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "zulip" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.zulip_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "zulip_realms" {
  for_each = var.create_ecs && var.create_zulip ? toset(var.realms) : toset([])

  zone_id         = local.hosted_zone_id
  name            = "${each.value}.zulip.${local.hosted_zone_name_input}"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "exastro_web" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.exastro_web_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "exastro_api" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.exastro_api_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "pgadmin" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.pgadmin_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "sulu" {
  for_each = var.create_ecs && var.create_sulu ? local.sulu_realm_hosts : {}

  zone_id         = local.hosted_zone_id
  name            = each.value
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "keycloak" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.keycloak_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "odoo" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.odoo_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "gitlab" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.gitlab_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "grafana" {
  for_each = var.create_ecs && var.create_gitlab && var.create_grafana ? local.grafana_realm_hosts : {}

  zone_id         = local.hosted_zone_id
  name            = each.value
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app[0].dns_name
    zone_id                = aws_lb.app[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "gitlab_ssh" {
  count = local.gitlab_ssh_enabled ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = local.gitlab_ssh_host
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.gitlab_ssh[0].dns_name
    zone_id                = aws_lb.gitlab_ssh[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_ecs_service" "n8n" {
  count = var.create_ecs && var.create_n8n ? 1 : 0

  name                   = "${local.name_prefix}-n8n"
  cluster                = aws_ecs_cluster.this[0].id
  task_definition        = aws_ecs_task_definition.n8n[0].arn
  desired_count          = var.n8n_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.n8n_realm_ports
    content {
      target_group_arn = aws_lb_target_group.n8n[load_balancer.key].arn
      container_name   = "n8n-${load_balancer.key}"
      container_port   = load_balancer.value
    }
  }

  dynamic "load_balancer" {
    for_each = var.enable_n8n_qdrant && local.n8n_has_efs_effective ? local.qdrant_realm_http_ports : {}
    content {
      target_group_arn = aws_lb_target_group.qdrant[load_balancer.key].arn
      container_name   = "qdrant-${load_balancer.key}"
      container_port   = load_balancer.value
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-svc" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "exastro" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  name                   = "${local.name_prefix}-exastro"
  cluster                = aws_ecs_cluster.this[0].id
  task_definition        = aws_ecs_task_definition.exastro[0].arn
  desired_count          = local.exastro_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.exastro_web[0].arn
    container_name   = "exastro-web"
    container_port   = 80
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.exastro_api_admin[0].arn
    container_name   = "exastro-api"
    container_port   = 8000
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-svc" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "sulu" {
  for_each = var.create_ecs && var.create_sulu ? local.sulu_realm_hosts : {}

  name                              = "${local.name_prefix}-sulu-${each.key}"
  cluster                           = aws_ecs_cluster.this[0].id
  task_definition                   = aws_ecs_task_definition.sulu[each.key].arn
  desired_count                     = var.sulu_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = var.sulu_health_check_grace_period_seconds
  enable_execute_command            = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.sulu[each.key].arn
    container_name   = "nginx-${each.key}"
    container_port   = local.sulu_realm_ports[each.key]
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-sulu-${each.key}-svc" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "keycloak" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  name                              = "${local.name_prefix}-keycloak"
  cluster                           = aws_ecs_cluster.this[0].id
  task_definition                   = aws_ecs_task_definition.keycloak[0].arn
  desired_count                     = var.keycloak_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = var.keycloak_health_check_grace_period_seconds
  enable_execute_command            = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.keycloak[0].arn
    container_name   = "keycloak"
    container_port   = 8080
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-svc" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "odoo" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  name                   = "${local.name_prefix}-odoo"
  cluster                = aws_ecs_cluster.this[0].id
  task_definition        = aws_ecs_task_definition.odoo[0].arn
  desired_count          = var.odoo_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.odoo[0].arn
    container_name   = "odoo"
    container_port   = 8069
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-svc" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "pgadmin" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  name                   = "${local.name_prefix}-pgadmin"
  cluster                = aws_ecs_cluster.this[0].id
  task_definition        = aws_ecs_task_definition.pgadmin[0].arn
  desired_count          = var.pgadmin_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.pgadmin[0].arn
    container_name   = "pgadmin"
    container_port   = 80
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-pgadmin-svc" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "gitlab" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  name                              = "${local.name_prefix}-gitlab"
  cluster                           = aws_ecs_cluster.this[0].id
  task_definition                   = aws_ecs_task_definition.gitlab[0].arn
  desired_count                     = var.gitlab_desired_count
  launch_type                       = "FARGATE"
  enable_execute_command            = true
  health_check_grace_period_seconds = var.gitlab_health_check_grace_period_seconds

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gitlab[0].arn
    container_name   = "gitlab"
    container_port   = 80
  }

  dynamic "load_balancer" {
    for_each = var.create_grafana ? local.grafana_realm_ports : {}
    content {
      target_group_arn = aws_lb_target_group.grafana[load_balancer.key].arn
      container_name   = "grafana-${load_balancer.key}"
      container_port   = load_balancer.value
    }
  }

  dynamic "load_balancer" {
    for_each = local.gitlab_ssh_enabled ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.gitlab_ssh[0].arn
      container_name   = "gitlab"
      container_port   = 22
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-svc" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_ecs_service" "zulip" {
  count = var.create_ecs && var.create_zulip ? 1 : 0

  name                   = "${local.name_prefix}-zulip"
  cluster                = aws_ecs_cluster.this[0].id
  task_definition        = aws_ecs_task_definition.zulip[0].arn
  desired_count          = var.zulip_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [local.service_subnet_id]
    security_groups  = [aws_security_group.ecs_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.zulip[0].arn
    container_name   = "zulip"
    container_port   = 80
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-svc" })

  depends_on = [aws_lb_listener.https]
}
