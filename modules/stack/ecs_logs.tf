locals {
  ecs_logs_per_container_services = toset(local.enabled_services)

  ecs_default_realm        = local.default_realm
  ecs_n8n_shared_realm     = coalesce(local.n8n_primary_realm, local.ecs_default_realm)
  ecs_grafana_shared_realm = coalesce(local.grafana_primary_realm, local.ecs_default_realm)
  ecs_sulu_shared_realm    = coalesce(local.sulu_primary_realm, local.ecs_default_realm)

  n8n_has_efs_effective = (
    trimspace(coalesce(var.n8n_filesystem_id, "")) != "" ||
    local.create_n8n_efs_effective ||
    local.n8n_existing_efs_id != null
  )
  exastro_has_efs_effective = (
    trimspace(coalesce(var.exastro_filesystem_id, "")) != "" ||
    local.create_exastro_efs_effective ||
    local.exastro_existing_efs_id != null
  )
  sulu_has_efs_effective = (
    trimspace(coalesce(var.sulu_filesystem_id, "")) != "" ||
    local.create_sulu_efs_effective ||
    local.sulu_existing_efs_id != null
  )
  keycloak_has_efs_effective = (
    trimspace(coalesce(var.keycloak_filesystem_id, "")) != "" ||
    local.create_keycloak_efs_effective ||
    local.keycloak_existing_efs_id != null
  )
  pgadmin_has_efs_effective = (
    trimspace(coalesce(var.pgadmin_filesystem_id, "")) != "" ||
    local.create_pgadmin_efs_effective ||
    local.pgadmin_existing_efs_id != null
  )
  grafana_has_efs_effective = (
    trimspace(coalesce(var.grafana_filesystem_id, "")) != "" ||
    local.create_grafana_efs_effective ||
    local.grafana_existing_efs_id != null
  )
  zulip_has_efs_effective = (
    trimspace(coalesce(var.zulip_filesystem_id, "")) != "" ||
    local.create_zulip_efs_effective ||
    local.zulip_existing_efs_id != null
  )
  gitlab_has_efs_effective = (
    trimspace(coalesce(var.gitlab_data_filesystem_id, "")) != "" ||
    trimspace(coalesce(var.gitlab_config_filesystem_id, "")) != "" ||
    local.create_gitlab_data_efs_effective ||
    local.create_gitlab_config_efs_effective ||
    local.gitlab_data_existing_efs_id != null ||
    local.gitlab_config_existing_efs_id != null
  )

  ecs_container_defs_by_service = {
    n8n = contains(local.enabled_services, "n8n") ? concat(
      local.n8n_has_efs_effective ? [{ name = "n8n-fs-init", realm = local.ecs_n8n_shared_realm }] : [],
      [{ name = "n8n-db-init", realm = local.ecs_n8n_shared_realm }],
      contains(local.xray_services_set, "n8n") ? [
        { name = "xray-daemon-${local.ecs_n8n_shared_realm}", realm = local.ecs_n8n_shared_realm }
      ] : [],
      (local.n8n_qdrant_enabled && local.n8n_has_efs_effective) ? [for realm in local.n8n_realms : { name = "qdrant-${realm}", realm = realm }] : [],
      [for realm in local.n8n_realms : { name = "n8n-${realm}", realm = realm }]
    ) : []
    exastro = contains(local.enabled_services, "exastro") ? concat(
      local.exastro_has_efs_effective ? [{ name = "exastro-fs-init", realm = local.ecs_default_realm }] : [],
      [
        { name = "exastro-web", realm = local.ecs_default_realm },
        { name = "exastro-api", realm = local.ecs_default_realm }
      ]
    ) : []
    sulu = contains(local.enabled_services, "sulu") ? concat(
      local.sulu_has_efs_effective ? [{ name = "sulu-fs-init", realm = local.ecs_sulu_shared_realm }] : [],
      [
        { name = "redis", realm = local.ecs_sulu_shared_realm }
      ],
      [for realm in local.sulu_realms : { name = "loupe-indexer-${realm}", realm = realm }],
      [for realm in local.sulu_realms : { name = "init-db-${realm}", realm = realm }],
      [for realm in local.sulu_realms : { name = "php-fpm-${realm}", realm = realm }],
      [for realm in local.sulu_realms : { name = "nginx-${realm}", realm = realm }]
    ) : []
    keycloak = contains(local.enabled_services, "keycloak") ? concat(
      local.keycloak_has_efs_effective ? [{ name = "keycloak-fs-init", realm = local.ecs_default_realm }] : [],
      [
        { name = "keycloak-db-init", realm = local.ecs_default_realm },
        { name = "keycloak-realm-import", realm = local.ecs_default_realm },
        { name = "keycloak", realm = local.ecs_default_realm }
      ]
    ) : []
    odoo = contains(local.enabled_services, "odoo") ? [
      { name = "odoo-db-init", realm = local.ecs_default_realm },
      { name = "odoo", realm = local.ecs_default_realm }
    ] : []
    gitlab = contains(local.enabled_services, "gitlab") ? concat(
      local.gitlab_has_efs_effective ? [{ name = "gitlab-fs-init", realm = local.ecs_default_realm }] : [],
      [
        { name = "gitlab-db-init", realm = local.ecs_default_realm },
        { name = "gitlab", realm = local.ecs_default_realm }
      ]
    ) : []
    grafana = contains(local.enabled_services, "grafana") ? concat(
      local.grafana_has_efs_effective ? [{ name = "grafana-fs-init", realm = local.ecs_grafana_shared_realm }] : [],
      [{ name = "grafana-db-init", realm = local.ecs_grafana_shared_realm }],
      contains(local.xray_services_set, "grafana") ? [
        { name = "xray-daemon-${local.ecs_grafana_shared_realm}", realm = local.ecs_grafana_shared_realm }
      ] : [],
      [for realm in local.grafana_realms : { name = "grafana-${realm}", realm = realm }]
    ) : []
    pgadmin = contains(local.enabled_services, "pgadmin") ? concat(
      local.pgadmin_has_efs_effective ? [{ name = "pgadmin-fs-init", realm = local.ecs_default_realm }] : [],
      [{ name = "pgadmin", realm = local.ecs_default_realm }]
    ) : []
    zulip = contains(local.enabled_services, "zulip") ? concat(
      local.zulip_has_efs_effective ? [{ name = "zulip-fs-init", realm = local.ecs_default_realm }] : [],
      [
        { name = "zulip-db-init", realm = local.ecs_default_realm },
        { name = "zulip-memcached", realm = local.ecs_default_realm },
        { name = "zulip-redis", realm = local.ecs_default_realm },
        { name = "zulip-rabbitmq", realm = local.ecs_default_realm },
        { name = "zulip", realm = local.ecs_default_realm }
      ]
    ) : []
  }

  ecs_container_log_group_maps = [
    for service, containers in local.ecs_container_defs_by_service :
    contains(local.ecs_logs_per_container_services, service) && length(containers) > 0 ? {
      for container in containers :
      "${service}--${container.name}" => {
        service   = service
        container = container.name
        realm     = container.realm
        name      = "/aws/ecs/${container.realm}/${local.name_prefix}-${service}/${container.name}"
      }
    } : {}
  ]

  ecs_container_log_groups = length(local.ecs_container_log_group_maps) > 0 ? merge(local.ecs_container_log_group_maps...) : {}
  ecs_log_group_name_by_container = {
    for key, entry in local.ecs_container_log_groups : key => entry.name
  }
  ecs_logs_per_container_services_effective = sort(local.enabled_services)
  ecs_service_log_group_realm_by_service = {
    n8n      = local.ecs_n8n_shared_realm
    exastro  = local.ecs_default_realm
    sulu     = local.ecs_sulu_shared_realm
    keycloak = local.ecs_default_realm
    odoo     = local.ecs_default_realm
    pgadmin  = local.ecs_default_realm
    gitlab   = local.ecs_default_realm
    grafana  = local.ecs_grafana_shared_realm
    zulip    = local.ecs_default_realm
  }
  ecs_container_log_groups_by_realm_service = {
    for realm_service in distinct([
      for _, entry in local.ecs_container_log_groups : "${entry.realm}::${entry.service}"
    ]) :
    realm_service => [
      for _, entry in local.ecs_container_log_groups :
      entry.name if "${entry.realm}::${entry.service}" == realm_service
    ]
  }
  ecs_service_log_group_map_base = {
    for service in local.enabled_services :
    "${lookup(local.ecs_service_log_group_realm_by_service, service, local.ecs_default_realm)}::${service}" => {
      realm   = lookup(local.ecs_service_log_group_realm_by_service, service, local.ecs_default_realm)
      service = service
      name    = "/aws/ecs/${lookup(local.ecs_service_log_group_realm_by_service, service, local.ecs_default_realm)}/${local.name_prefix}-${service}"
    }
  }
  ecs_service_log_group_pairs_additional = toset(concat(
    contains(local.enabled_services, "n8n") ? [for realm in local.n8n_realms : "${realm}::n8n"] : [],
    contains(local.enabled_services, "sulu") ? [for realm in local.sulu_realms : "${realm}::sulu"] : [],
    contains(local.enabled_services, "grafana") ? [for realm in local.grafana_realms : "${realm}::grafana"] : [],
  ))
  ecs_service_log_group_extra_candidates = {
    for realm_service in local.ecs_service_log_group_pairs_additional :
    realm_service => {
      realm   = split("::", realm_service)[0]
      service = split("::", realm_service)[1]
      name    = "/aws/ecs/${split("::", realm_service)[0]}/${local.name_prefix}-${split("::", realm_service)[1]}"
    } if !contains(keys(local.ecs_service_log_group_map_base), realm_service)
  }
  ecs_service_log_group_map = merge(local.ecs_service_log_group_map_base, local.ecs_service_log_group_extra_candidates)
  ecs_log_destinations_by_realm_service = {
    for realm_service, entry in local.ecs_service_log_group_map :
    realm_service => {
      realm                = entry.realm
      service              = entry.service
      service_log_group    = entry.name
      container_log_groups = lookup(local.ecs_container_log_groups_by_realm_service, realm_service, [])
    }
  }
  ecs_log_destinations_by_realm = {
    for realm in distinct([
      for _, entry in local.ecs_log_destinations_by_realm_service : entry.realm
    ]) :
    realm => {
      for _, entry in local.ecs_log_destinations_by_realm_service :
      entry.service => {
        service_log_group    = entry.service_log_group
        container_log_groups = entry.container_log_groups
      } if entry.realm == realm
    }
  }
}

resource "aws_cloudwatch_log_group" "ecs_container" {
  for_each = local.ecs_container_log_groups

  name              = each.value.name
  retention_in_days = var.ecs_logs_retention_days

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.value.service}-${each.value.container}-logs" })
}

resource "aws_cloudwatch_log_group" "ecs_service_realm" {
  for_each = local.ecs_service_log_group_extra_candidates

  name              = each.value.name
  retention_in_days = var.ecs_logs_retention_days

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.value.service}-logs" })
}
