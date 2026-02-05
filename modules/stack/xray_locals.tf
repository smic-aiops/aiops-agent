locals {
  xray_services_set = toset(var.xray_services)
  xray_enabled_services = [
    for service in local.enabled_services :
    service if contains(local.xray_services_set, service)
  ]
  xray_enabled = var.create_ecs && length(local.xray_enabled_services) > 0
}
