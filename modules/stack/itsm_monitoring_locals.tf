locals {
  monitoring_yaml_effective = var.monitoring_yaml != null ? trimspace(var.monitoring_yaml) : ""

  monitoring_config = local.monitoring_yaml_effective != "" ? try(yamldecode(local.monitoring_yaml_effective), {}) : {}

  monitoring_realms_raw = try(local.monitoring_config.realms, {})
  monitoring_default    = try(local.monitoring_realms_raw.default, {})

  monitoring_realms_effective = {
    for realm in local.n8n_realms :
    realm => merge(local.monitoring_default, try(local.monitoring_realms_raw[realm], {}))
  }

  itsm_event_inbox_grafana_by_realm = {
    for realm, cfg in local.monitoring_realms_effective :
    realm => {
      dashboard_uid   = try(cfg.grafana.itsm_event_inbox.dashboard_uid, null)
      dashboard_title = try(cfg.grafana.itsm_event_inbox.dashboard_title, null)
      panel_id        = try(cfg.grafana.itsm_event_inbox.panel_id, null)
      panel_title     = try(cfg.grafana.itsm_event_inbox.panel_title, null)
      tags            = try(cfg.grafana.itsm_event_inbox.tags, null)
    }
    if try(cfg.grafana.itsm_event_inbox, null) != null
  }

  n8n_grafana_event_inbox_env_by_realm = {
    for realm, inbox in local.itsm_event_inbox_grafana_by_realm :
    realm => merge(
      inbox.dashboard_uid != null && trimspace(tostring(inbox.dashboard_uid)) != "" ? { GRAFANA_DASHBOARD_UID = tostring(inbox.dashboard_uid) } : {},
      inbox.panel_id != null ? { GRAFANA_PANEL_ID = tostring(inbox.panel_id) } : {},
      inbox.tags != null && trimspace(tostring(inbox.tags)) != "" ? { GRAFANA_TAGS = tostring(inbox.tags) } : {},
    )
  }

  itsm_monitoring_context_by_realm = {
    for realm, cfg in local.monitoring_realms_effective :
    realm => cfg
    if length(cfg) > 0
  }

  itsm_monitoring_context_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/itsm/monitoring_context/${realm}"
  }
}

