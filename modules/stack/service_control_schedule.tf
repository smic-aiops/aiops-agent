locals {
  service_control_services = compact([
    "keycloak",
    "zulip",
    "odoo",
    "n8n",
    "sulu",
    local.exastro_service_enabled ? "exastro" : "",
    "gitlab",
    "pgadmin"
  ])
  service_control_ssm_path = "/${local.name_prefix}/service-control"
  default_service_control_schedule = {
    for svc in local.service_control_services : svc => {
      enabled            = contains(["keycloak", "n8n", "zulip"], svc)
      start_time         = "17:00"
      stop_time          = "22:00"
      weekday_start_time = "17:00"
      weekday_stop_time  = "22:00"
      holiday_start_time = "08:00"
      holiday_stop_time  = "23:00"
      idle_minutes       = 60
    }
  }
  service_control_schedule_map = merge(local.default_service_control_schedule, var.service_control_schedule_overrides)
}

data "aws_ssm_parameters_by_path" "service_control_schedule" {
  count           = var.create_ecs && var.create_ssm_parameters ? 1 : 0
  path            = local.service_control_ssm_path
  recursive       = true
  with_decryption = true
}

locals {
  # 既存の SSM パラメータを上書きするかどうかはフラグで制御
  existing_service_control_schedules = var.create_ecs && var.create_ssm_parameters ? {
    for name, value in zipmap(
      data.aws_ssm_parameters_by_path.service_control_schedule[0].names,
      data.aws_ssm_parameters_by_path.service_control_schedule[0].values
    ) :
    replace(replace(name, "${local.service_control_ssm_path}/", ""), "/schedule", "") => jsondecode(value)
    if length(regexall("/schedule$", name)) > 0
  } : {}

  effective_service_control_schedule = {
    for svc, schedule in local.service_control_schedule_map :
    svc => var.service_control_schedule_overwrite ? schedule : lookup(local.existing_service_control_schedules, svc, schedule)
  }
}

resource "aws_ssm_parameter" "service_control_schedule" {
  for_each = var.create_ecs && var.create_ssm_parameters ? local.service_control_schedule_map : {}

  name      = "${local.service_control_ssm_path}/${each.key}/schedule"
  type      = "String"
  value     = jsonencode(local.effective_service_control_schedule[each.key])
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-control-${each.key}-schedule" })
}
