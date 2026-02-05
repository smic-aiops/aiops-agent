locals {
  ecs_min_capacity                     = 0
  ecs_max_capacity                     = 1
  enable_exastro_autostop              = var.enable_exastro_autostop
  service_control_alarm_period_seconds = 300
  service_control_alarm_period_minutes = local.service_control_alarm_period_seconds / 60
  service_control_idle_minutes = {
    for svc, schedule in local.service_control_schedule_map :
    svc => lookup(schedule, "idle_minutes", 10)
  }
}

resource "aws_appautoscaling_target" "exastro" {
  count = var.create_ecs && local.exastro_service_enabled && local.enable_exastro_autostop ? 1 : 0

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.exastro[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "n8n" {
  count = var.create_ecs && var.create_n8n && var.enable_n8n_autostop ? 1 : 0

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.n8n[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "pgadmin" {
  count = var.create_ecs && var.create_pgadmin && var.enable_pgadmin_autostop ? 1 : 0

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.pgadmin[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "odoo" {
  count = var.create_ecs && var.create_odoo && var.enable_odoo_autostop ? 1 : 0

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.odoo[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "gitlab" {
  count = var.create_ecs && var.create_gitlab && var.enable_gitlab_autostop ? 1 : 0

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.gitlab[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "zulip" {
  count = var.create_ecs && var.create_zulip && var.enable_zulip_autostop ? 1 : 0

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.zulip[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "keycloak" {
  count = var.create_ecs && var.create_keycloak && var.enable_keycloak_autostop ? 1 : 0

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.keycloak[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "sulu" {
  for_each = var.create_ecs && var.create_sulu && var.enable_sulu_autostop ? local.sulu_realm_hosts : {}

  max_capacity       = local.ecs_max_capacity
  min_capacity       = local.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.sulu[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "exastro_idle_scale_to_zero" {
  count = var.create_ecs && local.exastro_service_enabled && local.enable_exastro_autostop ? 1 : 0

  name               = "${local.name_prefix}-exastro-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.exastro[0].resource_id
  scalable_dimension = aws_appautoscaling_target.exastro[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.exastro[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "n8n_idle_scale_to_zero" {
  count = var.create_ecs && var.create_n8n && var.enable_n8n_autostop ? 1 : 0

  name               = "${local.name_prefix}-n8n-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.n8n[0].resource_id
  scalable_dimension = aws_appautoscaling_target.n8n[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.n8n[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "pgadmin_idle_scale_to_zero" {
  count = var.create_ecs && var.create_pgadmin && var.enable_pgadmin_autostop ? 1 : 0

  name               = "${local.name_prefix}-pgadmin-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.pgadmin[0].resource_id
  scalable_dimension = aws_appautoscaling_target.pgadmin[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.pgadmin[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "odoo_idle_scale_to_zero" {
  count = var.create_ecs && var.create_odoo && var.enable_odoo_autostop ? 1 : 0

  name               = "${local.name_prefix}-odoo-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.odoo[0].resource_id
  scalable_dimension = aws_appautoscaling_target.odoo[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.odoo[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "gitlab_idle_scale_to_zero" {
  count = var.create_ecs && var.create_gitlab && var.enable_gitlab_autostop ? 1 : 0

  name               = "${local.name_prefix}-gitlab-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.gitlab[0].resource_id
  scalable_dimension = aws_appautoscaling_target.gitlab[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.gitlab[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "zulip_idle_scale_to_zero" {
  count = var.create_ecs && var.create_zulip && var.enable_zulip_autostop ? 1 : 0

  name               = "${local.name_prefix}-zulip-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.zulip[0].resource_id
  scalable_dimension = aws_appautoscaling_target.zulip[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.zulip[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "keycloak_idle_scale_to_zero" {
  count = var.create_ecs && var.create_keycloak && var.enable_keycloak_autostop ? 1 : 0

  name               = "${local.name_prefix}-keycloak-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.keycloak[0].resource_id
  scalable_dimension = aws_appautoscaling_target.keycloak[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.keycloak[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "sulu_idle_scale_to_zero" {
  for_each = var.create_ecs && var.create_sulu && var.enable_sulu_autostop ? local.sulu_realm_hosts : {}

  name               = "${local.name_prefix}-sulu-${each.key}-idle-scale-to-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.sulu[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.sulu[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.sulu[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "exastro_idle_10m" {
  count = var.create_ecs && local.exastro_service_enabled && local.enable_exastro_autostop ? 1 : 0

  alarm_name          = "${local.name_prefix}-exastro-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "exastro",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale exastro service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-exastro-web"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.exastro_idle_scale_to_zero[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "n8n_idle_10m" {
  count = var.create_ecs && var.create_n8n && var.enable_n8n_autostop ? 1 : 0

  alarm_name          = "${local.name_prefix}-n8n-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "n8n",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale n8n service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-n8n"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.n8n_idle_scale_to_zero[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "pgadmin_idle_10m" {
  count = var.create_ecs && var.create_pgadmin && var.enable_pgadmin_autostop ? 1 : 0

  alarm_name          = "${local.name_prefix}-pgadmin-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "pgadmin",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale pgadmin service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-pgadmin"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.pgadmin_idle_scale_to_zero[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "odoo_idle_10m" {
  count = var.create_ecs && var.create_odoo && var.enable_odoo_autostop ? 1 : 0

  alarm_name          = "${local.name_prefix}-odoo-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "odoo",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale odoo service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-odoo"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.odoo_idle_scale_to_zero[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "gitlab_idle_10m" {
  count = var.create_ecs && var.create_gitlab && var.enable_gitlab_autostop ? 1 : 0

  alarm_name          = "${local.name_prefix}-gitlab-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "gitlab",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale gitlab service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-gitlab"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.gitlab_idle_scale_to_zero[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "zulip_idle_10m" {
  count = var.create_ecs && var.create_zulip && var.enable_zulip_autostop ? 1 : 0

  alarm_name          = "${local.name_prefix}-zulip-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "zulip",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale zulip service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-zulip"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.zulip_idle_scale_to_zero[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "keycloak_idle_10m" {
  count = var.create_ecs && var.create_keycloak && var.enable_keycloak_autostop ? 1 : 0

  alarm_name          = "${local.name_prefix}-keycloak-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "keycloak",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale keycloak service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-keycloak"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.keycloak_idle_scale_to_zero[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "sulu_idle_10m" {
  for_each = var.create_ecs && var.create_sulu && var.enable_sulu_autostop ? local.sulu_realm_hosts : {}

  alarm_name          = "${local.name_prefix}-sulu-${each.key}-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = max(
    1,
    ceil(
      lookup(
        local.service_control_idle_minutes,
        "sulu",
        10
      ) / local.service_control_alarm_period_minutes
    )
  )
  lifecycle {
    ignore_changes = [evaluation_periods]
  }
  metric_name        = "CountedRequests"
  namespace          = "AWS/WAFV2"
  period             = 300
  statistic          = "Sum"
  threshold          = 0
  alarm_description  = "Scale sulu service to 0 when no Japan ALB requests are counted for the configured idle window"
  treat_missing_data = "breaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.alb[0].name
    Rule   = "count-jp-sulu"
    Region = var.region
  }

  alarm_actions = [aws_appautoscaling_policy.sulu_idle_scale_to_zero[each.key].arn]
}
