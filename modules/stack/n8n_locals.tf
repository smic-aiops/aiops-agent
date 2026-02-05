locals {
  n8n_realms                                  = length(var.realms) > 0 ? var.realms : [local.keycloak_realm_effective]
  n8n_primary_realm                           = try(local.n8n_realms[0], null)
  n8n_realms_csv                              = join(" ", local.n8n_realms)
  n8n_use_realm_suffix                        = length(local.n8n_realms) > 1
  n8n_subdomain                               = local.service_subdomain_map["n8n"]
  n8n_realm_hosts                             = { for realm in local.n8n_realms : realm => "${realm}.${local.n8n_subdomain}.${local.hosted_zone_name_input}" }
  n8n_primary_host                            = local.n8n_primary_realm != null ? local.n8n_realm_hosts[local.n8n_primary_realm] : null
  n8n_realm_ports                             = { for idx, realm in local.n8n_realms : realm => 5678 + idx }
  n8n_qdrant_enabled                          = var.enable_n8n_qdrant
  qdrant_subdomain                            = local.service_subdomain_map["qdrant"]
  qdrant_realm_hosts                          = { for realm in local.n8n_realms : realm => "${realm}.${local.qdrant_subdomain}.${local.hosted_zone_name_input}" }
  qdrant_primary_host                         = local.n8n_primary_realm != null ? local.qdrant_realm_hosts[local.n8n_primary_realm] : null
  qdrant_realm_http_ports                     = { for idx, realm in local.n8n_realms : realm => 6333 + (idx * 2) }
  qdrant_realm_grpc_ports                     = { for idx, realm in local.n8n_realms : realm => 6334 + (idx * 2) }
  qdrant_realm_paths                          = { for realm in local.n8n_realms : realm => "${var.n8n_filesystem_path}/qdrant/${realm}" }
  n8n_encryption_key_parameter_names_by_realm = { for realm in local.n8n_realms : realm => "/${local.name_prefix}/n8n/encryption_key/${realm}" }
  n8n_listener_priority_by_realm              = { for idx, realm in local.n8n_realms : realm => 200 + idx }
  qdrant_listener_priority_by_realm           = { for idx, realm in local.n8n_realms : realm => 260 + idx }
  n8n_target_group_name_by_realm              = { for realm in local.n8n_realms : realm => "${local.name_prefix}-n8n-${realm}-tg" }
  n8n_realm_db_names                          = { for realm in local.n8n_realms : realm => (local.n8n_use_realm_suffix ? "${var.n8n_db_name}_${realm}" : var.n8n_db_name) }
  n8n_realm_db_schemas                        = { for realm in local.n8n_realms : realm => lower(replace(realm, "/[^0-9A-Za-z_]/", "_")) }
  n8n_realm_paths                             = { for realm in local.n8n_realms : realm => (local.n8n_use_realm_suffix ? "${var.n8n_filesystem_path}/${realm}" : var.n8n_filesystem_path) }
  aiops_agent_environment_default             = try(lookup(var.aiops_agent_environment, "default", {}), {})
  aiops_agent_environment_raw_by_realm = {
    for realm in local.n8n_realms :
    realm => merge(
      local.aiops_agent_environment_default,
      try(lookup(var.aiops_agent_environment, realm, {}), {})
    )
  }
  openai_model_api_key_by_realm = {
    for realm, envs in local.aiops_agent_environment_raw_by_realm :
    realm => try(envs.OPENAI_MODEL_API_KEY, null)
  }
  openai_model_by_realm = {
    for realm, envs in local.aiops_agent_environment_raw_by_realm :
    realm => try(envs.OPENAI_MODEL, null)
  }
  openai_base_url_by_realm = {
    for realm, envs in local.aiops_agent_environment_raw_by_realm :
    realm => try(envs.OPENAI_BASE_URL, null)
  }
  openai_model_api_key_by_realm_effective = {
    for realm, key in local.openai_model_api_key_by_realm :
    realm => key
    if key != null && trimspace(key) != ""
  }
  openai_model_by_realm_effective = {
    for realm, value in local.openai_model_by_realm :
    realm => value
    if value != null && trimspace(value) != ""
  }
  openai_base_url_by_realm_effective = {
    for realm, value in local.openai_base_url_by_realm :
    realm => value
    if value != null && trimspace(value) != ""
  }
  openai_model_api_key_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/aiops/openai/api_key/${realm}"
  }
  openai_model_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/aiops/openai/model/${realm}"
  }
  openai_base_url_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/aiops/openai/base_url/${realm}"
  }
  openai_model_api_key_env_by_realm = {
    for realm, key in local.openai_model_api_key_by_realm_effective :
    realm => { OPENAI_MODEL_API_KEY = local.openai_model_api_key_parameter_names_by_realm[realm] }
  }
  openai_model_env_by_realm = {
    for realm, value in local.openai_model_by_realm_effective :
    realm => { OPENAI_MODEL = local.openai_model_parameter_names_by_realm[realm] }
  }
  openai_base_url_env_by_realm = {
    for realm, value in local.openai_base_url_by_realm_effective :
    realm => { OPENAI_BASE_URL = local.openai_base_url_parameter_names_by_realm[realm] }
  }
  aiops_agent_environment_by_realm = {
    for realm, envs in local.aiops_agent_environment_raw_by_realm :
    realm => {
      for k, v in envs :
      k => v
      if k != "OPENAI_MODEL_API_KEY" && k != "OPENAI_MODEL" && k != "OPENAI_BASE_URL"
    }
  }
  aiops_s3_bucket_default_prefix = lower(replace(
    "${local.name_prefix}-${var.region}-${data.aws_caller_identity.current.account_id}-aiops",
    "/[^0-9a-z-]/",
    "-"
  ))
  aiops_s3_bucket_names_by_realm = {
    for realm in local.n8n_realms :
    realm => (
      lookup(var.aiops_s3_bucket_names, realm, null) != null
      ? lookup(var.aiops_s3_bucket_names, realm, null)
      : substr(lower(replace("${local.aiops_s3_bucket_default_prefix}-${realm}", "/[^0-9a-z-]/", "-")), 0, 63)
    )
  }
  aiops_approval_base_url_value_by_realm = {
    for realm, host in local.n8n_realm_hosts :
    realm => "https://${host}/webhook"
  }
  alb_dns_name_effective = try(aws_lb.app[0].dns_name, null)
  aiops_adapter_base_url_value_by_realm = local.alb_dns_name_effective != null ? {
    for realm, port in local.n8n_realm_ports :
    realm => "http://${local.alb_dns_name_effective}:${port}/webhook"
  } : {}
  aiops_s3_bucket_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "${coalesce(var.aiops_s3_bucket_parameter_name_prefix, "/${local.name_prefix}/n8n/aiops/s3_bucket/")}${realm}"
  }
  aiops_adapter_base_url_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/aiops/adapter_base_url/${realm}"
  }
  aiops_approval_base_url_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/aiops/approval_base_url/${realm}"
  }
  aiops_approval_hmac_secret_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/aiops/approval_hmac_secret/${realm}"
  }
  aiops_cloudwatch_webhook_secret_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/aiops/cloudwatch_webhook_secret/${realm}"
  }
  gitlab_service_projects_path_by_realm = {
    for realm in local.n8n_realms :
    realm => "${realm}/service-management"
  }
  gitlab_general_projects_path_by_realm = {
    for realm in local.n8n_realms :
    realm => "${realm}/general-management"
  }
  gitlab_technical_projects_path_by_realm = {
    for realm in local.n8n_realms :
    realm => "${realm}/technical-management"
  }
  grafana_api_token_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/grafana/api_token/${realm}"
  }
  grafana_api_token_by_realm = {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(var.grafana_api_tokens_by_realm, realm, null),
        lookup(var.grafana_api_tokens_by_realm, "default", null)
      ])[0],
      null
    )
  }
  grafana_api_token_by_realm_effective = {
    for realm, token in local.grafana_api_token_by_realm :
    realm => token
    if token != null && trimspace(token) != ""
  }
  aiops_ingest_limits_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => {
      N8N_INGEST_RATE_LIMIT_RPS    = "/${local.name_prefix}/n8n/aiops/ingest_rate_limit_rps/${realm}"
      N8N_INGEST_BURST_RPS         = "/${local.name_prefix}/n8n/aiops/ingest_burst_rps/${realm}"
      N8N_TENANT_RATE_LIMIT_RPS    = "/${local.name_prefix}/n8n/aiops/tenant_rate_limit_rps/${realm}"
      N8N_INGEST_PAYLOAD_MAX_BYTES = "/${local.name_prefix}/n8n/aiops/ingest_payload_max_bytes/${realm}"
    }
  }
  n8n_ssm_params_auto_by_realm = {
    for realm in local.n8n_realms :
    realm => merge(
      {
        N8N_S3_BUCKET                 = local.aiops_s3_bucket_parameter_names_by_realm[realm]
        N8N_ADAPTER_BASE_URL          = local.aiops_adapter_base_url_parameter_names_by_realm[realm]
        N8N_APPROVAL_BASE_URL         = local.aiops_approval_base_url_parameter_names_by_realm[realm]
        N8N_APPROVAL_HMAC_SECRET_NAME = local.aiops_approval_hmac_secret_parameter_names_by_realm[realm]
        N8N_CLOUDWATCH_WEBHOOK_SECRET = local.aiops_cloudwatch_webhook_secret_parameter_names_by_realm[realm]
        GRAFANA_API_KEY               = local.grafana_api_token_parameter_names_by_realm[realm]
        N8N_ENCRYPTION_KEY            = local.n8n_encryption_key_parameter_names_by_realm[realm]
      },
      lookup(local.zulip_admin_api_key_ssm_params_by_realm, realm, {}),
      lookup(local.aiops_zulip_ssm_params_by_realm, realm, {}),
      lookup(local.openai_model_api_key_env_by_realm, realm, {}),
      lookup(local.openai_model_env_by_realm, realm, {}),
      lookup(local.openai_base_url_env_by_realm, realm, {}),
      lookup(local.aiops_ingest_limits_parameter_names_by_realm, realm, {})
    )
  }
  n8n_ssm_params_combined_by_realm = local.n8n_ssm_params_auto_by_realm
  aiops_zulip_bot_token_value_by_realm = local.aiops_zulip_bot_tokens_map != null ? {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.aiops_zulip_bot_tokens_map, realm, null),
        lookup(local.aiops_zulip_bot_tokens_map, "default", null)
      ])[0],
      null
    )
  } : {}
  aiops_zulip_bot_email_value_by_realm = local.aiops_zulip_bot_emails_map != null ? {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.aiops_zulip_bot_emails_map, realm, null),
        lookup(local.aiops_zulip_bot_emails_map, "default", null)
      ])[0],
      null
    )
  } : {}
  aiops_zulip_api_base_url_value_by_realm = local.aiops_zulip_api_base_urls_map != null ? {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.aiops_zulip_api_base_urls_map, realm, null),
        lookup(local.aiops_zulip_api_base_urls_map, "default", null)
      ])[0],
      null
    )
  } : {}
  aiops_zulip_outgoing_token_value_by_realm = local.aiops_zulip_outgoing_tokens_map != null ? {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.aiops_zulip_outgoing_tokens_map, realm, null),
        lookup(local.aiops_zulip_outgoing_tokens_map, "default", null)
      ])[0],
      null
    )
  } : {}
  aiops_zulip_bot_token_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/aiops/zulip/bot_token/${realm}"
  }
  aiops_zulip_bot_email_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/aiops/zulip/bot_email/${realm}"
  }
  aiops_zulip_api_base_url_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/aiops/zulip/api_base_url/${realm}"
  }
  aiops_zulip_outgoing_token_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/aiops/zulip/outgoing_token/${realm}"
  }
  aiops_zulip_ssm_params_by_realm = {
    for realm in local.n8n_realms :
    realm => merge(
      lookup(local.aiops_zulip_bot_token_value_by_realm, realm, null) != null && trimspace(lookup(local.aiops_zulip_bot_token_value_by_realm, realm, "")) != "" ? { N8N_ZULIP_BOT_TOKEN = local.aiops_zulip_bot_token_parameter_names_by_realm[realm] } : {},
      lookup(local.aiops_zulip_bot_email_value_by_realm, realm, null) != null && trimspace(lookup(local.aiops_zulip_bot_email_value_by_realm, realm, "")) != "" ? { N8N_ZULIP_BOT_EMAIL = local.aiops_zulip_bot_email_parameter_names_by_realm[realm] } : {},
      lookup(local.aiops_zulip_api_base_url_value_by_realm, realm, null) != null && trimspace(lookup(local.aiops_zulip_api_base_url_value_by_realm, realm, "")) != "" ? { N8N_ZULIP_API_BASE_URL = local.aiops_zulip_api_base_url_parameter_names_by_realm[realm] } : {},
      lookup(local.aiops_zulip_outgoing_token_value_by_realm, realm, null) != null && trimspace(lookup(local.aiops_zulip_outgoing_token_value_by_realm, realm, "")) != "" ? { N8N_ZULIP_OUTGOING_TOKEN = local.aiops_zulip_outgoing_token_parameter_names_by_realm[realm] } : {}
    )
  }

  zulip_admin_api_key_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/zulip/admin/api_key/${realm}"
  }
  zulip_admin_api_key_value_by_realm = local.zulip_admin_api_keys_map != null ? {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.zulip_admin_api_keys_map, realm, null),
        lookup(local.zulip_admin_api_keys_map, "default", null)
      ])[0],
      null
    )
  } : {}
  zulip_admin_api_key_ssm_params_by_realm = {
    for realm in local.n8n_realms :
    realm => (
      lookup(local.zulip_admin_api_key_value_by_realm, realm, null) != null && trimspace(lookup(local.zulip_admin_api_key_value_by_realm, realm, "")) != ""
      ? { ZULIP_ADMIN_API_KEY = local.zulip_admin_api_key_parameter_names_by_realm[realm] }
      : {}
    )
  }
  gitlab_realm_admin_tokens_yaml_effective = (
    var.gitlab_realm_admin_tokens_yaml != null && trimspace(var.gitlab_realm_admin_tokens_yaml) != ""
    ? var.gitlab_realm_admin_tokens_yaml
    : null
  )
  gitlab_realm_admin_tokens_map = (
    local.gitlab_realm_admin_tokens_yaml_effective != null
    ? try(tomap(yamldecode(local.gitlab_realm_admin_tokens_yaml_effective)), {})
    : {}
  )
  gitlab_realm_admin_token_default = lookup(local.gitlab_realm_admin_tokens_map, "default", null)
  gitlab_realm_admin_token_by_realm = {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.gitlab_realm_admin_tokens_map, realm, null),
        local.gitlab_realm_admin_token_default
      ])[0],
      null
    )
  }
  gitlab_webhook_secrets_yaml_effective = (
    var.gitlab_webhook_secrets_yaml != null && trimspace(var.gitlab_webhook_secrets_yaml) != ""
    ? var.gitlab_webhook_secrets_yaml
    : null
  )
  gitlab_webhook_secrets_map = (
    local.gitlab_webhook_secrets_yaml_effective != null
    ? try(tomap(yamldecode(local.gitlab_webhook_secrets_yaml_effective)), {})
    : {}
  )
  gitlab_webhook_secret_default = lookup(local.gitlab_webhook_secrets_map, "default", null)
  gitlab_webhook_secret_by_realm = {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.gitlab_webhook_secrets_map, realm, null),
        local.gitlab_webhook_secret_default
      ])[0],
      null
    )
  }
  gitlab_webhook_secret_by_realm_effective = {
    for realm, secret in local.gitlab_webhook_secret_by_realm :
    realm => secret
    if secret != null && trimspace(secret) != ""
  }
  n8n_gitlab_token_env_by_realm = {
    for realm in local.n8n_realms :
    realm => merge(
      (
        local.gitlab_host != null && trimspace(local.gitlab_host) != ""
        ? {
          GITLAB_BASE_URL                      = "https://${local.gitlab_host}"
          GITLAB_API_BASE_URL                  = "https://${local.gitlab_host}/api/v4"
          GITLAB_PROJECT_PATH                  = local.gitlab_service_projects_path_by_realm[realm]
          N8N_GITLAB_PROJECT_PATH              = local.gitlab_service_projects_path_by_realm[realm]
          N8N_GITLAB_WORKFLOW_CATALOG_MD_PATH  = "docs/workflow_catalog.md"
          N8N_GITLAB_ESCALATION_MD_PATH        = "docs/escalation_matrix.md"
          N8N_GITLAB_ESCALATION_MATRIX_MD_PATH = "docs/escalation_matrix.md"
          N8N_GITLAB_CMDB_DIR_PATH             = "cmdb/${realm}"
          N8N_GITLAB_RUNBOOK_MD_PATH           = "cmdb/runbook/sulu.md"
        }
        : {}
      )
    )
  }
}
