locals {
  service_control_api_name       = "${local.name_prefix}-svc-control-api"
  service_control_lambda_name    = "${local.name_prefix}-svc-control"
  service_control_lambda_role    = "${local.name_prefix}-svc-control-lambda"
  service_control_api_stage_name = "$default"
  service_control_api_log_group  = "/aws/apigw/${local.name_prefix}-svc-control-api"
  service_control_jwt_audiences_effective = distinct(compact(concat(
    var.service_control_jwt_audiences,
    var.service_control_oidc_client_id != null ? [var.service_control_oidc_client_id] : [],
    var.service_control_ui_client_id != null ? [var.service_control_ui_client_id] : []
  )))
  service_control_jwt_enabled = var.service_control_jwt_issuer != null && length(local.service_control_jwt_audiences_effective) > 0
  service_control_api_service_flags = {
    n8n      = var.create_n8n
    zulip    = var.create_zulip
    exastro  = local.exastro_service_enabled
    sulu     = var.create_sulu
    keycloak = var.create_keycloak
    odoo     = var.create_odoo
    pgadmin  = var.create_pgadmin
    gitlab   = var.create_gitlab
  }
  service_control_enabled = var.create_ecs && var.enable_service_control && anytrue(values(local.service_control_api_service_flags))
  service_control_api_services = {
    for k, v in {
      n8n      = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-n8n"
      zulip    = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-zulip"
      exastro  = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-exastro"
      sulu     = { for realm in local.sulu_realms : realm => "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-sulu-${realm}" }
      keycloak = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-keycloak"
      odoo     = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-odoo"
      pgadmin  = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-pgadmin"
      gitlab   = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.ecs_cluster_name}/${local.name_prefix}-gitlab"
    } : k => v if lookup(local.service_control_api_service_flags, k, false)
  }
  service_control_api_service_arns = flatten([
    for v in values(local.service_control_api_services) : try(values(v), [v])
  ])
  service_control_target_groups = {
    for k, v in {
      n8n      = local.n8n_primary_realm != null ? try(aws_lb_target_group.n8n[local.n8n_primary_realm].arn, "") : ""
      zulip    = try(aws_lb_target_group.zulip[0].arn, "")
      exastro  = try(aws_lb_target_group.exastro_web[0].arn, "")
      sulu     = { for realm in local.sulu_realms : realm => try(aws_lb_target_group.sulu[realm].arn, "") }
      keycloak = try(aws_lb_target_group.keycloak[0].arn, "")
      odoo     = try(aws_lb_target_group.odoo[0].arn, "")
      pgadmin  = try(aws_lb_target_group.pgadmin[0].arn, "")
      gitlab   = try(aws_lb_target_group.gitlab[0].arn, "")
    } : k => v if lookup(local.service_control_api_service_flags, k, false)
  }
  service_control_api_cluster_arn = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.ecs_cluster_name}"
  service_control_schedule_prefix = local.service_control_ssm_path
  service_control_autostop_alarm_sources = {
    exastro = {
      policy = aws_appautoscaling_policy.exastro_idle_scale_to_zero
      rule   = "count-jp-exastro-web"
    }
    sulu = {
      policy = local.sulu_primary_realm != null ? try([aws_appautoscaling_policy.sulu_idle_scale_to_zero[local.sulu_primary_realm]], []) : []
      rule   = "count-jp-sulu"
    }
    n8n = {
      policy = aws_appautoscaling_policy.n8n_idle_scale_to_zero
      rule   = "count-jp-n8n"
    }
    pgadmin = {
      policy = aws_appautoscaling_policy.pgadmin_idle_scale_to_zero
      rule   = "count-jp-pgadmin"
    }
    odoo = {
      policy = aws_appautoscaling_policy.odoo_idle_scale_to_zero
      rule   = "count-jp-odoo"
    }
    gitlab = {
      policy = aws_appautoscaling_policy.gitlab_idle_scale_to_zero
      rule   = "count-jp-gitlab"
    }
    zulip = {
      policy = aws_appautoscaling_policy.zulip_idle_scale_to_zero
      rule   = "count-jp-zulip"
    }
    keycloak = {
      policy = aws_appautoscaling_policy.keycloak_idle_scale_to_zero
      rule   = "count-jp-keycloak"
    }
  }
  service_control_autostop_alarm_configs = {
    for svc, cfg in local.service_control_autostop_alarm_sources : svc => {
      alarm_name = "${local.name_prefix}-${svc}-idle"
      rule_name  = cfg.rule
      policy_arn = length(cfg.policy) > 0 ? cfg.policy[0].arn : ""
    }
  }
  service_control_mysql_db_username_parameter_name = local.mysql_db_username_parameter_name
  service_control_mysql_db_password_parameter_name = local.mysql_db_password_parameter_name
}

data "archive_file" "service_control_lambda" {
  type        = "zip"
  source_file = "${path.module}/templates/service_control_lambda.py"
  output_path = "${path.module}/templates/service_control_lambda.zip"
}

data "archive_file" "service_control_scheduler" {
  type        = "zip"
  source_file = "${path.module}/templates/service_control_scheduler.py"
  output_path = "${path.module}/templates/service_control_scheduler.zip"
}

data "aws_iam_policy_document" "service_control_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service_control" {
  count              = local.service_control_enabled ? 1 : 0
  name               = local.service_control_lambda_role
  assume_role_policy = data.aws_iam_policy_document.service_control_assume.json

  tags = merge(local.tags, { Name = local.service_control_lambda_role })
}

data "aws_iam_policy_document" "service_control_inline" {
  count = local.service_control_enabled ? 1 : 0

  statement {
    actions = [
      "ecs:DescribeServices",
      "ecs:ListTagsForResource",
      "ecs:UpdateService",
      "ecs:DescribeTaskDefinition"
    ]
    resources = concat(
      local.service_control_api_service_arns,
      [local.service_control_api_cluster_arn]
    )
  }

  statement {
    actions   = ["ecs:ListTasks"]
    resources = ["*"]
  }

  statement {
    actions   = ["ecs:DescribeTasks"]
    resources = ["*"]
  }

  statement {
    actions = [
      "elasticloadbalancing:DescribeTargetHealth"
    ]
    # AWS may not honor resource-level permissions for DescribeTargetHealth; allow all to avoid AccessDenied.
    resources = ["*"]
  }

  statement {
    actions = [
      "ecs:DescribeTaskDefinition"
    ]
    resources = ["*"]
  }

  # ECR イメージタグ取得
  statement {
    actions = [
      "ecr:DescribeImages"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter"
    ]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.service_control_schedule_prefix}/*"]
  }
  statement {
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.keycloak_admin_username_parameter_name}",
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.keycloak_admin_password_parameter_name}",
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.odoo_admin_password_parameter_name}",
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.pgadmin_default_password_parameter_name}",
    ]
  }
}

resource "aws_iam_policy" "service_control" {
  count  = local.service_control_enabled ? 1 : 0
  name   = "${local.name_prefix}-svc-control"
  policy = data.aws_iam_policy_document.service_control_inline[0].json
}

resource "aws_iam_role_policy_attachment" "service_control_basic" {
  count      = local.service_control_enabled ? 1 : 0
  role       = aws_iam_role.service_control[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "service_control_inline" {
  count      = local.service_control_enabled ? 1 : 0
  role       = aws_iam_role.service_control[0].name
  policy_arn = aws_iam_policy.service_control[0].arn
}

resource "aws_ssm_parameter" "service_control_service_arns" {
  count     = local.service_control_enabled && var.create_ssm_parameters ? 1 : 0
  name      = "${local.service_control_schedule_prefix}/service-arns"
  type      = "String"
  value     = jsonencode(local.service_control_api_services)
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-control-service-arns" })
}

resource "aws_ssm_parameter" "service_control_target_group_arns" {
  count     = local.service_control_enabled && var.create_ssm_parameters ? 1 : 0
  name      = "${local.service_control_schedule_prefix}/target-group-arns"
  type      = "String"
  value     = jsonencode(local.service_control_target_groups)
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-control-tg-arns" })
}

resource "aws_ssm_parameter" "service_control_autostop_alarms" {
  count = local.service_control_enabled && var.create_ssm_parameters ? 1 : 0
  name  = "${local.service_control_schedule_prefix}/autostop-alarms"
  type  = "String"
  value = jsonencode(
    {
      for svc, cfg in local.service_control_autostop_alarm_configs : svc => {
        alarm_name = cfg.alarm_name
        rule_name  = cfg.rule_name
        policy_arn = cfg.policy_arn
      } if cfg.policy_arn != ""
    }
  )
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-control-autostop-alarms" })
}

resource "aws_lambda_function" "service_control" {
  count = local.service_control_enabled ? 1 : 0

  function_name                  = local.service_control_lambda_name
  role                           = aws_iam_role.service_control[0].arn
  handler                        = "service_control_lambda.handler"
  runtime                        = "python3.12"
  timeout                        = 10
  reserved_concurrent_executions = var.service_control_lambda_reserved_concurrency

  filename         = data.archive_file.service_control_lambda.output_path
  source_code_hash = data.archive_file.service_control_lambda.output_base64sha256

  environment {
    variables = merge(
      {
        CLUSTER_ARN                           = local.service_control_api_cluster_arn
        START_DESIRED                         = "1"
        SERVICE_CONTROL_SSM_PATH              = local.service_control_schedule_prefix
        SERVICE_CONTROL_DEFAULT_REALM         = coalesce(local.sulu_primary_realm, "")
        KEYCLOAK_ADMIN_USERNAME_SSM_PARAMETER = local.keycloak_admin_username_parameter_name
        KEYCLOAK_ADMIN_PASSWORD_SSM_PARAMETER = local.keycloak_admin_password_parameter_name
        ODOO_ADMIN_USERNAME                   = "admin"
        ODOO_ADMIN_PASSWORD_SSM_PARAMETER     = local.odoo_admin_password_parameter_name
        PGADMIN_ADMIN_USERNAME                = "admin@${local.hosted_zone_name_input}"
        PGADMIN_PASSWORD_SSM_PARAMETER        = local.pgadmin_default_password_parameter_name
      },
      var.create_ssm_parameters ? {
        SERVICE_ARNS_SSM_PARAMETER      = aws_ssm_parameter.service_control_service_arns[0].name
        TARGET_GROUP_ARNS_SSM_PARAMETER = aws_ssm_parameter.service_control_target_group_arns[0].name
        } : {
        SERVICE_ARNS      = jsonencode(local.service_control_api_services)
        TARGET_GROUP_ARNS = jsonencode(local.service_control_target_groups)
      }
    )
  }

  tags = merge(local.tags, { Name = local.service_control_lambda_name })
}

resource "aws_lambda_function" "service_control_scheduler" {
  count = local.service_control_enabled ? 1 : 0

  function_name = "${local.name_prefix}-svc-control-scheduler"
  role          = aws_iam_role.service_control[0].arn
  handler       = "service_control_scheduler.handler"
  runtime       = "python3.12"
  timeout       = 60

  filename         = data.archive_file.service_control_scheduler.output_path
  source_code_hash = data.archive_file.service_control_scheduler.output_base64sha256

  environment {
    variables = merge(
      {
        CLUSTER_ARN                                       = local.service_control_api_cluster_arn
        SERVICE_CONTROL_SERVICE_KEYS                      = jsonencode(keys(local.service_control_api_services))
        SERVICE_CONTROL_NAME_PREFIX                       = local.name_prefix
        SERVICE_CONTROL_SCHEDULE_SERVICES                 = jsonencode(local.service_control_services)
        SERVICE_CONTROL_SSM_PATH                          = local.service_control_schedule_prefix
        START_DESIRED                                     = "1"
        SERVICE_CONTROL_AUTOSTOP_ALARM_PERIOD_SECONDS     = tostring(local.service_control_alarm_period_seconds)
        SERVICE_CONTROL_AUTOSTOP_ALARM_REGION             = var.region
        SERVICE_CONTROL_AUTOSTOP_WAF_NAME                 = try(aws_wafv2_web_acl.alb[0].name, "")
        SERVICE_CONTROL_AUTOSTOP_ALARM_TREAT_MISSING_DATA = "breaching"
      },
      var.create_ssm_parameters ? {
        SERVICE_ARNS_SSM_PARAMETER                    = aws_ssm_parameter.service_control_service_arns[0].name
        SERVICE_CONTROL_AUTOSTOP_ALARMS_SSM_PARAMETER = aws_ssm_parameter.service_control_autostop_alarms[0].name
        } : {
        SERVICE_CONTROL_AUTOSTOP_POLICY_ARNS = jsonencode(
          { for svc, cfg in local.service_control_autostop_alarm_configs : svc => cfg.policy_arn if cfg.policy_arn != "" }
        )
      }
    )
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-control-scheduler" })
}

resource "aws_cloudwatch_event_rule" "service_control_scheduler" {
  count = local.service_control_enabled ? 1 : 0

  name                = "${local.name_prefix}-svc-control-scheduler"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "service_control_scheduler" {
  count     = local.service_control_enabled ? 1 : 0
  rule      = aws_cloudwatch_event_rule.service_control_scheduler[0].name
  target_id = "service-control-scheduler"
  arn       = aws_lambda_function.service_control_scheduler[0].arn
  input     = "{}"
}

resource "aws_lambda_permission" "service_control_scheduler" {
  count         = local.service_control_enabled ? 1 : 0
  statement_id  = "AllowEventBridgeInvokeServiceControlScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.service_control_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.service_control_scheduler[0].arn
}

resource "aws_cloudwatch_log_group" "service_control_api" {
  count = local.service_control_enabled ? 1 : 0

  name              = local.service_control_api_log_group
  retention_in_days = 30

  tags = merge(local.tags, { Name = "${local.service_control_api_name}-api-logs" })
}

resource "aws_apigatewayv2_api" "service_control" {
  count = local.service_control_enabled ? 1 : 0

  name          = local.service_control_api_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
    allow_headers = ["*"]
  }

  tags = merge(local.tags, { Name = local.service_control_api_name })
}

resource "aws_apigatewayv2_authorizer" "service_control_jwt" {
  count = local.service_control_enabled && local.service_control_jwt_enabled ? 1 : 0

  api_id          = aws_apigatewayv2_api.service_control[0].id
  authorizer_type = "JWT"
  identity_sources = [
    "$request.header.Authorization"
  ]
  name = "${local.name_prefix}-svc-control-jwt"

  jwt_configuration {
    issuer   = var.service_control_jwt_issuer
    audience = local.service_control_jwt_audiences_effective
  }
}

resource "aws_apigatewayv2_integration" "service_control" {
  count = local.service_control_enabled ? 1 : 0

  api_id                 = aws_apigatewayv2_api.service_control[0].id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.service_control[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "service_control" {
  for_each = local.service_control_enabled ? {
    "GET /status" = {
      route = "GET /status"
    }
    "POST /start" = {
      route = "POST /start"
    }
    "POST /stop" = {
      route = "POST /stop"
    }
    "GET /schedule" = {
      route = "GET /schedule"
    }
    "POST /schedule" = {
      route = "POST /schedule"
    }
    "GET /odoo-admin-credentials" = {
      route = "GET /odoo-admin-credentials"
    }
    "GET /keycloak-admin-credentials" = {
      route = "GET /keycloak-admin-credentials"
    }
    "GET /pgadmin-admin-credentials" = {
      route = "GET /pgadmin-admin-credentials"
    }
  } : {}

  api_id             = aws_apigatewayv2_api.service_control[0].id
  route_key          = each.value.route
  target             = "integrations/${aws_apigatewayv2_integration.service_control[0].id}"
  authorization_type = local.service_control_jwt_enabled ? "JWT" : "NONE"
  authorizer_id      = local.service_control_jwt_enabled ? aws_apigatewayv2_authorizer.service_control_jwt[0].id : null
}

resource "aws_apigatewayv2_stage" "service_control" {
  count = local.service_control_enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.service_control[0].id
  name        = local.service_control_api_stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.service_control_api[0].arn
    format = jsonencode({
      requestId          = "$context.requestId"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      path               = "$context.path"
      status             = "$context.status"
      integrationError   = "$context.integrationErrorMessage"
      errorMessage       = "$context.error.message"
      errorMessageString = "$context.error.messageString"
      routeKey           = "$context.routeKey"
      integrationStatus  = "$context.integrationStatus"
      responseLength     = "$context.responseLength"
      userAgent          = "$context.identity.userAgent"
      sourceIp           = "$context.identity.sourceIp"
    })
  }

  tags = merge(local.tags, { Name = "${local.service_control_api_name}-stage" })
}

resource "aws_lambda_permission" "service_control" {
  count = local.service_control_enabled ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeServiceControl"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.service_control[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.service_control[0].execution_arn}/*/*"
}
