locals {
  horilla_realms        = length(var.realms) > 0 ? var.realms : [local.keycloak_realm_effective]
  horilla_primary_realm = try(local.horilla_realms[0], null)
  horilla_realms_csv    = join(" ", local.horilla_realms)

  # <realm>.horilla.<domain>
  horilla_realm_hosts = {
    for realm in local.horilla_realms :
    realm => "${realm}.${local.service_subdomain_map["horilla"]}.${local.hosted_zone_name_input}"
  }
  horilla_primary_host = local.horilla_primary_realm != null ? local.horilla_realm_hosts[local.horilla_primary_realm] : null

  # Keep priorities away from existing rules (gitlab/grafana/zulip ranges).
  horilla_listener_priority_by_realm = {
    for idx, realm in local.horilla_realms :
    realm => 140 + idx
  }

  horilla_target_group_name_by_realm = {
    for realm in local.horilla_realms :
    realm => "${local.name_prefix}-horilla-${realm}-tg"
  }

  # One DB per realm by default (created by a db-init sidecar).
  horilla_realm_db_names = {
    for realm in local.horilla_realms :
    realm => lower(substr("${var.horilla_db_name_prefix}_${realm}", 0, 63))
  }
}

