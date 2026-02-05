locals {
  sulu_realms        = length(var.realms) > 0 ? var.realms : [local.keycloak_realm_effective]
  sulu_primary_realm = try(local.sulu_realms[0], null)
  sulu_realms_csv    = join(" ", local.sulu_realms)
  sulu_realm_hosts   = { for realm in local.sulu_realms : realm => "${realm}.${local.service_subdomain_map["sulu"]}.${local.hosted_zone_name_input}" }
  sulu_primary_host  = local.sulu_primary_realm != null ? local.sulu_realm_hosts[local.sulu_primary_realm] : null
  sulu_listener_priority_by_realm = {
    for idx, realm in local.sulu_realms :
    realm => 30 + idx
  }
  sulu_realm_ports = {
    for idx, realm in local.sulu_realms :
    realm => 8080 + idx
  }
  sulu_realm_fpm_ports = {
    for idx, realm in local.sulu_realms :
    realm => 9000 + idx
  }
  sulu_target_group_name_by_realm = {
    for realm in local.sulu_realms :
    realm => "${local.name_prefix}-sulu-${realm}-tg"
  }
  sulu_realm_paths = {
    for realm in local.sulu_realms :
    realm => "${var.sulu_filesystem_path}/${realm}"
  }
  sulu_realm_db_schemas = {
    for realm in local.sulu_realms :
    realm => lower(replace(realm, "/[^0-9A-Za-z_]/", "_"))
  }
}
