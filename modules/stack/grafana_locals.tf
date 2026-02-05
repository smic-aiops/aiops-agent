locals {
  grafana_realms        = length(var.realms) > 0 ? var.realms : [local.keycloak_realm_effective]
  grafana_primary_realm = try(local.grafana_realms[0], null)
  grafana_realms_csv    = join(" ", local.grafana_realms)
  grafana_subdomain     = local.service_subdomain_map["grafana"]
  grafana_realm_hosts = {
    for realm in local.grafana_realms :
    realm => "${realm}.${local.grafana_subdomain}.${local.hosted_zone_name_input}"
  }
  grafana_primary_host = local.grafana_primary_realm != null ? local.grafana_realm_hosts[local.grafana_primary_realm] : null
  grafana_realm_ports = {
    for idx, realm in local.grafana_realms :
    realm => 3000 + idx
  }
  grafana_listener_priority_by_realm = {
    for idx, realm in local.grafana_realms :
    realm => 620 + idx
  }
  grafana_target_group_name_by_realm = {
    for realm in local.grafana_realms :
    realm => "${local.name_prefix}-grafana-${realm}-tg"
  }
  grafana_realm_db_names = {
    for realm in local.grafana_realms :
    realm => "grafana_${realm}"
  }
  grafana_realm_paths = {
    for realm in local.grafana_realms :
    realm => "${var.grafana_filesystem_path}/${realm}"
  }
  grafana_serve_from_sub_path_effective = var.grafana_serve_from_sub_path
  grafana_realm_root_urls = {
    for realm, host in local.grafana_realm_hosts :
    realm => (var.grafana_root_url != null && var.grafana_root_url != "" && length(local.grafana_realms) == 1 ? var.grafana_root_url : "https://${host}/")
  }
  grafana_realm_domains = {
    for realm, host in local.grafana_realm_hosts :
    realm => (var.grafana_domain != null && var.grafana_domain != "" && length(local.grafana_realms) == 1 ? var.grafana_domain : host)
  }
}
