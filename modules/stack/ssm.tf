locals {
  ssm_writes_enabled                   = var.create_ssm_parameters
  db_username_parameter_name           = coalesce(var.db_username_parameter_name, "/${local.name_prefix}/db/username")
  db_password_parameter_name           = coalesce(var.db_password_parameter_name, "/${local.name_prefix}/db/password")
  db_host_parameter_name               = "/${local.name_prefix}/db/host"
  db_port_parameter_name               = "/${local.name_prefix}/db/port"
  db_name_parameter_name               = "/${local.name_prefix}/db/name"
  n8n_encryption_key_parameter_name    = "/${local.name_prefix}/n8n/encryption_key"
  zulip_datasource_parameter_name      = "/${local.name_prefix}/zulip/datasource"
  n8n_db_username_parameter_name       = "/${local.name_prefix}/n8n/db/username"
  n8n_db_password_parameter_name       = "/${local.name_prefix}/n8n/db/password"
  n8n_db_name_parameter_name           = "/${local.name_prefix}/n8n/db/name"
  n8n_admin_password_parameter_name    = "/${local.name_prefix}/n8n/admin/password"
  aiops_workflows_token_parameter_name = coalesce(var.aiops_workflows_token_parameter_name, "/${local.name_prefix}/aiops/workflows/token")
  observer_token_parameter_name        = "/${local.name_prefix}/n8n/observer/token"
  aiops_s3_prefix_parameter_name       = coalesce(var.aiops_s3_prefix_parameter_name, "/${local.name_prefix}/aiops/s3_prefix")
  aiops_gitlab_first_contact_done_label_parameter_name = coalesce(
    var.aiops_gitlab_first_contact_done_label_parameter_name,
    "/${local.name_prefix}/aiops/gitlab/first_contact_done_label"
  )
  aiops_gitlab_escalation_label_parameter_name = coalesce(
    var.aiops_gitlab_escalation_label_parameter_name,
    "/${local.name_prefix}/aiops/gitlab/escalation_label"
  )
  openai_model_api_key_parameter_name               = coalesce(var.openai_model_api_key_parameter_name, "/${local.name_prefix}/n8n/aiops/openai/api_key")
  n8n_api_key_parameter_name                        = coalesce(var.n8n_api_key_parameter_name, "/${local.name_prefix}/n8n/api_key")
  n8n_api_key_parent_path                           = dirname(local.n8n_api_key_parameter_name)
  zulip_db_username_parameter_name                  = "/${local.name_prefix}/zulip/db/username"
  zulip_db_password_parameter_name                  = "/${local.name_prefix}/zulip/db/password"
  zulip_db_name_parameter_name                      = "/${local.name_prefix}/zulip/db/name"
  zulip_secret_key_parameter_name                   = "/${local.name_prefix}/zulip/secret_key"
  zulip_mq_username_parameter_name                  = "/${local.name_prefix}/zulip/rabbitmq/username"
  zulip_mq_password_parameter_name                  = "/${local.name_prefix}/zulip/rabbitmq/password"
  zulip_mq_host_parameter_name                      = "/${local.name_prefix}/zulip/rabbitmq/host"
  zulip_mq_endpoint_parameter_name                  = "/${local.name_prefix}/zulip/rabbitmq/amqp_endpoint"
  zulip_mq_port_parameter_name                      = "/${local.name_prefix}/zulip/rabbitmq/port"
  zulip_admin_api_key_parameter_name                = "/${local.name_prefix}/zulip/admin/api_key"
  zulip_bot_tokens_parameter_name                   = coalesce(var.zulip_bot_tokens_param, "/${local.name_prefix}/zulip/bot_tokens")
  zulip_redis_host_parameter_name                   = "/${local.name_prefix}/zulip/redis/host"
  zulip_redis_port_parameter_name                   = "/${local.name_prefix}/zulip/redis/port"
  zulip_redis_password_parameter_name               = "/${local.name_prefix}/zulip/redis/password"
  zulip_memcached_endpoint_parameter_name           = "/${local.name_prefix}/zulip/memcached/endpoint"
  sulu_app_secret_parameter_name                    = "/${local.name_prefix}/sulu/app_secret"
  sulu_database_url_parameter_name                  = "/${local.name_prefix}/sulu/database_url"
  sulu_mailer_dsn_parameter_name                    = "/${local.name_prefix}/sulu/mailer_dsn"
  sulu_oidc_client_id_parameter_name                = "/${local.name_prefix}/sulu/oidc/client_id"
  sulu_oidc_client_secret_parameter_name            = "/${local.name_prefix}/sulu/oidc/client_secret"
  service_control_oidc_client_id_parameter_name     = coalesce(var.service_control_oidc_client_id_parameter_name, "/${local.name_prefix}/service-control/oidc/client_id")
  service_control_oidc_client_secret_parameter_name = coalesce(var.service_control_oidc_client_secret_parameter_name, "/${local.name_prefix}/service-control/oidc/client_secret")
  keycloak_db_username_parameter_name               = "/${local.name_prefix}/keycloak/db/username"
  keycloak_db_password_parameter_name               = "/${local.name_prefix}/keycloak/db/password"
  keycloak_db_name_parameter_name                   = "/${local.name_prefix}/keycloak/db/name"
  keycloak_db_host_parameter_name                   = "/${local.name_prefix}/keycloak/db/host"
  keycloak_db_port_parameter_name                   = "/${local.name_prefix}/keycloak/db/port"
  keycloak_db_url_parameter_name                    = "/${local.name_prefix}/keycloak/db/url"
  keycloak_admin_username_parameter_name            = "/${local.name_prefix}/keycloak/admin/username"
  keycloak_admin_password_parameter_name            = "/${local.name_prefix}/keycloak/admin/password"
  odoo_db_username_parameter_name                   = "/${local.name_prefix}/odoo/db/username"
  odoo_db_password_parameter_name                   = "/${local.name_prefix}/odoo/db/password"
  odoo_db_name_parameter_name                       = "/${local.name_prefix}/odoo/db/name"
  odoo_admin_password_parameter_name                = "/${local.name_prefix}/odoo/admin/password"
  gitlab_db_username_parameter_name                 = "/${local.name_prefix}/gitlab/db/username"
  gitlab_db_password_parameter_name                 = "/${local.name_prefix}/gitlab/db/password"
  gitlab_db_name_parameter_name                     = "/${local.name_prefix}/gitlab/db/name"
  gitlab_db_host_parameter_name                     = "/${local.name_prefix}/gitlab/db/host"
  gitlab_db_port_parameter_name                     = "/${local.name_prefix}/gitlab/db/port"
  gitlab_admin_token_parameter_name                 = "/${local.name_prefix}/gitlab/admin/token"
  grafana_db_username_parameter_name                = "/${local.name_prefix}/grafana/db/username"
  grafana_db_password_parameter_name                = "/${local.name_prefix}/grafana/db/password"
  grafana_db_name_parameter_name                    = "/${local.name_prefix}/grafana/db/name"
  grafana_db_host_parameter_name                    = "/${local.name_prefix}/grafana/db/host"
  grafana_db_port_parameter_name                    = "/${local.name_prefix}/grafana/db/port"
  grafana_admin_username_parameter_name             = "/${local.name_prefix}/grafana/admin/username"
  grafana_admin_password_parameter_name             = "/${local.name_prefix}/grafana/admin/password"
  grafana_oidc_client_id_parameter_name             = "/${local.name_prefix}/grafana/oidc/client_id"
  grafana_oidc_client_secret_parameter_name         = "/${local.name_prefix}/grafana/oidc/client_secret"
  exastro_pf_db_username_parameter_name             = "/${local.name_prefix}/exastro-pf/db/username"
  exastro_pf_db_password_parameter_name             = "/${local.name_prefix}/exastro-pf/db/password"
  exastro_pf_db_name_parameter_name                 = "/${local.name_prefix}/exastro-pf/db/name"
  exastro_ita_db_username_parameter_name            = "/${local.name_prefix}/exastro-ita/db/username"
  exastro_ita_db_password_parameter_name            = "/${local.name_prefix}/exastro-ita/db/password"
  exastro_ita_db_name_parameter_name                = "/${local.name_prefix}/exastro-ita/db/name"
  exastro_web_oidc_client_id_parameter_name         = "/${local.name_prefix}/exastro-web/oidc/client_id"
  exastro_web_oidc_client_secret_parameter_name     = "/${local.name_prefix}/exastro-web/oidc/client_secret"
  exastro_api_oidc_client_id_parameter_name         = "/${local.name_prefix}/exastro-api/oidc/client_id"
  exastro_api_oidc_client_secret_parameter_name     = "/${local.name_prefix}/exastro-api/oidc/client_secret"
  oase_db_username_parameter_name                   = "/${local.name_prefix}/oase/db/username"
  oase_db_password_parameter_name                   = "/${local.name_prefix}/oase/db/password"
  oase_db_name_parameter_name                       = "/${local.name_prefix}/oase/db/name"
  pgadmin_default_password_parameter_name           = "/${local.name_prefix}/pgadmin/default_password"
  mysql_db_username_parameter_name                  = "/${local.name_prefix}/mysql/db/username"
  mysql_db_password_parameter_name                  = "/${local.name_prefix}/mysql/db/password"
  mysql_db_name_parameter_name                      = "/${local.name_prefix}/mysql/db/name"
  mysql_db_host_parameter_name                      = "/${local.name_prefix}/mysql/db/host"
  mysql_db_port_parameter_name                      = "/${local.name_prefix}/mysql/db/port"
  odoo_oidc_client_id_parameter_name                = "/${local.name_prefix}/odoo/oidc/client_id"
  odoo_oidc_client_secret_parameter_name            = "/${local.name_prefix}/odoo/oidc/client_secret"
  gitlab_oidc_client_id_parameter_name              = "/${local.name_prefix}/gitlab/oidc/client_id"
  gitlab_oidc_client_secret_parameter_name          = "/${local.name_prefix}/gitlab/oidc/client_secret"
  pgadmin_oidc_client_id_parameter_name             = "/${local.name_prefix}/pgadmin/oidc/client_id"
  pgadmin_oidc_client_secret_parameter_name         = "/${local.name_prefix}/pgadmin/oidc/client_secret"
  n8n_db_password_effective                         = local.db_password_effective
  zulip_db_password_effective                       = local.db_password_effective
  keycloak_db_password_effective                    = local.db_password_effective
  odoo_db_password_effective                        = local.db_password_effective
  gitlab_db_password_effective                      = local.db_password_effective
  gitlab_admin_token_value                          = var.gitlab_admin_token != null && trimspace(var.gitlab_admin_token) != "" ? var.gitlab_admin_token : null
  gitlab_realm_admin_tokens_yaml_parameter_name     = coalesce(var.gitlab_realm_admin_tokens_yaml_parameter_name, "/${local.name_prefix}/gitlab/realm_admin_tokens_yaml")
  gitlab_realm_admin_tokens_yaml_value              = var.gitlab_realm_admin_tokens_yaml != null && trimspace(var.gitlab_realm_admin_tokens_yaml) != "" ? var.gitlab_realm_admin_tokens_yaml : null
  gitlab_realm_admin_tokens_json_parameter_name     = "/${local.name_prefix}/aiops/gitlab/realm_admin_tokens_json"
  gitlab_realm_admin_tokens_json_value              = local.gitlab_realm_admin_tokens_yaml_value != null ? jsonencode(local.gitlab_realm_admin_tokens_map) : null
  gitlab_projects_path_json_parameter_name          = "/${local.name_prefix}/aiops/gitlab/projects_path_json"
  gitlab_projects_path_json_value                   = jsonencode(local.gitlab_service_projects_path_by_realm)
  zulip_admin_api_keys_raw_yaml                     = var.zulip_admin_api_keys_yaml != null && trimspace(var.zulip_admin_api_keys_yaml) != "" ? var.zulip_admin_api_keys_yaml : null
  zulip_admin_api_keys_map                          = local.zulip_admin_api_keys_raw_yaml != null ? try(tomap(yamldecode(local.zulip_admin_api_keys_raw_yaml)), null) : null
  oase_db_username_value                            = coalesce(var.oase_db_username, local.master_username)
  oase_db_password_value                            = coalesce(var.oase_db_password, local.db_password_effective)
  oase_db_name_value                                = var.oase_db_name
  exastro_pf_db_username_value                      = coalesce(var.exastro_pf_db_username, local.master_username)
  exastro_pf_db_password_value                      = coalesce(var.exastro_pf_db_password, local.db_password_effective)
  exastro_pf_db_name_value                          = var.exastro_pf_db_name
  exastro_ita_db_username_value                     = coalesce(var.exastro_ita_db_username, local.master_username)
  exastro_ita_db_password_value                     = coalesce(var.exastro_ita_db_password, local.db_password_effective)
  exastro_ita_db_name_value                         = var.exastro_ita_db_name
  mysql_db_username_value                           = var.mysql_db_username
  mysql_db_password_value                           = var.mysql_db_password != null ? var.mysql_db_password : (local.ssm_writes_enabled ? try(random_password.mysql_db[0].result, null) : null)
  mysql_db_name_value                               = var.mysql_db_name
  grafana_admin_username_value                      = var.grafana_admin_username
  grafana_admin_password_value                      = var.grafana_admin_password != null ? var.grafana_admin_password : (var.create_grafana && local.ssm_writes_enabled ? try(random_password.grafana_admin[0].result, null) : null)
  grafana_db_username_value                         = local.gitlab_db_username_value
  grafana_db_password_value                         = local.gitlab_db_password_value
  grafana_db_name_value                             = var.grafana_db_name
  n8n_smtp_username_parameter_name                  = "/${local.name_prefix}/n8n/smtp/username"
  n8n_smtp_password_parameter_name                  = "/${local.name_prefix}/n8n/smtp/password"
  zulip_smtp_username_parameter_name                = "/${local.name_prefix}/zulip/smtp/username"
  zulip_smtp_password_parameter_name                = "/${local.name_prefix}/zulip/smtp/password"
  keycloak_smtp_username_parameter_name             = "/${local.name_prefix}/keycloak/smtp/username"
  keycloak_smtp_password_parameter_name             = "/${local.name_prefix}/keycloak/smtp/password"
  odoo_smtp_username_parameter_name                 = "/${local.name_prefix}/odoo/smtp/username"
  odoo_smtp_password_parameter_name                 = "/${local.name_prefix}/odoo/smtp/password"
  gitlab_smtp_username_parameter_name               = "/${local.name_prefix}/gitlab/smtp/username"
  gitlab_smtp_password_parameter_name               = "/${local.name_prefix}/gitlab/smtp/password"
  exastro_web_smtp_username_parameter_name          = "/${local.name_prefix}/exastro-web/smtp/username"
  exastro_web_smtp_password_parameter_name          = "/${local.name_prefix}/exastro-web/smtp/password"
  exastro_api_smtp_username_parameter_name          = "/${local.name_prefix}/exastro-api/smtp/username"
  exastro_api_smtp_password_parameter_name          = "/${local.name_prefix}/exastro-api/smtp/password"
  pgadmin_smtp_username_parameter_name              = "/${local.name_prefix}/pgadmin/smtp/username"
  pgadmin_smtp_password_parameter_name              = "/${local.name_prefix}/pgadmin/smtp/password"
}

locals {
  gitlab_webhook_secret_realms = keys(local.gitlab_webhook_secret_by_realm_effective)
  gitlab_webhook_secret_parameter_names_by_realm = {
    for realm in nonsensitive(local.gitlab_webhook_secret_realms) :
    realm => "/${local.name_prefix}/n8n/gitlab/webhook_secret/${realm}"
  }
}

locals {
  gitlab_realm_token_parameter_names_by_realm = {
    for realm in local.n8n_realms :
    realm => "/${local.name_prefix}/n8n/gitlab/token/${realm}"
  }
}

data "aws_ssm_parameters_by_path" "existing_keycloak_admin" {
  count           = var.create_keycloak ? 1 : 0
  path            = "/${local.name_prefix}/keycloak/admin"
  with_decryption = true
}

locals {
  ses_smtp_username_value    = var.enable_ses_smtp_auto ? try(aws_iam_access_key.ses_smtp[0].id, null) : null
  ses_smtp_password_value    = var.enable_ses_smtp_auto ? try(aws_iam_access_key.ses_smtp[0].ses_smtp_password_v4, null) : null
  n8n_smtp_username_value    = coalesce(var.n8n_smtp_username, local.ses_smtp_username_value)
  n8n_smtp_password_value    = coalesce(var.n8n_smtp_password, local.ses_smtp_password_value)
  n8n_admin_email_value      = var.n8n_admin_email != null ? var.n8n_admin_email : "admin@${local.hosted_zone_name_input}"
  zulip_smtp_username_value  = coalesce(var.zulip_smtp_username, local.ses_smtp_username_value)
  zulip_smtp_password_value  = coalesce(var.zulip_smtp_password, local.ses_smtp_password_value)
  zulip_secret_key_value     = var.zulip_secret_key != null ? var.zulip_secret_key : (local.ssm_writes_enabled ? try(random_password.zulip_secret_key[0].result, null) : null)
  zulip_mq_username_value    = var.zulip_mq_username
  zulip_mq_password_generate = local.ssm_writes_enabled && var.create_ecs && var.create_zulip && var.zulip_mq_password == null
  zulip_mq_password_value    = var.zulip_mq_password != null ? var.zulip_mq_password : (local.zulip_mq_password_generate ? try(random_password.zulip_mq[0].result, null) : null)
  zulip_bot_tokens_yaml_value = (
    var.zulip_mess_bot_tokens_yaml != null &&
    trimspace(var.zulip_mess_bot_tokens_yaml) != ""
  ) ? var.zulip_mess_bot_tokens_yaml : null
  zulip_bot_tokens_map                        = local.zulip_bot_tokens_yaml_value != null ? yamldecode(local.zulip_bot_tokens_yaml_value) : null
  zulip_bot_tokens_json_value                 = local.zulip_bot_tokens_map != null ? jsonencode(local.zulip_bot_tokens_map) : null
  zulip_bot_tokens_value                      = local.zulip_bot_tokens_json_value
  aiops_s3_prefix_value                       = var.aiops_s3_prefix != null && trimspace(var.aiops_s3_prefix) != "" ? var.aiops_s3_prefix : null
  aiops_gitlab_first_contact_done_label_value = var.aiops_gitlab_first_contact_done_label != null && trimspace(var.aiops_gitlab_first_contact_done_label) != "" ? var.aiops_gitlab_first_contact_done_label : null
  aiops_gitlab_escalation_label_value         = var.aiops_gitlab_escalation_label != null && trimspace(var.aiops_gitlab_escalation_label) != "" ? var.aiops_gitlab_escalation_label : null
  aiops_zulip_bot_emails_yaml_value = (
    var.zulip_mess_bot_emails_yaml != null &&
    trimspace(var.zulip_mess_bot_emails_yaml) != ""
  ) ? var.zulip_mess_bot_emails_yaml : null
  aiops_zulip_api_base_urls_yaml_value = (
    var.zulip_api_mess_base_urls_yaml != null &&
    trimspace(var.zulip_api_mess_base_urls_yaml) != ""
  ) ? var.zulip_api_mess_base_urls_yaml : null
  aiops_zulip_outgoing_tokens_yaml_value = (
    var.zulip_outgoing_tokens_yaml != null &&
    trimspace(var.zulip_outgoing_tokens_yaml) != ""
  ) ? var.zulip_outgoing_tokens_yaml : null
  aiops_zulip_bot_tokens_map      = local.zulip_bot_tokens_map != null ? local.zulip_bot_tokens_map : null
  aiops_zulip_bot_emails_map      = local.aiops_zulip_bot_emails_yaml_value != null ? try(yamldecode(local.aiops_zulip_bot_emails_yaml_value), null) : null
  aiops_zulip_api_base_urls_map   = local.aiops_zulip_api_base_urls_yaml_value != null ? try(yamldecode(local.aiops_zulip_api_base_urls_yaml_value), null) : null
  aiops_zulip_outgoing_tokens_map = local.aiops_zulip_outgoing_tokens_yaml_value != null ? try(yamldecode(local.aiops_zulip_outgoing_tokens_yaml_value), null) : null
  sulu_db_username_value          = coalesce(var.sulu_db_username, local.master_username)
  sulu_app_secret_value           = var.sulu_app_secret != null ? var.sulu_app_secret : (local.ssm_writes_enabled && var.create_ecs && var.create_sulu ? try(random_password.sulu_app_secret[0].result, null) : null)
  sulu_database_url_value         = var.create_sulu && var.create_rds ? "postgresql://${local.sulu_db_username_value}:${urlencode(local.db_password_effective)}@${aws_db_instance.this[0].address}:${aws_db_instance.this[0].port}/${var.sulu_db_name}?serverVersion=${var.rds_engine_version}&sslmode=require" : null
  sulu_mailer_dsn_value           = coalesce(var.sulu_mailer_dsn, local.ses_smtp_username_value != null && local.ses_smtp_password_value != null ? "smtp://${local.ses_smtp_username_value}:${urlencode(local.ses_smtp_password_value)}@email-smtp.${var.region}.amazonaws.com:587?encryption=tls&auth_mode=login" : null)
  exastro_web_oidc_client_id_value = try(coalesce(
    var.exastro_web_oidc_client_id,
    lookup(local.oidc_idps_client_id_from_yaml, "exastro_web", null),
    try(local.keycloak_managed_clients["exastro-web"].client_id, null),
    var.exastro_web_oidc_client_secret != null ? "exastro-web" : null
  ), null)
  exastro_web_oidc_client_secret_value = try(coalesce(
    var.exastro_web_oidc_client_secret,
    lookup(local.oidc_idps_client_secret_from_yaml, "exastro_web", null),
    try(local.keycloak_managed_clients["exastro-web"].client_secret, null)
  ), null)
  exastro_api_oidc_client_id_value = try(coalesce(
    var.exastro_api_oidc_client_id,
    lookup(local.oidc_idps_client_id_from_yaml, "exastro_api", null),
    try(local.keycloak_managed_clients["exastro-api"].client_id, null),
    var.exastro_api_oidc_client_secret != null ? "exastro-api" : null
  ), null)
  exastro_api_oidc_client_secret_value = try(coalesce(
    var.exastro_api_oidc_client_secret,
    lookup(local.oidc_idps_client_secret_from_yaml, "exastro_api", null),
    try(local.keycloak_managed_clients["exastro-api"].client_secret, null)
  ), null)
  odoo_oidc_client_id_value = var.enable_odoo_keycloak ? try(coalesce(
    var.odoo_oidc_client_id,
    lookup(local.oidc_idps_client_id_from_yaml, "odoo", null),
    try(local.keycloak_managed_clients["odoo"].client_id, null),
    var.odoo_oidc_client_secret != null ? "odoo" : null
  ), null) : null
  odoo_oidc_client_secret_value = var.enable_odoo_keycloak ? try(coalesce(
    var.odoo_oidc_client_secret,
    lookup(local.oidc_idps_client_secret_from_yaml, "odoo", null),
    try(local.keycloak_managed_clients["odoo"].client_secret, null)
  ), null) : null
  oidc_idps_yaml_sources = {
    exastro_web = var.exastro_oidc_idps_yaml
    exastro_api = var.exastro_oidc_idps_yaml
    sulu        = var.sulu_oidc_idps_yaml
    keycloak    = var.keycloak_oidc_idps_yaml
    odoo        = var.odoo_oidc_idps_yaml
    pgadmin     = var.pgadmin_oidc_idps_yaml
    gitlab      = var.gitlab_oidc_idps_yaml
    grafana     = var.grafana_oidc_idps_yaml
    zulip       = var.zulip_oidc_idps_yaml
  }
  oidc_idps_yaml_docs = { for svc, yaml in local.oidc_idps_yaml_sources : svc => yaml != null ? try(tomap(yamldecode(yaml)), {}) : {} }
  oidc_idps_yaml_entries = {
    for svc, doc in local.oidc_idps_yaml_docs :
    svc => length(doc) > 0 ? coalesce(lookup(doc, "keycloak", null), values(doc)[0]) : null
  }
  grafana_oidc_idps_doc = var.grafana_oidc_idps_yaml != null ? try(tomap(yamldecode(var.grafana_oidc_idps_yaml)), {}) : {}
  grafana_oidc_key_by_realm = {
    for realm in local.grafana_realms :
    realm => "keycloak_${replace(realm, "/[^A-Za-z0-9_-]+/", "_")}"
  }
  grafana_oidc_entry_by_realm = {
    for realm in local.grafana_realms :
    realm => try(
      coalesce(
        lookup(local.grafana_oidc_idps_doc, local.grafana_oidc_key_by_realm[realm], null),
        lookup(local.grafana_oidc_idps_doc, "keycloak", null)
      ),
      null
    )
  }
  grafana_oidc_client_id_by_realm = {
    for realm, entry in local.grafana_oidc_entry_by_realm :
    realm => try(
      coalesce(
        var.grafana_oidc_client_id,
        entry != null ? try(entry.client_id, null) : null,
        var.grafana_oidc_client_secret != null ? "grafana" : null
      ),
      null
    )
  }
  grafana_oidc_client_secret_by_realm = {
    for realm, entry in local.grafana_oidc_entry_by_realm :
    realm => try(
      coalesce(
        var.grafana_oidc_client_secret,
        entry != null ? try(entry.secret, null) : null
      ),
      null
    )
  }
  grafana_oidc_issuer_url_by_realm = {
    for realm, entry in local.grafana_oidc_entry_by_realm :
    realm => entry != null ? try(entry.oidc_url, null) : null
  }
  grafana_oidc_userinfo_url_by_realm = {
    for realm, entry in local.grafana_oidc_entry_by_realm :
    realm => entry != null ? try(entry.api_url, null) : null
  }
  grafana_oidc_scopes_by_realm = {
    for realm, entry in local.grafana_oidc_entry_by_realm :
    realm => entry != null ? try(entry.extra_params.scope, null) : null
  }
  grafana_oidc_display_name_by_realm = {
    for realm, entry in local.grafana_oidc_entry_by_realm :
    realm => entry != null ? try(entry.display_name, null) : null
  }
  grafana_oidc_client_id_parameter_names_by_realm = {
    for realm in local.grafana_realms :
    realm => "/${local.name_prefix}/grafana/oidc/${realm}/client_id"
  }
  grafana_oidc_client_secret_parameter_names_by_realm = {
    for realm in local.grafana_realms :
    realm => "/${local.name_prefix}/grafana/oidc/${realm}/client_secret"
  }
  grafana_oidc_client_id_by_realm_effective = {
    for realm, value in local.grafana_oidc_client_id_by_realm :
    realm => value if value != null && value != ""
  }
  grafana_oidc_client_secret_by_realm_effective = {
    for realm, value in local.grafana_oidc_client_secret_by_realm :
    realm => value if value != null && value != ""
  }
  oidc_idps_client_id_from_yaml     = { for svc, entry in local.oidc_idps_yaml_entries : svc => entry != null ? try(entry.client_id, null) : null }
  oidc_idps_client_secret_from_yaml = { for svc, entry in local.oidc_idps_yaml_entries : svc => entry != null ? try(entry.secret, null) : null }
  oidc_idps_issuer_url_from_yaml    = { for svc, entry in local.oidc_idps_yaml_entries : svc => entry != null ? try(entry.oidc_url, null) : null }
  oidc_idps_userinfo_url_from_yaml  = { for svc, entry in local.oidc_idps_yaml_entries : svc => entry != null ? try(entry.api_url, null) : null }
  oidc_idps_scope_from_yaml         = { for svc, entry in local.oidc_idps_yaml_entries : svc => entry != null ? try(entry.extra_params.scope, null) : null }
  oidc_idps_display_name_from_yaml  = { for svc, entry in local.oidc_idps_yaml_entries : svc => entry != null ? try(entry.display_name, null) : null }
  gitlab_oidc_client_id_value = var.enable_gitlab_keycloak ? try(coalesce(
    var.gitlab_oidc_client_id,
    lookup(local.oidc_idps_client_id_from_yaml, "gitlab", null),
    try(local.keycloak_managed_clients["gitlab"].client_id, null),
    var.gitlab_oidc_client_secret != null ? "gitlab" : null
  ), null) : null
  gitlab_oidc_client_secret_value = var.enable_gitlab_keycloak ? try(coalesce(
    var.gitlab_oidc_client_secret,
    lookup(local.oidc_idps_client_secret_from_yaml, "gitlab", null),
    try(local.keycloak_managed_clients["gitlab"].client_secret, null)
  ), null) : null
  grafana_oidc_client_id_value = var.enable_grafana_keycloak ? try(coalesce(
    var.grafana_oidc_client_id,
    lookup(local.oidc_idps_client_id_from_yaml, "grafana", null),
    try(local.keycloak_managed_clients["grafana"].client_id, null),
    var.grafana_oidc_client_secret != null ? "grafana" : null
  ), null) : null
  grafana_oidc_client_secret_value = var.enable_grafana_keycloak ? try(coalesce(
    var.grafana_oidc_client_secret,
    lookup(local.oidc_idps_client_secret_from_yaml, "grafana", null),
    try(local.keycloak_managed_clients["grafana"].client_secret, null)
  ), null) : null
  pgadmin_oidc_client_id_value = var.enable_pgadmin_keycloak ? try(coalesce(
    var.pgadmin_oidc_client_id,
    lookup(local.oidc_idps_client_id_from_yaml, "pgadmin", null),
    try(local.keycloak_managed_clients["pgadmin"].client_id, null),
    var.pgadmin_oidc_client_secret != null ? "pgadmin" : null
  ), null) : null
  pgadmin_oidc_client_secret_value = var.enable_pgadmin_keycloak ? try(coalesce(
    var.pgadmin_oidc_client_secret,
    lookup(local.oidc_idps_client_secret_from_yaml, "pgadmin", null),
    try(local.keycloak_managed_clients["pgadmin"].client_secret, null)
  ), null) : null
  service_control_oidc_client_id_value = try(coalesce(
    var.service_control_oidc_client_id,
    var.service_control_oidc_client_secret != null ? "service-control" : null
  ), null)
  service_control_oidc_client_secret_value = try(coalesce(
    var.service_control_oidc_client_secret,
    null
  ), null)
  keycloak_admin_params_from_ssm = zipmap(
    try(data.aws_ssm_parameters_by_path.existing_keycloak_admin[0].names, []),
    try(data.aws_ssm_parameters_by_path.existing_keycloak_admin[0].values, []),
  )
  exastro_web_oidc_client_id_write_enabled         = local.ssm_writes_enabled && var.create_ecs && local.exastro_service_enabled && var.enable_exastro_keycloak && (var.exastro_web_oidc_client_id != null || var.exastro_web_oidc_client_secret != null || var.exastro_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  exastro_web_oidc_client_secret_write_enabled     = local.ssm_writes_enabled && var.create_ecs && local.exastro_service_enabled && var.enable_exastro_keycloak && (var.exastro_web_oidc_client_secret != null || var.exastro_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  exastro_api_oidc_client_id_write_enabled         = local.ssm_writes_enabled && var.create_ecs && local.exastro_service_enabled && var.enable_exastro_keycloak && (var.exastro_api_oidc_client_id != null || var.exastro_api_oidc_client_secret != null || var.exastro_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  exastro_api_oidc_client_secret_write_enabled     = local.ssm_writes_enabled && var.create_ecs && local.exastro_service_enabled && var.enable_exastro_keycloak && (var.exastro_api_oidc_client_secret != null || var.exastro_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  odoo_oidc_client_id_write_enabled                = local.ssm_writes_enabled && var.create_ecs && var.create_odoo && var.enable_odoo_keycloak && (var.odoo_oidc_client_id != null || var.odoo_oidc_client_secret != null || var.odoo_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  odoo_oidc_client_secret_write_enabled            = local.ssm_writes_enabled && var.create_ecs && var.create_odoo && var.enable_odoo_keycloak && (var.odoo_oidc_client_secret != null || var.odoo_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  gitlab_oidc_client_id_write_enabled              = local.ssm_writes_enabled && var.create_ecs && var.create_gitlab && var.enable_gitlab_keycloak && (var.gitlab_oidc_client_id != null || var.gitlab_oidc_client_secret != null || var.gitlab_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  gitlab_oidc_client_secret_write_enabled          = local.ssm_writes_enabled && var.create_ecs && var.create_gitlab && var.enable_gitlab_keycloak && (var.gitlab_oidc_client_secret != null || var.gitlab_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  grafana_oidc_client_id_write_enabled             = local.ssm_writes_enabled && var.create_ecs && var.create_grafana && var.enable_grafana_keycloak && (var.grafana_oidc_client_id != null || var.grafana_oidc_client_secret != null || var.grafana_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  grafana_oidc_client_secret_write_enabled         = local.ssm_writes_enabled && var.create_ecs && var.create_grafana && var.enable_grafana_keycloak && (var.grafana_oidc_client_secret != null || var.grafana_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  pgadmin_oidc_client_id_write_enabled             = local.ssm_writes_enabled && var.create_ecs && var.create_pgadmin && var.enable_pgadmin_keycloak && (var.pgadmin_oidc_client_id != null || var.pgadmin_oidc_client_secret != null || var.pgadmin_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  pgadmin_oidc_client_secret_write_enabled         = local.ssm_writes_enabled && var.create_ecs && var.create_pgadmin && var.enable_pgadmin_keycloak && (var.pgadmin_oidc_client_secret != null || var.pgadmin_oidc_idps_yaml != null || local.manage_keycloak_clients_effective)
  service_control_oidc_client_id_write_enabled     = local.ssm_writes_enabled && var.create_ecs && var.enable_service_control && (var.service_control_oidc_client_id != null || var.service_control_oidc_client_secret != null)
  service_control_oidc_client_secret_write_enabled = local.ssm_writes_enabled && var.create_ecs && var.enable_service_control && (var.service_control_oidc_client_secret != null)
  gitlab_admin_token_write_enabled                 = local.ssm_writes_enabled && var.create_ecs && var.create_gitlab && local.gitlab_admin_token_value != null
  keycloak_smtp_username_value                     = coalesce(var.keycloak_smtp_username, local.ses_smtp_username_value)
  keycloak_smtp_password_value                     = coalesce(var.keycloak_smtp_password, local.ses_smtp_password_value)
  keycloak_db_username_value                       = coalesce(var.keycloak_db_username, local.master_username)
  keycloak_db_password_value                       = coalesce(var.keycloak_db_password, local.db_password_effective)
  keycloak_admin_username_value                    = coalesce(try(local.keycloak_admin_params_from_ssm[local.keycloak_admin_username_parameter_name], null), var.keycloak_admin_username)
  keycloak_admin_password_value                    = coalesce(var.keycloak_admin_password, try(local.keycloak_admin_params_from_ssm[local.keycloak_admin_password_parameter_name], null), var.create_keycloak && local.ssm_writes_enabled ? try(random_password.keycloak_admin[0].result, null) : null)
  odoo_smtp_username_value                         = coalesce(var.odoo_smtp_username, local.ses_smtp_username_value)
  odoo_smtp_password_value                         = coalesce(var.odoo_smtp_password, local.ses_smtp_password_value)
  odoo_db_username_value                           = coalesce(var.odoo_db_username, local.master_username)
  odoo_db_password_value                           = coalesce(var.odoo_db_password, local.db_password_effective)
  odoo_admin_password_value                        = var.odoo_admin_password != null ? var.odoo_admin_password : (var.create_odoo && local.ssm_writes_enabled ? try(random_password.odoo_admin[0].result, null) : null)
  gitlab_db_username_value                         = coalesce(var.gitlab_db_username, local.master_username)
  gitlab_db_password_value                         = coalesce(var.gitlab_db_password, local.db_password_effective)
  gitlab_db_name_value                             = var.gitlab_db_name
  gitlab_smtp_username_value                       = coalesce(var.gitlab_smtp_username, local.ses_smtp_username_value)
  gitlab_smtp_password_value                       = coalesce(var.gitlab_smtp_password, local.ses_smtp_password_value)
  exastro_web_smtp_username_value                  = local.ses_smtp_username_value
  exastro_web_smtp_password_value                  = local.ses_smtp_password_value
  exastro_api_smtp_username_value                  = local.ses_smtp_username_value
  exastro_api_smtp_password_value                  = local.ses_smtp_password_value
  pgadmin_smtp_username_value                      = coalesce(var.pgadmin_smtp_username, local.ses_smtp_username_value)
  pgadmin_smtp_password_value                      = coalesce(var.pgadmin_smtp_password, local.ses_smtp_password_value)
}

locals {
  smtp_creds_available            = var.enable_ses_smtp_auto
  n8n_smtp_params_enabled         = local.smtp_creds_available || var.n8n_smtp_username != null || var.n8n_smtp_password != null
  zulip_smtp_params_enabled       = local.smtp_creds_available || var.zulip_smtp_username != null || var.zulip_smtp_password != null
  keycloak_smtp_params_enabled    = local.smtp_creds_available || var.keycloak_smtp_username != null || var.keycloak_smtp_password != null
  odoo_smtp_params_enabled        = local.smtp_creds_available || var.odoo_smtp_username != null || var.odoo_smtp_password != null
  gitlab_smtp_params_enabled      = local.smtp_creds_available || var.gitlab_smtp_username != null || var.gitlab_smtp_password != null
  exastro_web_smtp_params_enabled = local.smtp_creds_available
  exastro_api_smtp_params_enabled = local.smtp_creds_available
  pgadmin_smtp_params_enabled     = local.smtp_creds_available || var.pgadmin_smtp_username != null || var.pgadmin_smtp_password != null
  randoms_enabled                 = local.ssm_writes_enabled
}

resource "aws_ssm_parameter" "db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters && var.create_rds ? 1 : 0) : 0

  name  = local.db_username_parameter_name
  type  = "SecureString"
  value = local.master_username

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-username" })
}

resource "aws_ssm_parameter" "db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters && var.create_rds && local.db_password_effective != null ? 1 : 0) : 0

  name  = local.db_password_parameter_name
  type  = "SecureString"
  value = local.db_password_effective

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-password" })
}

resource "aws_ssm_parameter" "n8n_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.n8n_db_username_parameter_name
  type  = "String"
  value = local.master_username

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-db-username" })
}

resource "aws_ssm_parameter" "n8n_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.n8n_db_password_parameter_name
  type  = "SecureString"
  value = local.db_password_effective

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-db-password" })
}

resource "aws_ssm_parameter" "n8n_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.n8n_db_name_parameter_name
  type  = "String"
  value = var.n8n_db_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-db-name" })
}

resource "aws_ssm_parameter" "n8n_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && local.n8n_smtp_params_enabled ? 1 : 0) : 0

  name      = local.n8n_smtp_username_parameter_name
  type      = "SecureString"
  value     = local.n8n_smtp_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-smtp-username" })
}

resource "aws_ssm_parameter" "n8n_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && local.n8n_smtp_params_enabled ? 1 : 0) : 0

  name      = local.n8n_smtp_password_parameter_name
  type      = "SecureString"
  value     = local.n8n_smtp_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-smtp-password" })
}

resource "aws_ssm_parameter" "keycloak_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak && local.keycloak_smtp_params_enabled ? 1 : 0) : 0

  name      = local.keycloak_smtp_username_parameter_name
  type      = "SecureString"
  value     = local.keycloak_smtp_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-smtp-username" })
}

resource "aws_ssm_parameter" "keycloak_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak && local.keycloak_smtp_params_enabled ? 1 : 0) : 0

  name      = local.keycloak_smtp_password_parameter_name
  type      = "SecureString"
  value     = local.keycloak_smtp_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-smtp-password" })
}

resource "aws_ssm_parameter" "odoo_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_odoo && local.odoo_smtp_params_enabled ? 1 : 0) : 0

  name      = local.odoo_smtp_username_parameter_name
  type      = "SecureString"
  value     = local.odoo_smtp_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-smtp-username" })
}

resource "aws_ssm_parameter" "odoo_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_odoo && local.odoo_smtp_params_enabled ? 1 : 0) : 0

  name      = local.odoo_smtp_password_parameter_name
  type      = "SecureString"
  value     = local.odoo_smtp_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-smtp-password" })
}

resource "aws_ssm_parameter" "zulip_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip && local.zulip_smtp_params_enabled ? 1 : 0) : 0

  name      = local.zulip_smtp_username_parameter_name
  type      = "SecureString"
  value     = local.zulip_smtp_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-smtp-username" })
}

resource "aws_ssm_parameter" "zulip_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip && local.zulip_smtp_params_enabled ? 1 : 0) : 0

  name      = local.zulip_smtp_password_parameter_name
  type      = "SecureString"
  value     = local.zulip_smtp_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-smtp-password" })
}

resource "aws_ssm_parameter" "zulip_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.zulip_db_username_parameter_name
  type  = "String"
  value = local.master_username

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-db-username" })
}

resource "aws_ssm_parameter" "zulip_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.zulip_db_password_parameter_name
  type  = "SecureString"
  value = local.db_password_effective

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-db-password" })
}

resource "aws_ssm_parameter" "zulip_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.zulip_db_name_parameter_name
  type  = "String"
  value = var.zulip_db_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-db-name" })
}

resource "aws_ssm_parameter" "keycloak_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.keycloak_db_username_parameter_name
  type  = "String"
  value = local.keycloak_db_username_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-db-username" })
}

resource "aws_ssm_parameter" "keycloak_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.keycloak_db_password_parameter_name
  type  = "SecureString"
  value = local.keycloak_db_password_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-db-password" })
}

resource "aws_ssm_parameter" "keycloak_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.keycloak_db_name_parameter_name
  type  = "String"
  value = var.keycloak_db_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-db-name" })
}

resource "aws_ssm_parameter" "keycloak_db_host" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak && var.create_rds ? 1 : 0) : 0

  name  = local.keycloak_db_host_parameter_name
  type  = "String"
  value = aws_db_instance.this[0].address

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-db-host" })
}

resource "aws_ssm_parameter" "keycloak_db_port" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak && var.create_rds ? 1 : 0) : 0

  name  = local.keycloak_db_port_parameter_name
  type  = "String"
  value = tostring(aws_db_instance.this[0].port)

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-db-port" })
}

resource "aws_ssm_parameter" "keycloak_db_url" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak && var.create_rds ? 1 : 0) : 0

  name  = local.keycloak_db_url_parameter_name
  type  = "SecureString"
  value = "jdbc:postgresql://${aws_db_instance.this[0].address}:${aws_db_instance.this[0].port}/${var.keycloak_db_name}"

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-db-url" })
}

resource "aws_ssm_parameter" "keycloak_admin_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak ? 1 : 0) : 0

  name      = local.keycloak_admin_username_parameter_name
  type      = "SecureString"
  value     = local.keycloak_admin_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-admin-username" })
}

resource "aws_ssm_parameter" "keycloak_admin_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak ? 1 : 0) : 0

  name      = local.keycloak_admin_password_parameter_name
  type      = "SecureString"
  value     = local.keycloak_admin_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-admin-password" })
}

resource "aws_ssm_parameter" "grafana_admin_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_grafana ? 1 : 0) : 0

  name      = local.grafana_admin_username_parameter_name
  type      = "SecureString"
  value     = local.grafana_admin_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-admin-username" })
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_grafana ? 1 : 0) : 0

  name      = local.grafana_admin_password_parameter_name
  type      = "SecureString"
  value     = local.grafana_admin_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-admin-password" })
}

resource "aws_ssm_parameter" "odoo_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.odoo_db_username_parameter_name
  type  = "String"
  value = local.odoo_db_username_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-db-username" })
}

resource "aws_ssm_parameter" "odoo_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.odoo_db_password_parameter_name
  type  = "SecureString"
  value = local.odoo_db_password_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-db-password" })
}

resource "aws_ssm_parameter" "odoo_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.odoo_db_name_parameter_name
  type  = "String"
  value = var.odoo_db_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-db-name" })
}

resource "aws_ssm_parameter" "odoo_oidc_client_id" {
  count = local.odoo_oidc_client_id_write_enabled ? 1 : 0

  name      = local.odoo_oidc_client_id_parameter_name
  type      = "SecureString"
  value     = local.odoo_oidc_client_id_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-oidc-client-id" })
}

resource "aws_ssm_parameter" "odoo_oidc_client_secret" {
  count = local.odoo_oidc_client_secret_write_enabled ? 1 : 0

  name      = local.odoo_oidc_client_secret_parameter_name
  type      = "SecureString"
  value     = local.odoo_oidc_client_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-oidc-client-secret" })
}

resource "aws_ssm_parameter" "mysql_db_username" {
  count = local.ssm_writes_enabled ? (var.create_mysql_rds ? 1 : 0) : 0

  name      = local.mysql_db_username_parameter_name
  type      = "String"
  value     = local.mysql_db_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-mysql-db-username" })
}

resource "aws_ssm_parameter" "mysql_db_password" {
  count = local.ssm_writes_enabled ? (var.create_mysql_rds ? 1 : 0) : 0

  name      = local.mysql_db_password_parameter_name
  type      = "SecureString"
  value     = local.mysql_db_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-mysql-db-password" })
}

resource "aws_ssm_parameter" "mysql_db_name" {
  count = local.ssm_writes_enabled ? (var.create_mysql_rds ? 1 : 0) : 0

  name      = local.mysql_db_name_parameter_name
  type      = "String"
  value     = local.mysql_db_name_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-mysql-db-name" })
}

resource "aws_ssm_parameter" "mysql_db_host" {
  count = local.ssm_writes_enabled ? (var.create_mysql_rds ? 1 : 0) : 0

  name      = local.mysql_db_host_parameter_name
  type      = "String"
  value     = var.create_mysql_rds ? try(aws_db_instance.mysql[0].address, "") : ""
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-mysql-db-host" })
}

resource "aws_ssm_parameter" "mysql_db_port" {
  count = local.ssm_writes_enabled ? (var.create_mysql_rds ? 1 : 0) : 0

  name      = local.mysql_db_port_parameter_name
  type      = "String"
  value     = var.create_mysql_rds ? tostring(try(aws_db_instance.mysql[0].port, 3306)) : "3306"
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-mysql-db-port" })
}

resource "aws_ssm_parameter" "gitlab_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.gitlab_db_username_parameter_name
  type  = "String"
  value = local.gitlab_db_username_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-db-username" })
}

resource "aws_ssm_parameter" "gitlab_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.gitlab_db_password_parameter_name
  type  = "SecureString"
  value = local.gitlab_db_password_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-db-password" })
}

resource "aws_ssm_parameter" "gitlab_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.gitlab_db_name_parameter_name
  type  = "String"
  value = local.gitlab_db_name_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-db-name" })
}

resource "aws_ssm_parameter" "gitlab_db_host" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.gitlab_db_host_parameter_name
  type  = "String"
  value = aws_db_instance.this[0].address

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-db-host" })
}

resource "aws_ssm_parameter" "gitlab_db_port" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.gitlab_db_port_parameter_name
  type  = "String"
  value = tostring(aws_db_instance.this[0].port)

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-db-port" })
}

resource "aws_ssm_parameter" "grafana_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.grafana_db_username_parameter_name
  type  = "String"
  value = local.grafana_db_username_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-db-username" })
}

resource "aws_ssm_parameter" "grafana_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.grafana_db_password_parameter_name
  type  = "SecureString"
  value = local.grafana_db_password_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-db-password" })
}

resource "aws_ssm_parameter" "grafana_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.grafana_db_name_parameter_name
  type  = "String"
  value = local.grafana_db_name_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-db-name" })
}

resource "aws_ssm_parameter" "grafana_db_host" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.grafana_db_host_parameter_name
  type  = "String"
  value = aws_db_instance.this[0].address

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-db-host" })
}

resource "aws_ssm_parameter" "grafana_db_port" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.grafana_db_port_parameter_name
  type  = "String"
  value = tostring(aws_db_instance.this[0].port)

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-db-port" })
}

resource "aws_ssm_parameter" "gitlab_oidc_client_id" {
  count = local.gitlab_oidc_client_id_write_enabled ? 1 : 0

  name      = local.gitlab_oidc_client_id_parameter_name
  type      = "SecureString"
  value     = local.gitlab_oidc_client_id_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-oidc-client-id" })
}

resource "aws_ssm_parameter" "gitlab_oidc_client_secret" {
  count = local.gitlab_oidc_client_secret_write_enabled ? 1 : 0

  name      = local.gitlab_oidc_client_secret_parameter_name
  type      = "SecureString"
  value     = local.gitlab_oidc_client_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-oidc-client-secret" })
}

resource "aws_ssm_parameter" "grafana_oidc_client_id" {
  count = local.grafana_oidc_client_id_write_enabled ? 1 : 0

  name      = local.grafana_oidc_client_id_parameter_name
  type      = "SecureString"
  value     = local.grafana_oidc_client_id_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-oidc-client-id" })
}

resource "aws_ssm_parameter" "grafana_oidc_client_secret" {
  count = local.grafana_oidc_client_secret_write_enabled ? 1 : 0

  name      = local.grafana_oidc_client_secret_parameter_name
  type      = "SecureString"
  value     = local.grafana_oidc_client_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-oidc-client-secret" })
}

resource "aws_ssm_parameter" "grafana_oidc_client_id_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_grafana && var.enable_grafana_keycloak ? local.grafana_oidc_client_id_by_realm_effective : {}

  name      = local.grafana_oidc_client_id_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-grafana-oidc-${each.key}-client-id" })
}

resource "aws_ssm_parameter" "grafana_oidc_client_secret_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_grafana && var.enable_grafana_keycloak ? local.grafana_oidc_client_secret_by_realm_effective : {}

  name      = local.grafana_oidc_client_secret_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-grafana-oidc-${each.key}-client-secret" })
}

resource "aws_ssm_parameter" "oase_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.oase_db_username_parameter_name
  type  = "String"
  value = local.oase_db_username_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-oase-db-username" })
}

resource "aws_ssm_parameter" "oase_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters && local.oase_db_password_value != null ? 1 : 0) : 0

  name  = local.oase_db_password_parameter_name
  type  = "SecureString"
  value = local.oase_db_password_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-oase-db-password" })
}

resource "aws_ssm_parameter" "oase_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.oase_db_name_parameter_name
  type  = "String"
  value = local.oase_db_name_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-oase-db-name" })
}

resource "aws_ssm_parameter" "exastro_pf_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.exastro_pf_db_username_parameter_name
  type  = "String"
  value = local.exastro_pf_db_username_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-pf-db-username" })
}

resource "aws_ssm_parameter" "exastro_pf_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters && local.exastro_pf_db_password_value != null ? 1 : 0) : 0

  name  = local.exastro_pf_db_password_parameter_name
  type  = "SecureString"
  value = local.exastro_pf_db_password_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-pf-db-password" })
}

resource "aws_ssm_parameter" "exastro_pf_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.exastro_pf_db_name_parameter_name
  type  = "String"
  value = local.exastro_pf_db_name_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-pf-db-name" })
}

resource "aws_ssm_parameter" "exastro_ita_db_username" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.exastro_ita_db_username_parameter_name
  type  = "String"
  value = local.exastro_ita_db_username_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-ita-db-username" })
}

resource "aws_ssm_parameter" "exastro_ita_db_password" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters && local.exastro_ita_db_password_value != null ? 1 : 0) : 0

  name  = local.exastro_ita_db_password_parameter_name
  type  = "SecureString"
  value = local.exastro_ita_db_password_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-ita-db-password" })
}

resource "aws_ssm_parameter" "exastro_ita_db_name" {
  count = local.ssm_writes_enabled ? (var.create_db_credentials_parameters ? 1 : 0) : 0

  name  = local.exastro_ita_db_name_parameter_name
  type  = "String"
  value = local.exastro_ita_db_name_value

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-ita-db-name" })
}

resource "aws_ssm_parameter" "gitlab_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_gitlab && local.gitlab_smtp_params_enabled ? 1 : 0) : 0

  name      = local.gitlab_smtp_username_parameter_name
  type      = "SecureString"
  value     = local.gitlab_smtp_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-smtp-username" })
}

resource "aws_ssm_parameter" "gitlab_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_gitlab && local.gitlab_smtp_params_enabled ? 1 : 0) : 0

  name      = local.gitlab_smtp_password_parameter_name
  type      = "SecureString"
  value     = local.gitlab_smtp_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-smtp-password" })
}

resource "aws_ssm_parameter" "gitlab_admin_token" {
  count = local.gitlab_admin_token_write_enabled ? 1 : 0

  name      = local.gitlab_admin_token_parameter_name
  type      = "SecureString"
  value     = local.gitlab_admin_token_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-admin-token" })
}

resource "aws_ssm_parameter" "gitlab_realm_admin_tokens_yaml" {
  count = local.ssm_writes_enabled ? (local.gitlab_realm_admin_tokens_yaml_value != null ? 1 : 0) : 0

  name      = local.gitlab_realm_admin_tokens_yaml_parameter_name
  type      = "SecureString"
  value     = local.gitlab_realm_admin_tokens_json_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-realm-admin-tokens-yaml" })
}

resource "aws_ssm_parameter" "gitlab_realm_admin_tokens_json" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_n8n && local.gitlab_realm_admin_tokens_json_value != null ? 1 : 0) : 0

  name      = local.gitlab_realm_admin_tokens_json_parameter_name
  type      = "SecureString"
  value     = local.gitlab_realm_admin_tokens_json_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-gitlab-realm-admin-tokens-json" })
}

locals {
  gitlab_realm_token_write_realms = toset([
    for realm in local.n8n_realms :
    realm
    if nonsensitive(local.gitlab_realm_admin_token_by_realm[realm] != null && trimspace(local.gitlab_realm_admin_token_by_realm[realm]) != "")
  ])
}

resource "aws_ssm_parameter" "gitlab_realm_token_by_realm" {
  for_each = (local.ssm_writes_enabled && var.create_ecs && var.create_n8n) ? local.gitlab_realm_token_write_realms : toset([])

  name      = local.gitlab_realm_token_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = local.gitlab_realm_admin_token_by_realm[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-gitlab-token-${each.key}" })
}

resource "aws_ssm_parameter" "gitlab_projects_path_json" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_n8n ? 1 : 0) : 0

  name      = local.gitlab_projects_path_json_parameter_name
  type      = "String"
  value     = local.gitlab_projects_path_json_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-gitlab-projects-path-json" })
}

resource "aws_ssm_parameter" "exastro_web_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && local.exastro_service_enabled && local.exastro_web_smtp_params_enabled ? 1 : 0) : 0

  name      = local.exastro_web_smtp_username_parameter_name
  type      = "SecureString"
  value     = local.exastro_web_smtp_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-web-smtp-username" })
}

resource "aws_ssm_parameter" "exastro_web_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && local.exastro_service_enabled && local.exastro_web_smtp_params_enabled ? 1 : 0) : 0

  name      = local.exastro_web_smtp_password_parameter_name
  type      = "SecureString"
  value     = local.exastro_web_smtp_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-web-smtp-password" })
}

resource "aws_ssm_parameter" "exastro_web_oidc_client_id" {
  count = local.exastro_web_oidc_client_id_write_enabled ? 1 : 0

  name      = local.exastro_web_oidc_client_id_parameter_name
  type      = "SecureString"
  value     = local.exastro_web_oidc_client_id_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-web-oidc-client-id" })
}

resource "aws_ssm_parameter" "exastro_web_oidc_client_secret" {
  count = local.exastro_web_oidc_client_secret_write_enabled ? 1 : 0

  name      = local.exastro_web_oidc_client_secret_parameter_name
  type      = "SecureString"
  value     = local.exastro_web_oidc_client_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-web-oidc-client-secret" })
}

resource "aws_ssm_parameter" "exastro_api_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && local.exastro_service_enabled && local.exastro_api_smtp_params_enabled ? 1 : 0) : 0

  name      = local.exastro_api_smtp_username_parameter_name
  type      = "SecureString"
  value     = local.exastro_api_smtp_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-api-smtp-username" })
}

resource "aws_ssm_parameter" "exastro_api_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && local.exastro_service_enabled && local.exastro_api_smtp_params_enabled ? 1 : 0) : 0

  name      = local.exastro_api_smtp_password_parameter_name
  type      = "SecureString"
  value     = local.exastro_api_smtp_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-api-smtp-password" })
}

resource "aws_ssm_parameter" "exastro_api_oidc_client_id" {
  count = local.exastro_api_oidc_client_id_write_enabled ? 1 : 0

  name      = local.exastro_api_oidc_client_id_parameter_name
  type      = "SecureString"
  value     = local.exastro_api_oidc_client_id_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-api-oidc-client-id" })
}

resource "aws_ssm_parameter" "exastro_api_oidc_client_secret" {
  count = local.exastro_api_oidc_client_secret_write_enabled ? 1 : 0

  name      = local.exastro_api_oidc_client_secret_parameter_name
  type      = "SecureString"
  value     = local.exastro_api_oidc_client_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-api-oidc-client-secret" })
}


resource "aws_ssm_parameter" "pgadmin_smtp_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_pgadmin && local.pgadmin_smtp_params_enabled ? 1 : 0) : 0

  name = local.pgadmin_smtp_username_parameter_name
  type = "SecureString"
  # Quote the value so pgAdmin's config_distro.py sees a valid Python string literal.
  value     = local.pgadmin_smtp_username_value != null ? jsonencode(local.pgadmin_smtp_username_value) : null
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-pgadmin-smtp-username" })
}

resource "aws_ssm_parameter" "pgadmin_smtp_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_pgadmin && local.pgadmin_smtp_params_enabled ? 1 : 0) : 0

  name = local.pgadmin_smtp_password_parameter_name
  type = "SecureString"
  # Quote the value so pgAdmin's config_distro.py sees a valid Python string literal.
  value     = local.pgadmin_smtp_password_value != null ? jsonencode(local.pgadmin_smtp_password_value) : null
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-pgadmin-smtp-password" })
}

resource "aws_ssm_parameter" "pgadmin_oidc_client_id" {
  count = local.pgadmin_oidc_client_id_write_enabled ? 1 : 0

  name      = local.pgadmin_oidc_client_id_parameter_name
  type      = "SecureString"
  value     = local.pgadmin_oidc_client_id_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-pgadmin-oidc-client-id" })
}

resource "aws_ssm_parameter" "pgadmin_oidc_client_secret" {
  count = local.pgadmin_oidc_client_secret_write_enabled ? 1 : 0

  name      = local.pgadmin_oidc_client_secret_parameter_name
  type      = "SecureString"
  value     = local.pgadmin_oidc_client_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-pgadmin-oidc-client-secret" })
}

resource "aws_ssm_parameter" "service_control_oidc_client_id" {
  count = local.service_control_oidc_client_id_write_enabled ? 1 : 0

  name      = local.service_control_oidc_client_id_parameter_name
  type      = "SecureString"
  value     = local.service_control_oidc_client_id_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-control-oidc-client-id" })
}

resource "aws_ssm_parameter" "service_control_oidc_client_secret" {
  count = local.service_control_oidc_client_secret_write_enabled ? 1 : 0

  name      = local.service_control_oidc_client_secret_parameter_name
  type      = "SecureString"
  value     = local.service_control_oidc_client_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-svc-control-oidc-client-secret" })
}

resource "random_password" "mysql_db" {
  count            = local.ssm_writes_enabled ? (var.create_mysql_rds && var.mysql_db_password == null ? 1 : 0) : 0
  length           = 16
  lower            = true
  upper            = true
  numeric          = true
  special          = true
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%^&*()-_+="
}

resource "random_password" "grafana_admin" {
  count   = local.ssm_writes_enabled ? (var.create_ecs && var.create_grafana && var.grafana_admin_password == null ? 1 : 0) : 0
  length  = 20
  special = false
}

resource "random_password" "odoo_admin" {
  count   = local.ssm_writes_enabled ? (var.create_ecs && var.create_odoo && var.odoo_admin_password == null ? 1 : 0) : 0
  length  = 24
  special = false
}

resource "random_password" "keycloak_admin" {
  count   = local.ssm_writes_enabled ? (var.create_ecs && var.create_keycloak && var.keycloak_admin_password == null ? 1 : 0) : 0
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "odoo_admin_password" {
  # The value is always resolved from either var.odoo_admin_password or random_password.odoo_admin.
  # Keep creation gated only by create flags to avoid count depending on computed values.
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_odoo ? 1 : 0) : 0

  name      = local.odoo_admin_password_parameter_name
  type      = "SecureString"
  value     = local.odoo_admin_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-admin-password" })
}

resource "random_password" "pgadmin_default_password" {
  count   = local.ssm_writes_enabled ? (var.create_ecs && var.create_pgadmin ? 1 : 0) : 0
  length  = 20
  special = false
}

resource "random_password" "aiops_workflows_token" {
  count   = local.ssm_writes_enabled ? (var.aiops_workflows_token == null ? 1 : 0) : 0
  length  = 32
  lower   = true
  upper   = true
  numeric = true
  special = false
}

resource "aws_ssm_parameter" "pgadmin_default_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_pgadmin ? 1 : 0) : 0

  name      = local.pgadmin_default_password_parameter_name
  type      = "SecureString"
  value     = random_password.pgadmin_default_password[0].result
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-pgadmin-default-password" })
}

resource "random_password" "zulip_mq" {
  count = local.zulip_mq_password_generate ? 1 : 0

  length           = 32
  special          = true
  override_special = "!@#$%^&*()_+-=[]{}|"
}

resource "random_password" "zulip_redis_password" {
  count   = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0
  length  = 64
  special = false
}

resource "random_password" "zulip_secret_key" {
  count   = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip && var.zulip_secret_key == null ? 1 : 0) : 0
  length  = 50
  special = true
}

resource "random_password" "sulu_app_secret" {
  count   = local.ssm_writes_enabled ? (var.create_ecs && var.create_sulu && var.sulu_app_secret == null ? 1 : 0) : 0
  length  = 64
  special = true
}

resource "aws_ssm_parameter" "zulip_secret_key" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

  name      = local.zulip_secret_key_parameter_name
  type      = "SecureString"
  value     = local.zulip_secret_key_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-secret-key" })
}

resource "aws_ssm_parameter" "zulip_admin_api_key" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip && var.zulip_admin_api_key != null ? 1 : 0) : 0

  name      = local.zulip_admin_api_key_parameter_name
  type      = "SecureString"
  value     = var.zulip_admin_api_key
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-admin-api-key" })
}

resource "aws_ssm_parameter" "zulip_admin_api_key_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? toset(nonsensitive(keys({
    for realm, key in local.zulip_admin_api_key_value_by_realm :
    realm => true
    if key != null && trimspace(key) != ""
  }))) : []

  name      = local.zulip_admin_api_key_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = local.zulip_admin_api_key_value_by_realm[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-admin-api-key-${each.key}", realm = each.key })
}

resource "aws_ssm_parameter" "grafana_api_token_by_realm" {
  for_each = local.ssm_writes_enabled ? toset(nonsensitive(keys(local.grafana_api_token_by_realm_effective))) : []

  name      = "/${local.name_prefix}/grafana/api_token/${each.key}"
  type      = "SecureString"
  value     = local.grafana_api_token_by_realm_effective[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-grafana-api-token-${each.key}", realm = each.key })
}

resource "aws_ssm_parameter" "zulip_bot_tokens" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip && local.zulip_bot_tokens_value != null ? 1 : 0) : 0

  name      = local.zulip_bot_tokens_parameter_name
  type      = "SecureString"
  value     = local.zulip_bot_tokens_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-bot-tokens" })
}

resource "aws_ssm_parameter" "aiops_zulip_bot_token_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n && local.aiops_zulip_bot_tokens_map != null ? {
    for realm in local.n8n_realms :
    realm => true
    if contains(keys(nonsensitive(local.aiops_zulip_bot_tokens_map)), realm) || contains(keys(nonsensitive(local.aiops_zulip_bot_tokens_map)), "default")
  } : {}

  name      = local.aiops_zulip_bot_token_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = local.aiops_zulip_bot_token_value_by_realm[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-zulip-bot-token-${each.key}", realm = each.key })
}

resource "aws_ssm_parameter" "aiops_zulip_bot_email_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n && local.aiops_zulip_bot_emails_map != null ? {
    for realm in local.n8n_realms :
    realm => true
    if contains(keys(nonsensitive(local.aiops_zulip_bot_emails_map)), realm) || contains(keys(nonsensitive(local.aiops_zulip_bot_emails_map)), "default")
  } : {}

  name      = local.aiops_zulip_bot_email_parameter_names_by_realm[each.key]
  type      = "String"
  value     = local.aiops_zulip_bot_email_value_by_realm[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-zulip-bot-email-${each.key}", realm = each.key })
}

resource "aws_ssm_parameter" "aiops_zulip_api_base_url_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n && local.aiops_zulip_api_base_urls_map != null ? {
    for realm in local.n8n_realms :
    realm => true
    if contains(keys(nonsensitive(local.aiops_zulip_api_base_urls_map)), realm) || contains(keys(nonsensitive(local.aiops_zulip_api_base_urls_map)), "default")
  } : {}

  name      = local.aiops_zulip_api_base_url_parameter_names_by_realm[each.key]
  type      = "String"
  value     = local.aiops_zulip_api_base_url_value_by_realm[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-zulip-api-base-url-${each.key}", realm = each.key })
}

resource "aws_ssm_parameter" "aiops_zulip_outgoing_token_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n && local.aiops_zulip_outgoing_tokens_map != null ? {
    for realm in local.n8n_realms :
    realm => true
    if contains(keys(nonsensitive(local.aiops_zulip_outgoing_tokens_map)), realm) || contains(keys(nonsensitive(local.aiops_zulip_outgoing_tokens_map)), "default")
  } : {}

  name      = local.aiops_zulip_outgoing_token_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = local.aiops_zulip_outgoing_token_value_by_realm[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-zulip-outgoing-token-${each.key}", realm = each.key })
}

resource "aws_ssm_parameter" "aiops_s3_bucket_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.aiops_s3_bucket_names_by_realm : {}

  name      = local.aiops_s3_bucket_parameter_names_by_realm[each.key]
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-aiops-s3-bucket-${each.key}" })
}

resource "aws_ssm_parameter" "aiops_s3_prefix" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_n8n && local.aiops_s3_prefix_value != null ? 1 : 0) : 0

  name      = local.aiops_s3_prefix_parameter_name
  type      = "String"
  value     = local.aiops_s3_prefix_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-s3-prefix" })
}

resource "aws_ssm_parameter" "aiops_gitlab_first_contact_done_label" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_n8n && local.aiops_gitlab_first_contact_done_label_value != null ? 1 : 0) : 0

  name      = local.aiops_gitlab_first_contact_done_label_parameter_name
  type      = "String"
  value     = local.aiops_gitlab_first_contact_done_label_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-gitlab-first-contact-done-label" })
}

resource "aws_ssm_parameter" "aiops_gitlab_escalation_label" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_n8n && local.aiops_gitlab_escalation_label_value != null ? 1 : 0) : 0

  name      = local.aiops_gitlab_escalation_label_parameter_name
  type      = "String"
  value     = local.aiops_gitlab_escalation_label_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-gitlab-escalation-label" })
}

resource "aws_ssm_parameter" "aiops_workflows_token" {
  count = local.ssm_writes_enabled ? 1 : 0

  name      = local.aiops_workflows_token_parameter_name
  type      = "SecureString"
  value     = local.aiops_workflows_token_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-aiops-workflows-token" })
}

resource "aws_ssm_parameter" "openai_model_api_key_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.openai_model_api_key_by_realm_effective : {}

  name      = local.openai_model_api_key_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-openai-model-api-key-${each.key}" })
}

resource "aws_ssm_parameter" "openai_model_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.openai_model_by_realm_effective : {}

  name      = local.openai_model_parameter_names_by_realm[each.key]
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-openai-model-${each.key}" })
}

resource "aws_ssm_parameter" "openai_base_url_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.openai_base_url_by_realm_effective : {}

  name      = local.openai_base_url_parameter_names_by_realm[each.key]
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-openai-base-url-${each.key}" })
}

data "aws_ssm_parameters_by_path" "n8n_api_key" {
  count           = var.n8n_api_key == null ? 1 : 0
  path            = local.n8n_api_key_parent_path
  recursive       = false
  with_decryption = true
}

resource "aws_ssm_parameter" "zulip_redis_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

  name      = local.zulip_redis_password_parameter_name
  type      = "SecureString"
  value     = random_password.zulip_redis_password[0].result
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-redis-password" })
}

resource "aws_ssm_parameter" "db_host" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.db_host_parameter_name
  type  = "String"
  value = aws_db_instance.this[0].address

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-host" })
}

resource "aws_ssm_parameter" "db_port" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.db_port_parameter_name
  type  = "String"
  value = tostring(aws_db_instance.this[0].port)

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-port" })
}

resource "aws_ssm_parameter" "db_name" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.db_name_parameter_name
  type  = "String"
  value = var.pg_db_name

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-name" })
}

resource "aws_ssm_parameter" "zulip_datasource" {
  count = local.ssm_writes_enabled ? (var.create_rds ? 1 : 0) : 0

  name  = local.zulip_datasource_parameter_name
  type  = "SecureString"
  value = "postgres://${local.master_username}:${urlencode(local.db_password_effective)}@${aws_db_instance.this[0].address}:${aws_db_instance.this[0].port}/${var.zulip_db_name}?sslmode=require&connect_timeout=10"

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-datasource" })
}

resource "aws_ssm_parameter" "sulu_app_secret" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_sulu ? 1 : 0) : 0

  name      = local.sulu_app_secret_parameter_name
  type      = "SecureString"
  value     = local.sulu_app_secret_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-sulu-app-secret" })
}

resource "aws_ssm_parameter" "sulu_database_url" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_sulu && var.create_rds ? 1 : 0) : 0

  name      = local.sulu_database_url_parameter_name
  type      = "SecureString"
  value     = local.sulu_database_url_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-sulu-db-url" })
}

resource "aws_ssm_parameter" "sulu_mailer_dsn" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_sulu && (var.sulu_mailer_dsn != null || var.enable_ses_smtp_auto) ? 1 : 0) : 0

  name      = local.sulu_mailer_dsn_parameter_name
  type      = "SecureString"
  value     = local.sulu_mailer_dsn_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-sulu-mailer-dsn" })
}

resource "aws_ssm_parameter" "zulip_mq_username" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip && local.zulip_mq_username_value != null ? 1 : 0) : 0

  name      = local.zulip_mq_username_parameter_name
  type      = "SecureString"
  value     = local.zulip_mq_username_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-mq-username" })
}

resource "aws_ssm_parameter" "zulip_mq_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip && (var.zulip_mq_password != null || local.zulip_mq_password_generate) ? 1 : 0) : 0

  name      = local.zulip_mq_password_parameter_name
  type      = "SecureString"
  value     = local.zulip_mq_password_value
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-mq-password" })
}

# resource "aws_ssm_parameter" "zulip_mq_host" {
#   count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

#   name      = local.zulip_mq_host_parameter_name
#   type      = "String"
#   value     = coalesce(local.zulip_mq_host, "")
#   overwrite = true

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-mq-host" })
# }

# resource "aws_ssm_parameter" "zulip_mq_port" {
#   count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

#   name      = local.zulip_mq_port_parameter_name
#   type      = "String"
#   value     = local.zulip_mq_port_effective != null ? tostring(local.zulip_mq_port_effective) : ""
#   overwrite = true

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-mq-port" })
# }

# resource "aws_ssm_parameter" "zulip_mq_amqp_endpoint" {
#   count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

#   name      = local.zulip_mq_endpoint_parameter_name
#   type      = "String"
#   value     = coalesce(local.zulip_mq_amqp_endpoint, "")
#   overwrite = true

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-mq-amqp-endpoint" })
# }

# resource "aws_ssm_parameter" "zulip_redis_host" {
#   count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

#   name      = local.zulip_redis_host_parameter_name
#   type      = "String"
#   value     = coalesce(local.zulip_redis_host, "")
#   overwrite = true

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-redis-host" })
# }

# resource "aws_ssm_parameter" "zulip_redis_port" {
#   count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

#   name      = local.zulip_redis_port_parameter_name
#   type      = "String"
#   value     = tostring(local.zulip_redis_port)
#   overwrite = true

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-redis-port" })
# }

# resource "aws_ssm_parameter" "zulip_memcached_endpoint" {
#   count = local.ssm_writes_enabled ? (var.create_ecs && var.create_zulip ? 1 : 0) : 0

#   name      = local.zulip_memcached_endpoint_parameter_name
#   type      = "String"
#   value     = coalesce(local.zulip_memcached_endpoint, "")
#   overwrite = true

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-memcached-endpoint" })
# }

data "aws_ssm_parameters_by_path" "n8n_encryption_key" {
  count           = local.ssm_writes_enabled && var.create_ecs && var.create_n8n && var.n8n_encryption_key == null ? 1 : 0
  path            = local.n8n_encryption_key_parameter_name
  recursive       = false
  with_decryption = true
}

locals {
  # Note: tomap(null) returns null (not an error), so guard with coalesce to keep map operations safe.
  n8n_encryption_key_map_raw = coalesce(try(tomap(var.n8n_encryption_key), null), {})
  n8n_encryption_key_default = lookup(local.n8n_encryption_key_map_raw, "default", null)
  n8n_encryption_key_single_input = (
    var.n8n_encryption_key != null && length(local.n8n_encryption_key_map_raw) == 0
    ? tostring(var.n8n_encryption_key)
    : null
  )
  n8n_encryption_key_by_realm_raw = {
    for realm in local.n8n_realms :
    realm => try(
      compact([
        lookup(local.n8n_encryption_key_map_raw, realm, null),
        local.n8n_encryption_key_default
      ])[0],
      null
    )
  }
  n8n_encryption_key_by_realm_input = {
    for realm, key in local.n8n_encryption_key_by_realm_raw :
    realm => key
    if key != null && trimspace(key) != ""
  }
  n8n_encryption_key_params_by_path = try(data.aws_ssm_parameters_by_path.n8n_encryption_key[0], null)
  n8n_encryption_key_param_names    = try(local.n8n_encryption_key_params_by_path.names, [])
  n8n_encryption_key_param_values   = try(local.n8n_encryption_key_params_by_path.values, [])
  n8n_encryption_key_param_map = length(local.n8n_encryption_key_param_names) > 0 ? zipmap(
    local.n8n_encryption_key_param_names,
    local.n8n_encryption_key_param_values,
  ) : {}
  # Prefer the legacy single key at "/.../n8n/encryption_key". If absent, fall back to a realm-specific key
  # so refresh-only runs can still succeed without generating a new key.
  n8n_encryption_key_existing_value = try(coalesce(
    lookup(local.n8n_encryption_key_param_map, local.n8n_encryption_key_parameter_name, null),
    lookup(local.n8n_encryption_key_param_map, "${local.n8n_encryption_key_parameter_name}/${local.n8n_primary_realm}", null),
    lookup(local.n8n_encryption_key_param_map, "${local.n8n_encryption_key_parameter_name}/${local.n8n_realms[0]}", null),
  ), null)

  # If there is no configured value (single / per-realm), allow null so we can generate a key.
  n8n_encryption_key_input_any = try(coalesce(
    local.n8n_encryption_key_single_input,
    lookup(local.n8n_encryption_key_by_realm_input, local.n8n_primary_realm, null),
    lookup(local.n8n_encryption_key_by_realm_input, local.n8n_realms[0], null),
  ), null)

  n8n_encryption_key_effective = coalesce(
    local.n8n_encryption_key_input_any,
    local.n8n_encryption_key_existing_value,
    try(random_password.n8n_encryption_key[0].result, null),
  )

  # Realm-level encryption key map. Missing realms fall back to the legacy single key.
  n8n_encryption_key_by_realm_effective = merge(
    { for realm in local.n8n_realms : realm => local.n8n_encryption_key_effective },
    local.n8n_encryption_key_by_realm_input,
  )
}

resource "random_password" "n8n_encryption_key" {
  count   = local.ssm_writes_enabled && var.create_ecs && var.create_n8n && local.n8n_encryption_key_input_any == null && local.n8n_encryption_key_existing_value == null ? 1 : 0
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "n8n_encryption_key" {
  # Keep the legacy single-key parameter for backward compatibility.
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_n8n ? 1 : 0) : 0

  name      = local.n8n_encryption_key_parameter_name
  type      = "SecureString"
  value     = local.n8n_encryption_key_effective
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-encryption-key" })
}

resource "aws_ssm_parameter" "n8n_encryption_key_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? toset(local.n8n_realms) : toset([])

  name      = local.n8n_encryption_key_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = local.n8n_encryption_key_by_realm_effective[each.key]
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-encryption-key-${each.key}", realm = each.key })
}

data "aws_ssm_parameters_by_path" "observer_token" {
  count           = local.ssm_writes_enabled && var.create_ecs && (var.create_n8n || var.create_sulu) ? 1 : 0
  path            = local.observer_token_parameter_name
  recursive       = false
  with_decryption = true
}

locals {
  observer_token_params_by_path = try(data.aws_ssm_parameters_by_path.observer_token[0], null)
  observer_token_param_names    = try(local.observer_token_params_by_path.names, [])
  observer_token_param_values   = try(local.observer_token_params_by_path.values, [])
  observer_token_param_map = length(local.observer_token_param_names) > 0 ? zipmap(
    local.observer_token_param_names,
    local.observer_token_param_values,
  ) : {}
  observer_token_existing_value = lookup(
    local.observer_token_param_map,
    local.observer_token_parameter_name,
    null,
  )
  observer_token_generated_value = try(random_password.observer_token[0].result, null)
  observer_token_effective = local.ssm_writes_enabled && var.create_ecs && (var.create_n8n || var.create_sulu) ? (
    try(trimspace(local.observer_token_existing_value), "") != "" ? local.observer_token_existing_value : local.observer_token_generated_value
  ) : null
}

resource "random_password" "observer_token" {
  count   = local.ssm_writes_enabled && var.create_ecs && (var.create_n8n || var.create_sulu) ? 1 : 0
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "observer_token" {
  count = local.ssm_writes_enabled && var.create_ecs && (var.create_n8n || var.create_sulu) ? 1 : 0

  name      = local.observer_token_parameter_name
  type      = "SecureString"
  value     = local.observer_token_effective
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-observer-token" })
}

resource "aws_ssm_parameter" "n8n_admin_password" {
  count = local.ssm_writes_enabled ? (var.create_ecs && var.create_n8n && var.n8n_admin_password != null ? 1 : 0) : 0

  name      = local.n8n_admin_password_parameter_name
  type      = "SecureString"
  value     = var.n8n_admin_password
  overwrite = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-admin-password" })
}

resource "aws_ssm_parameter" "gitlab_webhook_secret_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.gitlab_webhook_secret_parameter_names_by_realm : {}

  name      = each.value
  type      = "SecureString"
  value     = local.gitlab_webhook_secret_by_realm_effective[each.key]
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-n8n-gitlab-webhook-secret-${each.key}" })
}

resource "aws_ssm_parameter" "aiops_approval_base_url_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.aiops_approval_base_url_value_by_realm : {}

  name      = local.aiops_approval_base_url_parameter_names_by_realm[each.key]
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-n8n-aiops-approval-base-url-${each.key}" })
}

resource "aws_ssm_parameter" "aiops_adapter_base_url_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.aiops_adapter_base_url_value_by_realm : {}

  name      = local.aiops_adapter_base_url_parameter_names_by_realm[each.key]
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-n8n-aiops-adapter-base-url-${each.key}" })
}

data "aws_ssm_parameters_by_path" "aiops_approval_hmac_secret" {
  count           = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? 1 : 0
  path            = "/${local.name_prefix}/n8n/aiops/approval_hmac_secret"
  recursive       = true
  with_decryption = true
}

locals {
  aiops_approval_hmac_secret_params_by_path = try(data.aws_ssm_parameters_by_path.aiops_approval_hmac_secret[0], null)
  aiops_approval_hmac_secret_param_names    = try(local.aiops_approval_hmac_secret_params_by_path.names, [])
  aiops_approval_hmac_secret_param_values   = try(local.aiops_approval_hmac_secret_params_by_path.values, [])
  aiops_approval_hmac_secret_param_map = length(local.aiops_approval_hmac_secret_param_names) > 0 ? zipmap(
    local.aiops_approval_hmac_secret_param_names,
    local.aiops_approval_hmac_secret_param_values,
  ) : {}
  aiops_approval_hmac_secret_existing_by_realm = {
    for realm in local.n8n_realms :
    realm => lookup(local.aiops_approval_hmac_secret_param_map, local.aiops_approval_hmac_secret_parameter_names_by_realm[realm], null)
  }
  aiops_approval_hmac_secret_missing_realms = toset([
    for realm in local.n8n_realms :
    realm
    if try(trimspace(local.aiops_approval_hmac_secret_existing_by_realm[realm]), "") == ""
  ])
}

resource "random_password" "aiops_approval_hmac_secret" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? toset(local.n8n_realms) : toset([])

  length  = 64
  special = false
}

locals {
  aiops_approval_hmac_secret_value_by_realm = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? {
    for realm in local.n8n_realms :
    realm => (
      try(trimspace(local.aiops_approval_hmac_secret_existing_by_realm[realm]), "") != "" ? local.aiops_approval_hmac_secret_existing_by_realm[realm] : try(random_password.aiops_approval_hmac_secret[realm].result, null)
    )
  } : {}
  aiops_approval_hmac_secret_write_values_by_realm = {
    for realm, value in local.aiops_approval_hmac_secret_value_by_realm :
    realm => value
    if value != null && try(trimspace(value), "") != ""
  }
}

resource "aws_ssm_parameter" "aiops_approval_hmac_secret_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? toset(local.n8n_realms) : toset([])

  name      = local.aiops_approval_hmac_secret_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = try(local.aiops_approval_hmac_secret_value_by_realm[each.key], "")
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-n8n-aiops-approval-hmac-secret-${each.key}" })
}

data "aws_ssm_parameters_by_path" "aiops_cloudwatch_webhook_secret" {
  count           = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? 1 : 0
  path            = "/${local.name_prefix}/n8n/aiops/cloudwatch_webhook_secret"
  recursive       = true
  with_decryption = true
}

locals {
  aiops_cloudwatch_webhook_secret_params_by_path = try(data.aws_ssm_parameters_by_path.aiops_cloudwatch_webhook_secret[0], null)
  aiops_cloudwatch_webhook_secret_param_names    = try(local.aiops_cloudwatch_webhook_secret_params_by_path.names, [])
  aiops_cloudwatch_webhook_secret_param_values   = try(local.aiops_cloudwatch_webhook_secret_params_by_path.values, [])
  aiops_cloudwatch_webhook_secret_param_map = length(local.aiops_cloudwatch_webhook_secret_param_names) > 0 ? zipmap(
    local.aiops_cloudwatch_webhook_secret_param_names,
    local.aiops_cloudwatch_webhook_secret_param_values,
  ) : {}
  aiops_cloudwatch_webhook_secret_existing_by_realm = {
    for realm in local.n8n_realms :
    realm => lookup(local.aiops_cloudwatch_webhook_secret_param_map, local.aiops_cloudwatch_webhook_secret_parameter_names_by_realm[realm], null)
  }
  aiops_cloudwatch_webhook_secret_missing_realms = toset([
    for realm in local.n8n_realms :
    realm
    if try(trimspace(local.aiops_cloudwatch_webhook_secret_existing_by_realm[realm]), "") == ""
  ])
}

resource "random_password" "aiops_cloudwatch_webhook_secret" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? toset(local.n8n_realms) : toset([])

  length  = 64
  special = false
}

locals {
  aiops_cloudwatch_webhook_secret_value_by_realm = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? {
    for realm in local.n8n_realms :
    realm => (
      try(trimspace(local.aiops_cloudwatch_webhook_secret_existing_by_realm[realm]), "") != "" ? local.aiops_cloudwatch_webhook_secret_existing_by_realm[realm] : try(random_password.aiops_cloudwatch_webhook_secret[realm].result, null)
    )
  } : {}
  aiops_cloudwatch_webhook_secret_write_values_by_realm = {
    for realm, value in local.aiops_cloudwatch_webhook_secret_value_by_realm :
    realm => value
    if value != null && try(trimspace(value), "") != ""
  }
}

resource "aws_ssm_parameter" "aiops_cloudwatch_webhook_secret_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? toset(local.n8n_realms) : toset([])

  name      = local.aiops_cloudwatch_webhook_secret_parameter_names_by_realm[each.key]
  type      = "SecureString"
  value     = try(local.aiops_cloudwatch_webhook_secret_value_by_realm[each.key], "")
  overwrite = true

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-n8n-aiops-cloudwatch-webhook-secret-${each.key}" })
}

locals {
  aiops_ingest_limits_values_by_param = merge([
    for realm in local.n8n_realms : {
      "${local.aiops_ingest_limits_parameter_names_by_realm[realm].N8N_INGEST_RATE_LIMIT_RPS}"    = tostring(var.aiops_ingest_rate_limit_rps)
      "${local.aiops_ingest_limits_parameter_names_by_realm[realm].N8N_INGEST_BURST_RPS}"         = tostring(var.aiops_ingest_burst_rps)
      "${local.aiops_ingest_limits_parameter_names_by_realm[realm].N8N_TENANT_RATE_LIMIT_RPS}"    = tostring(var.aiops_tenant_rate_limit_rps)
      "${local.aiops_ingest_limits_parameter_names_by_realm[realm].N8N_INGEST_PAYLOAD_MAX_BYTES}" = tostring(var.aiops_ingest_payload_max_bytes)
    }
  ]...)
}

resource "aws_ssm_parameter" "aiops_ingest_limits_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? local.aiops_ingest_limits_values_by_param : {}

  name      = each.key
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = basename(each.key), Name = "${local.name_prefix}-n8n-aiops-ingest-limits" })
}

locals {
  itsm_monitoring_context_values_by_param = {
    for realm, cfg in local.itsm_monitoring_context_by_realm :
    local.itsm_monitoring_context_parameter_names_by_realm[realm] => jsonencode(cfg)
  }
}

resource "aws_ssm_parameter" "itsm_monitoring_context_by_realm" {
  for_each = local.ssm_writes_enabled && var.create_ecs ? local.itsm_monitoring_context_values_by_param : {}

  name      = each.key
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(local.tags, { realm = basename(each.key), Name = "${local.name_prefix}-itsm-monitoring-context" })
}

locals {
  aiops_workflows_token_value = local.ssm_writes_enabled ? (
    var.aiops_workflows_token != null ? var.aiops_workflows_token : try(random_password.aiops_workflows_token[0].result, null)
  ) : null
  n8n_api_key_parameters_by_path = try(data.aws_ssm_parameters_by_path.n8n_api_key[0], null)
  n8n_api_key_names              = try(local.n8n_api_key_parameters_by_path.names, [])
  n8n_api_key_values             = try(local.n8n_api_key_parameters_by_path.values, [])
  n8n_api_key_map                = length(local.n8n_api_key_names) > 0 ? zipmap(local.n8n_api_key_names, local.n8n_api_key_values) : {}
  n8n_api_key_value              = var.n8n_api_key != null ? var.n8n_api_key : lookup(local.n8n_api_key_map, local.n8n_api_key_parameter_name, null)
}
