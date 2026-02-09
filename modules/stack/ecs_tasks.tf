locals {
  account_id               = data.aws_caller_identity.current.account_id
  create_exastro_effective = var.create_exastro
  enabled_services = var.create_ecs ? compact([
    var.create_n8n ? "n8n" : "",
    local.exastro_service_enabled ? "exastro" : "",
    var.create_sulu ? "sulu" : "",
    var.create_keycloak ? "keycloak" : "",
    var.create_odoo ? "odoo" : "",
    var.create_pgadmin ? "pgadmin" : "",
    var.create_gitlab ? "gitlab" : "",
    var.create_gitlab_runner ? "gitlab-runner" : "",
    var.create_grafana && var.create_gitlab ? "grafana" : "",
    var.create_zulip ? "zulip" : ""
  ]) : []
  exastro_service_enabled = local.create_exastro_effective
  exastro_task_cpu = min(
    4096,
    max(
      coalesce(var.exastro_task_cpu, var.ecs_task_cpu),
      coalesce(var.exastro_task_cpu, var.ecs_task_cpu)
    ) * 2
  )
  exastro_task_memory = max(
    coalesce(var.exastro_task_memory, var.ecs_task_memory),
    coalesce(var.exastro_task_memory, var.ecs_task_memory)
  ) * 2
  ecr_uri_n8n              = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_n8n}:latest"
  ecr_registry_prefix      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}"
  ecr_uri_alpine_base      = "${local.ecr_registry_prefix}/${var.ecr_repo_alpine}"
  alpine_image_3_19        = "${local.ecr_uri_alpine_base}:3.19"
  alpine_image_3_20        = "${local.ecr_uri_alpine_base}:3.20"
  redis_image              = "${local.ecr_registry_prefix}/${var.ecr_repo_redis}:7.2-alpine"
  memcached_image          = "${local.ecr_registry_prefix}/${var.ecr_repo_memcached}:1.6-alpine"
  rabbitmq_image           = "${local.ecr_registry_prefix}/${var.ecr_repo_rabbitmq}:3.13-alpine"
  mongo_image              = "${local.ecr_registry_prefix}/${var.ecr_repo_mongo}:7.0"
  python_image             = "${local.ecr_registry_prefix}/${var.ecr_repo_python}:3.12-alpine"
  qdrant_image             = "${local.ecr_registry_prefix}/${var.ecr_repo_qdrant}:${var.qdrant_image_tag}"
  ecr_uri_exastro_web      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_exastro_it_automation_web_server}:latest"
  ecr_uri_exastro_api      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_exastro_it_automation_api_admin}:latest"
  sulu_image_tag_effective = var.sulu_image_tag != null && var.sulu_image_tag != "" ? var.sulu_image_tag : "latest"
  ecr_uri_sulu             = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_sulu}:${local.sulu_image_tag_effective}"
  ecr_uri_sulu_nginx       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_sulu_nginx}:${local.sulu_image_tag_effective}"
  ecr_uri_pgadmin          = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_pgadmin}:latest"
  ecr_uri_keycloak         = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_keycloak}:latest"
  ecr_uri_odoo             = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_odoo}:latest"
  ecr_uri_gitlab           = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_gitlab}:latest"
  ecr_uri_gitlab_runner    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_gitlab_runner}:latest"
  ecr_uri_grafana          = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_grafana}:latest"
  ecr_uri_zulip            = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_zulip}:latest"
  default_realm            = local.keycloak_realm_effective
  keycloak_issuer_url      = "https://keycloak.${local.hosted_zone_name_input}/realms/${local.default_realm}"
  keycloak_auth_url        = "${local.keycloak_issuer_url}/protocol/openid-connect/auth"
  keycloak_token_url       = "${local.keycloak_issuer_url}/protocol/openid-connect/token"
  keycloak_userinfo_url    = "${local.keycloak_issuer_url}/protocol/openid-connect/userinfo"
  odoo_oidc_issuer_url     = trim(coalesce(local.oidc_idps_issuer_url_from_yaml["odoo"], local.keycloak_issuer_url), "/")
  odoo_oidc_scopes         = coalesce(local.oidc_idps_scope_from_yaml["odoo"], "openid profile email")
  gitlab_oidc_issuer_url   = trim(coalesce(local.oidc_idps_issuer_url_from_yaml["gitlab"], local.keycloak_issuer_url), "/")
  gitlab_oidc_scope_raw    = coalesce(local.oidc_idps_scope_from_yaml["gitlab"], "openid profile email")
  gitlab_oidc_scopes       = regexall("[^\\s]+", local.gitlab_oidc_scope_raw)
  gitlab_oidc_label        = coalesce(local.oidc_idps_display_name_from_yaml["gitlab"], "Keycloak")
  keycloak_host_for_oidc   = "${local.service_subdomain_map["keycloak"]}.${local.hosted_zone_name_input}"
  grafana_oidc_issuer_url_effective_by_realm = {
    for realm in local.grafana_realms :
    realm => trim(coalesce(
      local.grafana_oidc_issuer_url_by_realm[realm],
      "https://${local.keycloak_host_for_oidc}/realms/${realm}"
    ), "/")
  }
  grafana_oidc_auth_url_by_realm = {
    for realm, issuer in local.grafana_oidc_issuer_url_effective_by_realm :
    realm => "${issuer}/protocol/openid-connect/auth"
  }
  grafana_oidc_token_url_by_realm = {
    for realm, issuer in local.grafana_oidc_issuer_url_effective_by_realm :
    realm => "${issuer}/protocol/openid-connect/token"
  }
  grafana_oidc_userinfo_url_effective_by_realm = {
    for realm, issuer in local.grafana_oidc_issuer_url_effective_by_realm :
    realm => coalesce(local.grafana_oidc_userinfo_url_by_realm[realm], "${issuer}/protocol/openid-connect/userinfo")
  }
  grafana_oidc_scopes_effective_by_realm = {
    for realm in local.grafana_realms :
    realm => coalesce(local.grafana_oidc_scopes_by_realm[realm], "openid profile email")
  }
  grafana_oidc_display_name_effective_by_realm = {
    for realm in local.grafana_realms :
    realm => coalesce(local.grafana_oidc_display_name_by_realm[realm], "Keycloak (${realm})")
  }
  xray_n8n_enabled     = contains(local.xray_services_set, "n8n")
  xray_grafana_enabled = contains(local.xray_services_set, "grafana")
  xray_daemon_image    = "${local.ecr_registry_prefix}/${var.ecr_repo_xray_daemon}:3.3.9"
  xray_daemon_container_common = merge(local.ecs_base_container, {
    image     = local.xray_daemon_image
    essential = false
    portMappings = [{
      containerPort = 2000
      hostPort      = 2000
      protocol      = "udp"
    }]
    environment = [
      { name = "AWS_REGION", value = var.region }
    ]
  })
  xray_daemon_env = {
    AWS_XRAY_DAEMON_ADDRESS = "127.0.0.1:2000"
  }
  pgadmin_oidc_issuer_url                           = trim(coalesce(local.oidc_idps_issuer_url_from_yaml["pgadmin"], local.keycloak_issuer_url), "/")
  pgadmin_oidc_metadata_url                         = "${local.pgadmin_oidc_issuer_url}/.well-known/openid-configuration"
  pgadmin_oidc_auth_url                             = "${local.pgadmin_oidc_issuer_url}/protocol/openid-connect/auth"
  pgadmin_oidc_token_url                            = "${local.pgadmin_oidc_issuer_url}/protocol/openid-connect/token"
  pgadmin_oidc_userinfo_url                         = coalesce(local.oidc_idps_userinfo_url_from_yaml["pgadmin"], "${local.pgadmin_oidc_issuer_url}/protocol/openid-connect/userinfo")
  pgadmin_oidc_api_base_url                         = local.pgadmin_oidc_issuer_url
  pgadmin_oidc_scope                                = coalesce(local.oidc_idps_scope_from_yaml["pgadmin"], "openid email profile")
  pgadmin_oidc_display_name                         = coalesce(local.oidc_idps_display_name_from_yaml["pgadmin"], "Keycloak")
  exastro_web_oidc_issuer_url                       = trim(coalesce(local.oidc_idps_issuer_url_from_yaml["exastro_web"], local.keycloak_issuer_url), "/")
  exastro_web_oidc_auth_url                         = "${local.exastro_web_oidc_issuer_url}/protocol/openid-connect/auth"
  exastro_web_oidc_token_url                        = "${local.exastro_web_oidc_issuer_url}/protocol/openid-connect/token"
  exastro_web_oidc_userinfo_url                     = coalesce(local.oidc_idps_userinfo_url_from_yaml["exastro_web"], "${local.exastro_web_oidc_issuer_url}/protocol/openid-connect/userinfo")
  exastro_api_oidc_issuer_url                       = trim(coalesce(local.oidc_idps_issuer_url_from_yaml["exastro_api"], local.keycloak_issuer_url), "/")
  exastro_api_oidc_auth_url                         = "${local.exastro_api_oidc_issuer_url}/protocol/openid-connect/auth"
  exastro_api_oidc_token_url                        = "${local.exastro_api_oidc_issuer_url}/protocol/openid-connect/token"
  exastro_api_oidc_userinfo_url                     = coalesce(local.oidc_idps_userinfo_url_from_yaml["exastro_api"], "${local.exastro_api_oidc_issuer_url}/protocol/openid-connect/userinfo")
  keycloak_email_domain                             = coalesce(local.ses_domain, local.hosted_zone_name_input, "example.com")
  n8n_smtp_sender_effective                         = coalesce(var.n8n_smtp_sender, "no-reply@${local.hosted_zone_name_input}")
  pgadmin_admin_email_effective                     = coalesce(var.pgadmin_email, "admin@${local.hosted_zone_name_input}")
  pgadmin_default_sender_effective                  = coalesce(var.pgadmin_default_sender, "no-reply@${local.hosted_zone_name_input}")
  gitlab_email_from_effective                       = coalesce(var.gitlab_email_from, "gitlab@${local.hosted_zone_name_input}")
  gitlab_email_reply_to_effective                   = coalesce(var.gitlab_email_reply_to, "noreply@${local.hosted_zone_name_input}")
  gitlab_ssh_port_effective                         = coalesce(var.gitlab_ssh_port, 22)
  gitlab_ssh_host_effective                         = coalesce(var.gitlab_ssh_host, "gitlab-ssh.${local.hosted_zone_name_input}")
  sulu_admin_email_effective                        = coalesce(var.sulu_admin_email, "admin@${local.hosted_zone_name_input}")
  zulip_admin_email_effective                       = coalesce(var.zulip_admin_email, "admin@${local.hosted_zone_name_input}")
  keycloak_realm_master_email_from                  = coalesce(var.keycloak_realm_master_email_from, "admin@${local.keycloak_email_domain}")
  keycloak_realm_master_email_from_display_name     = coalesce(var.keycloak_realm_master_email_from_display_name, "Admin")
  keycloak_realm_master_email_reply_to              = coalesce(var.keycloak_realm_master_email_reply_to, "admin@${local.keycloak_email_domain}")
  keycloak_realm_master_email_reply_to_display_name = coalesce(var.keycloak_realm_master_email_reply_to_display_name, "Admin")
  keycloak_realm_master_email_envelope_from         = coalesce(var.keycloak_realm_master_email_envelope_from, "admin@${local.keycloak_email_domain}")
  keycloak_realm_master_email_allow_utf8            = coalesce(var.keycloak_realm_master_email_allow_utf8, true)
  keycloak_realm_master_i18n_enabled                = var.keycloak_realm_master_i18n_enabled
  keycloak_realm_master_supported_locales           = length(var.keycloak_realm_master_supported_locales) > 0 ? var.keycloak_realm_master_supported_locales : ["ja", "en"]
  keycloak_realm_master_default_locale              = coalesce(var.keycloak_realm_master_default_locale, "ja")
  default_ssm_params_n8n_base = {
    DB_USER                             = local.n8n_db_username_parameter_name
    DB_PASSWORD                         = local.n8n_db_password_parameter_name
    DB_HOST                             = local.db_host_parameter_name
    DB_PORT                             = local.db_port_parameter_name
    DB_POSTGRESDB_HOST                  = local.db_host_parameter_name
    DB_POSTGRESDB_PORT                  = local.db_port_parameter_name
    DB_POSTGRESDB_USER                  = local.n8n_db_username_parameter_name
    DB_POSTGRESDB_PASSWORD              = local.n8n_db_password_parameter_name
    N8N_KEYCLOAK_ADMIN_USERNAME         = local.keycloak_admin_username_parameter_name
    N8N_KEYCLOAK_ADMIN_PASSWORD         = local.keycloak_admin_password_parameter_name
    N8N_WORKFLOWS_TOKEN                 = local.aiops_workflows_token_parameter_name
    N8N_S3_PREFIX                       = local.aiops_s3_prefix_parameter_name
    N8N_GITLAB_FIRST_CONTACT_DONE_LABEL = local.aiops_gitlab_first_contact_done_label_parameter_name
    N8N_GITLAB_ESCALATION_LABEL         = local.aiops_gitlab_escalation_label_parameter_name
    N8N_API_KEY                         = local.n8n_api_key_parameter_name
    N8N_ADMIN_PASSWORD                  = local.n8n_admin_password_parameter_name
    N8N_OBSERVER_TOKEN                  = local.observer_token_parameter_name
  }
  default_ssm_params_n8n_db_name = local.n8n_use_realm_suffix ? {} : {
    DB_NAME                = local.n8n_db_name_parameter_name
    DB_POSTGRESDB_DATABASE = local.n8n_db_name_parameter_name
  }
  default_ssm_params_n8n = merge(local.default_ssm_params_n8n_base, local.default_ssm_params_n8n_db_name)
  optional_smtp_params_n8n = local.n8n_smtp_username_value != null && local.n8n_smtp_password_value != null ? {
    N8N_SMTP_USER = local.n8n_smtp_username_parameter_name
    N8N_SMTP_PASS = local.n8n_smtp_password_parameter_name
  } : {}
  optional_zulip_bot_tokens_params_n8n = local.zulip_bot_tokens_value != null ? {
    ZULIP_BOT_TOKEN = local.zulip_bot_tokens_parameter_name
  } : {}
  service_control_token_url = "${trim(local.keycloak_base_url_effective, "/")}/realms/${local.keycloak_realm_effective}/protocol/openid-connect/token"
  service_control_oidc_params_enabled = var.service_control_jwt_issuer != null && length(local.service_control_jwt_audiences_effective) > 0 && (
    var.service_control_oidc_client_id != null ||
    var.service_control_oidc_client_secret != null ||
    var.service_control_oidc_client_id_parameter_name != null ||
    var.service_control_oidc_client_secret_parameter_name != null
  )
  optional_service_control_params_n8n = local.service_control_oidc_params_enabled ? {
    SERVICE_CONTROL_CLIENT_ID     = local.service_control_oidc_client_id_parameter_name
    SERVICE_CONTROL_CLIENT_SECRET = local.service_control_oidc_client_secret_parameter_name
  } : {}
  default_ssm_params_exastro = {
    DB_HOST     = local.db_host_parameter_name
    DB_PORT     = local.db_port_parameter_name
    DB_DATABASE = local.oase_db_name_parameter_name
    DB_USER     = local.oase_db_username_parameter_name
    DB_PASSWORD = local.oase_db_password_parameter_name
  }
  # Prefer user-supplied filesystem IDs only when they are non-null/non-empty; otherwise fall back to the discovered/created EFS IDs.
  n8n_efs_id = (
    var.n8n_filesystem_id != null && var.n8n_filesystem_id != "" ? var.n8n_filesystem_id :
    try(local.n8n_filesystem_id_effective, null)
  )
  sulu_efs_id = (
    var.sulu_filesystem_id != null && var.sulu_filesystem_id != "" ? var.sulu_filesystem_id :
    try(local.sulu_filesystem_id_effective, null)
  )
  zulip_efs_id = (
    var.zulip_filesystem_id != null && var.zulip_filesystem_id != "" ? var.zulip_filesystem_id :
    try(local.zulip_filesystem_id_effective, null)
  )
  pgadmin_efs_id = (
    var.pgadmin_filesystem_id != null && var.pgadmin_filesystem_id != "" ? var.pgadmin_filesystem_id :
    try(local.pgadmin_filesystem_id_effective, null)
  )
  exastro_efs_id = (
    var.exastro_filesystem_id != null && var.exastro_filesystem_id != "" ? var.exastro_filesystem_id :
    try(local.exastro_filesystem_id_effective, null)
  )
  keycloak_efs_id      = try(local.keycloak_filesystem_id_effective, null)
  odoo_efs_id          = try(local.odoo_filesystem_id_effective, null)
  gitlab_data_efs_id   = local.gitlab_data_filesystem_id_effective
  gitlab_config_efs_id = local.gitlab_config_filesystem_id_effective
  grafana_efs_id       = try(local.grafana_filesystem_id_effective, null)
  default_environment_n8n_base = merge(
    {
      DB_TYPE                               = "postgresdb"
      DB_POSTGRESDB_SSL                     = jsonencode({ rejectUnauthorized = false })
      DB_POSTGRESDB_SSL_ENABLED             = "true"
      DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED = "false"
      DB_POSTGRESDB_POOL_SIZE               = tostring(var.n8n_db_postgresdb_pool_size)
      DB_POSTGRESDB_CONNECTION_TIMEOUT      = tostring(var.n8n_db_postgresdb_connection_timeout)
      DB_POSTGRESDB_IDLE_CONNECTION_TIMEOUT = tostring(var.n8n_db_postgresdb_idle_connection_timeout)
      DB_PING_INTERVAL_SECONDS              = tostring(var.n8n_db_ping_interval_seconds)
      NODE_FUNCTION_ALLOW_BUILTIN           = "crypto"
      N8N_KEYCLOAK_BASE_URL                 = trim(local.keycloak_base_url_effective, "/")
      N8N_KEYCLOAK_ADMIN_REALM              = "master"
      N8N_ZULIP_ENFORCE_KEYCLOAK_MEMBERSHIP = "true"
      N8N_DEBUG_LOG                         = "false"
      N8N_SMTP_SENDER                       = local.n8n_smtp_sender_effective
      N8N_SMTP_HOST                         = "email-smtp.${var.region}.amazonaws.com"
      N8N_SMTP_PORT                         = "587"
      N8N_SMTP_SSL                          = "false"
      N8N_PROTOCOL                          = "https"
      N8N_METRICS                           = "true"
      N8N_DEFAULT_LOCALE                    = "ja"
      N8N_PUBLIC_API_DISABLED               = "false"
      N8N_ADMIN_EMAIL                       = local.n8n_admin_email_value
      # Enable decision/approval recognition by LLM for Zulip<->GitLab sync workflows by default.
      # (Workflows still require DECISION_LLM_API_* values to actually call the model.)
      ZULIP_GITLAB_DECISION_LLM_ENABLED = "true"
      GITLAB_DECISION_LLM_ENABLED       = "true"
      GENERIC_TIMEZONE                  = "Asia/Tokyo"
      SERVICE_CONTROL_API_BASE_URL      = local.service_control_api_base_url_effective
      SERVICE_CONTROL_TOKEN_URL         = local.service_control_token_url
    }
  )
  default_environment_keycloak = {
    KC_PROXY                            = "edge"
    KC_PROXY_HEADERS                    = "xforwarded"
    KC_HTTP_ENABLED                     = "true"
    KC_HTTP_MANAGEMENT_ENABLED          = "true"
    KC_HTTP_MANAGEMENT_PORT             = "9000"
    KC_HOSTNAME                         = "keycloak.${local.hosted_zone_name_input}"
    KC_HOSTNAME_STRICT                  = "false"
    KC_HOSTNAME_STRICT_HTTPS            = "true"
    KEYCLOAK_FRONTEND_URL               = "${trim(local.keycloak_base_url_effective, "/")}/"
    KC_METRICS_ENABLED                  = "false"
    KC_HEALTH_ENABLED                   = "true"
    KC_DB                               = "postgres"
    KC_SPI_EMAIL_SMTP_HOST              = "email-smtp.${var.region}.amazonaws.com"
    KC_SPI_EMAIL_SMTP_PORT              = "587"
    KC_SPI_EMAIL_SMTP_FROM              = local.keycloak_realm_master_email_from
    KC_SPI_EMAIL_SMTP_FROM_DISPLAY_NAME = local.keycloak_realm_master_email_from_display_name
    KC_SPI_EMAIL_SMTP_AUTH              = "true"
    KC_SPI_EMAIL_SMTP_STARTTLS          = "true"
    KEYCLOAK_IMPORT                     = "${var.keycloak_filesystem_path}/import/realm-ja.json"
    KEYCLOAK_IMPORT_STRATEGY            = "IGNORE_EXISTING"
    TZ                                  = "Asia/Tokyo"
    LANG                                = "ja_JP.UTF-8"
    LANGUAGE                            = "ja_JP:ja"
    LC_ALL                              = "ja_JP.UTF-8"
  }
  default_environment_odoo = {
    DB_SSLMODE             = "require"
    PGSSLMODE              = "require"
    PROXY_MODE             = "True"
    SMTP_SERVER            = "email-smtp.${var.region}.amazonaws.com"
    SMTP_PORT              = "587"
    ODOO_OIDC_ISSUER       = local.odoo_oidc_issuer_url
    ODOO_OIDC_REDIRECT_URI = "https://odoo.${local.hosted_zone_name_input}/auth_oauth/signin"
    ODOO_OIDC_SCOPES       = local.odoo_oidc_scopes
    ODOO_ADDONS_PATH       = "/usr/lib/python3/dist-packages/odoo/addons,${var.odoo_filesystem_path}/extra-addons"
    TZ                     = "Asia/Tokyo"
    LANG                   = "ja_JP.UTF-8"
    LC_ALL                 = "ja_JP.UTF-8"
  }
  # pgAdmin expects PGADMIN_CONFIG_* values as valid Python literals; quote strings so config_distro.py parses correctly.
  default_environment_pgadmin = {
    PGADMIN_DEFAULT_EMAIL                  = local.pgadmin_admin_email_effective
    PGADMIN_CONFIG_AUTHENTICATION_SOURCES  = jsonencode(["oauth2"])
    PGADMIN_CONFIG_OAUTH2_AUTO_CREATE_USER = "True"
    PGADMIN_CONFIG_DEFAULT_LANGUAGE        = jsonencode("ja")
    PGADMIN_CONFIG_MAIL_SERVER             = jsonencode("email-smtp.${var.region}.amazonaws.com")
    PGADMIN_CONFIG_MAIL_PORT               = "587"
    PGADMIN_CONFIG_MAIL_USE_SSL            = "False"
    PGADMIN_CONFIG_MAIL_USE_TLS            = "True"
    PGADMIN_CONFIG_MAIL_DEFAULT_SENDER     = jsonencode(local.pgadmin_default_sender_effective)
    PGADMIN_CONFIG_OAUTH2_CONFIG = jsonencode([
      {
        OAUTH2_NAME                = "keycloak"
        OAUTH2_DISPLAY_NAME        = local.pgadmin_oidc_display_name
        OAUTH2_CLIENT_ID           = "$${PGADMIN_OIDC_CLIENT_ID}"
        OAUTH2_CLIENT_SECRET       = "$${PGADMIN_OIDC_CLIENT_SECRET}"
        OAUTH2_SERVER_METADATA_URL = local.pgadmin_oidc_metadata_url
        OAUTH2_AUTHORIZATION_URL   = local.pgadmin_oidc_auth_url
        OAUTH2_TOKEN_URL           = local.pgadmin_oidc_token_url
        OAUTH2_API_BASE_URL        = local.pgadmin_oidc_api_base_url
        OAUTH2_USERINFO_ENDPOINT   = local.pgadmin_oidc_userinfo_url
        OAUTH2_SCOPE               = local.pgadmin_oidc_scope
        OAUTH2_USERNAME_CLAIM      = "preferred_username"
        OAUTH2_ICON                = "fa-key"
        OAUTH2_BUTTON_COLOR        = "#2C4F9E"
      }
    ])
  }
  default_environment_gitlab = merge({
    GITLAB_OMNIBUS_CONFIG = <<-EOT
		      external_url 'https://gitlab.${local.hosted_zone_name_input}'
	      gitlab_rails['gitlab_shell_ssh_port'] = ${local.gitlab_ssh_port_effective}
	      gitlab_rails['gitlab_ssh_host'] = '${local.gitlab_ssh_host_effective}'
	      # Redis unix socket cannot live on EFS (NFS). Keep Redis data on EFS, but place the socket on local FS.
	      redis['unixsocket'] = '/tmp/gitlab-redis.socket'
	      redis['unixsocketperm'] = 777
	      gitlab_rails['redis_socket'] = '/tmp/gitlab-redis.socket'
	      sidekiq['redis_socket'] = '/tmp/gitlab-redis.socket'
	      gitlab_workhorse['redis_socket'] = '/tmp/gitlab-redis.socket'
	      # Avoid unix sockets on EFS (NFS): keep Gitaly socket/runtime on local FS.
	      gitaly['configuration'] = {
	        socket_path: '/tmp/gitaly.socket',
	        runtime_dir: '/tmp',
	      }
	      # Avoid unix sockets on EFS (NFS): keep Rails<->Workhorse socket on local FS.
	      puma['socket'] = '/tmp/gitlab.socket'
	      gitlab_workhorse['auth_socket'] = '/tmp/gitlab.socket'
	      # Avoid unix sockets on EFS (NFS): use localhost TCP for gitlab-shell internal API.
	      gitlab_workhorse['listen_network'] = 'tcp'
	      gitlab_workhorse['listen_addr'] = '127.0.0.1:8181'
	      gitlab_shell['gitlab_url'] = 'http://127.0.0.1:8181'
	      postgresql['enable'] = false
      nginx['listen_port'] = 80
      nginx['listen_https'] = false
      nginx['redirect_http_to_https'] = false
      letsencrypt['enable'] = false
      gitlab_rails['time_zone'] = 'Asia/Tokyo'
      gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '::1/128', '${data.aws_vpc.selected.cidr_block}']
      gitlab_rails['db_adapter'] = 'postgresql'
      gitlab_rails['db_encoding'] = 'unicode'
      gitlab_rails['db_host'] = ENV['GITLAB_DB_HOST']
      gitlab_rails['db_port'] = (ENV['GITLAB_DB_PORT'] || '5432')
      gitlab_rails['db_username'] = ENV['GITLAB_DB_USER']
      gitlab_rails['db_password'] = ENV['GITLAB_DB_PASSWORD']
      gitlab_rails['db_database'] = ENV['GITLAB_DB_NAME']
      gitlab_rails['db_sslmode'] = 'require'
      gitlab_rails['gitlab_email_from'] = "${local.gitlab_email_from_effective}"
      gitlab_rails['gitlab_email_display_name'] = 'GitLab'
      gitlab_rails['gitlab_email_reply_to'] = "${local.gitlab_email_reply_to_effective}"
      gitlab_rails['smtp_enable'] = true
      gitlab_rails['smtp_address'] = "email-smtp.${var.region}.amazonaws.com"
      gitlab_rails['smtp_port'] = 587
      gitlab_rails['smtp_domain'] = '${local.hosted_zone_name_input}'
      gitlab_rails['smtp_authentication'] = 'login'
      gitlab_rails['smtp_enable_starttls_auto'] = true
      gitlab_rails['smtp_tls'] = false
      gitlab_rails['smtp_user_name'] = ENV['GITLAB_SMTP_USER'] if ENV['GITLAB_SMTP_USER']
      gitlab_rails['smtp_password'] = ENV['GITLAB_SMTP_PASS'] if ENV['GITLAB_SMTP_PASS']
      # Honor TLS termination at ALB
      nginx['custom_nginx_config'] = "proxy_set_header X-Forwarded-Proto https;"

	      gitlab_rails['omniauth_enabled'] = true
	      gitlab_rails['omniauth_block_auto_created_users'] = false

	      oidc_yaml = ENV['GITLAB_OIDC_IDPS_YAML'].to_s
	      if oidc_yaml.strip.empty?
	        gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
	        gitlab_rails['omniauth_auto_link_user'] = ['openid_connect']
	        gitlab_rails['omniauth_providers'] = [
	          {
	            name: 'openid_connect',
	            label: ${jsonencode(local.gitlab_oidc_label)},
	            args: {
	              name: 'openid_connect',
	              strategy_class: 'OmniAuth::Strategies::OpenIDConnect',
	              scope: ${jsonencode(local.gitlab_oidc_scopes)},
	              response_type: 'code',
	              issuer: ${jsonencode(local.gitlab_oidc_issuer_url)},
	              discovery: true,
	              client_auth_method: 'basic',
	              uid_field: 'preferred_username',
	              client_options: {
	                identifier: ENV['GITLAB_OIDC_CLIENT_ID'],
	                secret: ENV['GITLAB_OIDC_CLIENT_SECRET'],
	                redirect_uri: 'https://gitlab.${local.hosted_zone_name_input}/users/auth/openid_connect/callback'
	              }
	            }
	          }
	        ]
	      else
	        begin
	          require 'yaml'
	          idps = YAML.safe_load(oidc_yaml) || {}
	        rescue => e
	          idps = {}
	        end

	        provider_names = []
	        providers = []

	        if idps.is_a?(Hash)
	          idps.each do |key, cfg|
	            next unless cfg.is_a?(Hash)
	            issuer = cfg['oidc_url'].to_s.strip
	            client_id = cfg['client_id'].to_s.strip
	            client_secret = cfg['secret'].to_s
	            next if issuer.empty? || client_id.empty? || client_secret.empty?

	            suffix = key.to_s.gsub(/[^0-9A-Za-z_]/, '_')
	            provider = "openid_connect_#{suffix}"
	            label = cfg['display_name'].to_s.strip
	            label = key.to_s if label.empty?
	            scope = cfg.dig('extra_params', 'scope').to_s.strip
	            scope = 'openid profile email' if scope.empty?

	            provider_names << provider
	            providers << {
	              name: provider,
	              label: label,
	              args: {
	                name: provider,
	                strategy_class: 'OmniAuth::Strategies::OpenIDConnect',
	                scope: scope.split(/\s+/),
	                response_type: 'code',
	                issuer: issuer,
	                discovery: true,
	                client_auth_method: 'basic',
	                uid_field: 'preferred_username',
	                client_options: {
	                  identifier: client_id,
	                  secret: client_secret,
	                  redirect_uri: "https://gitlab.${local.hosted_zone_name_input}/users/auth/#{provider}/callback"
	                }
	              }
	            }
	          end
	        end

	        if provider_names.empty?
	          gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
	          gitlab_rails['omniauth_auto_link_user'] = ['openid_connect']
	          gitlab_rails['omniauth_providers'] = [
	            {
	              name: 'openid_connect',
	              label: ${jsonencode(local.gitlab_oidc_label)},
	              args: {
	                name: 'openid_connect',
	                strategy_class: 'OmniAuth::Strategies::OpenIDConnect',
	                scope: ${jsonencode(local.gitlab_oidc_scopes)},
	                response_type: 'code',
	                issuer: ${jsonencode(local.gitlab_oidc_issuer_url)},
	                discovery: true,
	                client_auth_method: 'basic',
	                uid_field: 'preferred_username',
	                client_options: {
	                  identifier: ENV['GITLAB_OIDC_CLIENT_ID'],
	                  secret: ENV['GITLAB_OIDC_CLIENT_SECRET'],
	                  redirect_uri: 'https://gitlab.${local.hosted_zone_name_input}/users/auth/openid_connect/callback'
	                }
	              }
	            }
	          ]
	        else
	          gitlab_rails['omniauth_allow_single_sign_on'] = provider_names
	          gitlab_rails['omniauth_auto_link_user'] = provider_names
	          gitlab_rails['omniauth_providers'] = providers
	        end
	      end
		    EOT
  }, var.gitlab_oidc_idps_yaml != null ? { GITLAB_OIDC_IDPS_YAML = var.gitlab_oidc_idps_yaml } : {})
  default_environment_grafana_base = {
    GF_DATABASE_TYPE              = "postgres"
    GF_DATABASE_SSL_MODE          = "require"
    GF_I18N_DEFAULT_LANGUAGE      = "ja-JP"
    GF_I18N_DEFAULT_LOCALE        = "ja-JP"
    GF_SERVER_SERVE_FROM_SUB_PATH = tostring(local.grafana_serve_from_sub_path_effective)
  }
  default_environment_zulip = {
    SETTINGS_FLAVOR                = "production"
    SETTING_EXTERNAL_HOST          = local.zulip_host
    SETTING_EMAIL_HOST             = "email-smtp.${var.region}.amazonaws.com"
    SETTING_EMAIL_PORT             = "587"
    SETTING_EMAIL_USE_TLS          = "True"
    SETTING_EMAIL_USE_SSL          = "False"
    SETTING_NOREPLY_EMAIL_ADDRESS  = "noreply@${local.hosted_zone_name_input}"
    SETTING_ZULIP_ADMINISTRATOR    = local.zulip_admin_email_effective
    ZULIP_EXTERNAL_HOST            = local.zulip_host
    EXTERNAL_HOST                  = local.zulip_host
    ZULIP_ADMINISTRATOR            = local.zulip_admin_email_effective
    DISABLE_HTTPS                  = "true"
    SSL_CERTIFICATE_GENERATION     = "false"
    ZULIP_SETTING_TIME_ZONE        = "Asia/Tokyo"
    ZULIP_SETTING_DEFAULT_LANGUAGE = "ja"
    RABBITMQ_HOST                  = "127.0.0.1"
    SETTING_RABBITMQ_HOST          = "127.0.0.1"
    RABBITMQ_PORT                  = "5672"
    SETTING_RABBITMQ_PORT          = "5672"
    REDIS_HOST                     = "127.0.0.1"
    SETTING_REDIS_HOST             = "127.0.0.1"
    REDIS_PORT                     = "6379"
    SETTING_REDIS_PORT             = "6379"
    MEMCACHED_HOST                 = "127.0.0.1:11211"
    SETTING_MEMCACHED_LOCATION     = "127.0.0.1:11211"
    OPEN_REALM_CREATION            = "True"
  }
  default_environment_sulu_base = {
    APP_ENV                   = "prod"
    APP_SHARE_DIR             = var.sulu_share_dir
    SEAL_DSN                  = "loupe:///var/www/html/var/indexes"
    LOCK_DSN                  = "flock"
    REDIS_URL                 = "redis://127.0.0.1:6379"
    LOUPE_DSN                 = "loupe:///var/www/html/var/indexes"
    TZ                        = "Asia/Tokyo"
    SULU_ADMIN_EMAIL          = local.sulu_admin_email_effective
    SULU_KEYCLOAK_HOST        = local.keycloak_host
    SULU_SSO_DEFAULT_ROLE_KEY = var.sulu_sso_default_role_key
  }
  exastro_web_keycloak_environment = var.enable_exastro_keycloak ? {
    KEYCLOAK_ISSUER_URL   = local.exastro_web_oidc_issuer_url
    KEYCLOAK_AUTH_URL     = local.exastro_web_oidc_auth_url
    KEYCLOAK_TOKEN_URL    = local.exastro_web_oidc_token_url
    KEYCLOAK_USERINFO_URL = local.exastro_web_oidc_userinfo_url
  } : {}
  exastro_api_keycloak_environment = var.enable_exastro_keycloak ? {
    KEYCLOAK_ISSUER_URL   = local.exastro_api_oidc_issuer_url
    KEYCLOAK_AUTH_URL     = local.exastro_api_oidc_auth_url
    KEYCLOAK_TOKEN_URL    = local.exastro_api_oidc_token_url
    KEYCLOAK_USERINFO_URL = local.exastro_api_oidc_userinfo_url
  } : {}
  default_ssm_params_keycloak = {
    KC_DB_URL               = local.keycloak_db_url_parameter_name
    KC_DB_HOST              = local.keycloak_db_host_parameter_name
    KC_DB_PORT              = local.keycloak_db_port_parameter_name
    KC_DB_NAME              = local.keycloak_db_name_parameter_name
    KC_DB_USERNAME          = local.keycloak_db_username_parameter_name
    KC_DB_PASSWORD          = local.keycloak_db_password_parameter_name
    KEYCLOAK_ADMIN          = local.keycloak_admin_username_parameter_name
    KEYCLOAK_ADMIN_PASSWORD = local.keycloak_admin_password_parameter_name
  }
  default_ssm_params_odoo = {
    DB_HOST        = local.db_host_parameter_name
    DB_PORT        = local.db_port_parameter_name
    HOST           = local.db_host_parameter_name
    PORT           = local.db_port_parameter_name
    DB_USER        = local.odoo_db_username_parameter_name
    DB_PASSWORD    = local.odoo_db_password_parameter_name
    USER           = local.odoo_db_username_parameter_name
    PASSWORD       = local.odoo_db_password_parameter_name
    DB_NAME        = local.odoo_db_name_parameter_name
    ADMIN_PASSWORD = local.odoo_admin_password_parameter_name
  }
  default_ssm_params_pgadmin = {
    PGADMIN_DEFAULT_PASSWORD = local.pgadmin_default_password_parameter_name
  }
  default_ssm_params_gitlab = {
    GITLAB_DB_HOST     = local.gitlab_db_host_parameter_name
    GITLAB_DB_PORT     = local.gitlab_db_port_parameter_name
    GITLAB_DB_NAME     = local.gitlab_db_name_parameter_name
    GITLAB_DB_USER     = local.gitlab_db_username_parameter_name
    GITLAB_DB_PASSWORD = local.gitlab_db_password_parameter_name
  }
  default_ssm_params_grafana_common = {
    GF_SECURITY_ADMIN_USER     = local.grafana_admin_username_parameter_name
    GF_SECURITY_ADMIN_PASSWORD = local.grafana_admin_password_parameter_name
    GF_DATABASE_HOST           = local.grafana_db_host_parameter_name
    GF_DATABASE_PORT           = local.grafana_db_port_parameter_name
    GF_DATABASE_USER           = local.grafana_db_username_parameter_name
    GF_DATABASE_PASSWORD       = local.grafana_db_password_parameter_name
  }
  default_ssm_params_zulip_base = {
    DB_HOST                              = local.db_host_parameter_name
    DB_PORT                              = local.db_port_parameter_name
    DB_HOST_PORT                         = local.db_port_parameter_name
    DB_NAME                              = local.zulip_db_name_parameter_name
    DB_USER                              = local.zulip_db_username_parameter_name
    DB_PASSWORD                          = local.zulip_db_password_parameter_name
    SECRETS_postgres_password            = local.zulip_db_password_parameter_name
    RABBITMQ_USERNAME                    = local.zulip_mq_username_parameter_name
    SETTING_RABBITMQ_USER                = local.zulip_mq_username_parameter_name
    RABBITMQ_PASSWORD                    = local.zulip_mq_password_parameter_name
    SECRETS_rabbitmq_password            = local.zulip_mq_password_parameter_name
    SECRETS_redis_password               = local.zulip_redis_password_parameter_name
    SECRETS_rate_limiting_redis_password = local.zulip_redis_password_parameter_name
    SECRET_KEY                           = local.zulip_secret_key_parameter_name
    SECRETS_secret_key                   = local.zulip_secret_key_parameter_name
  }
  optional_smtp_params_keycloak = merge(
    local.keycloak_smtp_username_value != null ? { KC_SPI_EMAIL_SMTP_USER = local.keycloak_smtp_username_parameter_name } : {},
    local.keycloak_smtp_password_value != null ? { KC_SPI_EMAIL_SMTP_PASSWORD = local.keycloak_smtp_password_parameter_name } : {}
  )
  optional_smtp_params_zulip = merge(
    local.zulip_smtp_username_value != null ? { SETTING_EMAIL_HOST_USER = local.zulip_smtp_username_parameter_name } : {},
    local.zulip_smtp_password_value != null ? { SECRETS_email_password = local.zulip_smtp_password_parameter_name } : {}
  )
  optional_smtp_params_odoo = merge(
    local.odoo_smtp_username_value != null ? { SMTP_USER = local.odoo_smtp_username_parameter_name } : {},
    local.odoo_smtp_password_value != null ? { SMTP_PASSWORD = local.odoo_smtp_password_parameter_name } : {}
  )
  optional_smtp_params_gitlab = merge(
    local.gitlab_smtp_username_value != null ? { GITLAB_SMTP_USER = local.gitlab_smtp_username_parameter_name } : {},
    local.gitlab_smtp_password_value != null ? { GITLAB_SMTP_PASS = local.gitlab_smtp_password_parameter_name } : {}
  )
  optional_smtp_params_pgadmin = merge(
    local.pgadmin_smtp_username_value != null ? { PGADMIN_CONFIG_MAIL_USERNAME = local.pgadmin_smtp_username_parameter_name } : {},
    local.pgadmin_smtp_password_value != null ? { PGADMIN_CONFIG_MAIL_PASSWORD = local.pgadmin_smtp_password_parameter_name } : {}
  )
  optional_oidc_params_odoo = var.enable_odoo_keycloak && local.odoo_oidc_client_id_value != null && local.odoo_oidc_client_secret_value != null ? {
    ODOO_OIDC_CLIENT_ID     = local.odoo_oidc_client_id_parameter_name
    ODOO_OIDC_CLIENT_SECRET = local.odoo_oidc_client_secret_parameter_name
  } : {}
  optional_oidc_params_gitlab = var.enable_gitlab_keycloak && local.gitlab_oidc_client_id_value != null && local.gitlab_oidc_client_secret_value != null ? {
    GITLAB_OIDC_CLIENT_ID     = local.gitlab_oidc_client_id_parameter_name
    GITLAB_OIDC_CLIENT_SECRET = local.gitlab_oidc_client_secret_parameter_name
  } : {}
  optional_oidc_params_pgadmin = var.enable_pgadmin_keycloak && local.pgadmin_oidc_client_id_value != null && local.pgadmin_oidc_client_secret_value != null ? {
    PGADMIN_OIDC_CLIENT_ID     = local.pgadmin_oidc_client_id_parameter_name
    PGADMIN_OIDC_CLIENT_SECRET = local.pgadmin_oidc_client_secret_parameter_name
  } : {}
}

resource "aws_cloudwatch_log_group" "ecs" {
  for_each = toset(local.enabled_services)

  name              = "/aws/ecs/${lookup(local.ecs_service_log_group_realm_by_service, each.key, local.ecs_default_realm)}/${local.name_prefix}-${each.key}"
  retention_in_days = var.ecs_logs_retention_days

  tags = merge(local.tags, {
    realm = lookup(local.ecs_service_log_group_realm_by_service, each.key, local.ecs_default_realm)
    Name  = "${local.name_prefix}-${each.key}-logs"
  })
}

locals {
  n8n_db_ssm_params_effective = var.n8n_db_ssm_params != null ? {
    for k, v in var.n8n_db_ssm_params : k => v if k != "DB_NAME" && k != "DB_POSTGRESDB_DATABASE"
  } : {}
  ssm_param_arns_n8n = {
    for k, v in merge(
      local.default_ssm_params_n8n,
      local.n8n_db_ssm_params_effective,
      local.optional_smtp_params_n8n,
      local.optional_zulip_bot_tokens_params_n8n,
      local.optional_service_control_params_n8n
    ) :
    k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}")
  }
  ssm_param_arns_exastro_web = { for k, v in merge(local.default_ssm_params_exastro, var.exastro_web_server_ssm_params) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  ssm_param_arns_exastro_api = { for k, v in merge(local.default_ssm_params_exastro, var.exastro_api_admin_ssm_params) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  ssm_param_arns_pgadmin     = { for k, v in merge(local.default_ssm_params_pgadmin, var.pgadmin_ssm_params, local.optional_smtp_params_pgadmin, local.optional_oidc_params_pgadmin) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  ssm_param_arns_keycloak    = { for k, v in merge(local.default_ssm_params_keycloak, var.keycloak_db_ssm_params, var.keycloak_ssm_params, local.optional_smtp_params_keycloak) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  ssm_param_arns_odoo        = { for k, v in merge(local.default_ssm_params_odoo, var.odoo_ssm_params, local.optional_smtp_params_odoo, local.optional_oidc_params_odoo) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  ssm_param_arns_gitlab      = { for k, v in merge(local.default_ssm_params_gitlab, var.gitlab_db_ssm_params, var.gitlab_ssm_params, local.optional_smtp_params_gitlab, local.optional_oidc_params_gitlab) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  default_ssm_params_gitlab_runner = local.gitlab_runner_token_write_enabled ? {
    GITLAB_RUNNER_TOKEN = local.gitlab_runner_token_parameter_name
  } : {}
  ssm_param_arns_gitlab_runner = {
    for k, v in merge(local.default_ssm_params_gitlab_runner, var.gitlab_runner_ssm_params) :
    k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}")
  }
  grafana_db_ssm_params_effective = var.grafana_db_ssm_params != null ? {
    for k, v in var.grafana_db_ssm_params : k => v if k != "GF_DATABASE_NAME"
  } : {}
  grafana_ssm_params_effective = var.grafana_ssm_params != null ? var.grafana_ssm_params : {}
  ssm_param_arns_grafana_common = {
    for k, v in merge(local.default_ssm_params_grafana_common, local.grafana_db_ssm_params_effective, local.grafana_ssm_params_effective) :
    k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}")
  }
  grafana_oidc_param_arns_by_realm = var.enable_grafana_keycloak ? {
    for realm in local.grafana_realms :
    realm => merge(
      contains(keys(local.grafana_oidc_client_id_by_realm_effective), realm) ? {
        GF_AUTH_GENERIC_OAUTH_CLIENT_ID = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(local.grafana_oidc_client_id_parameter_names_by_realm[realm], "/") ? local.grafana_oidc_client_id_parameter_names_by_realm[realm] : "/${local.grafana_oidc_client_id_parameter_names_by_realm[realm]}"}"
      } : {},
      contains(keys(local.grafana_oidc_client_secret_by_realm_effective), realm) ? {
        GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(local.grafana_oidc_client_secret_parameter_names_by_realm[realm], "/") ? local.grafana_oidc_client_secret_parameter_names_by_realm[realm] : "/${local.grafana_oidc_client_secret_parameter_names_by_realm[realm]}"}"
      } : {}
    )
  } : {}
  ssm_param_arns_zulip = { for k, v in merge(local.default_ssm_params_zulip_base, var.zulip_db_ssm_params, var.zulip_ssm_params, local.optional_smtp_params_zulip) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  sulu_ssm_core_params = {
    APP_SECRET         = local.sulu_app_secret_parameter_name
    DATABASE_URL       = local.sulu_database_url_parameter_name
    MAILER_DSN         = local.sulu_mailer_dsn_parameter_name
    N8N_OBSERVER_TOKEN = local.observer_token_parameter_name
  }
  sulu_ssm_oidc_params = var.enable_sulu_keycloak ? {
    SULU_SSO_CLIENT_ID     = local.sulu_oidc_client_id_parameter_name
    SULU_SSO_CLIENT_SECRET = local.sulu_oidc_client_secret_parameter_name
  } : {}
  ssm_param_arns_sulu = { for k, v in merge(local.sulu_ssm_core_params, local.sulu_ssm_oidc_params) : k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}") }
  ssm_param_arns_exastro_web_oidc = var.enable_exastro_keycloak ? { for k, v in {
    KEYCLOAK_CLIENT_ID     = local.exastro_web_oidc_client_id_parameter_name
    KEYCLOAK_CLIENT_SECRET = local.exastro_web_oidc_client_secret_parameter_name
  } : k => "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}" } : {}
  ssm_param_arns_exastro_api_oidc = var.enable_exastro_keycloak ? { for k, v in {
    KEYCLOAK_CLIENT_ID     = local.exastro_api_oidc_client_id_parameter_name
    KEYCLOAK_CLIENT_SECRET = local.exastro_api_oidc_client_secret_parameter_name
  } : k => "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}" } : {}
  db_ssm_param_arns = { for k, v in {
    DB_ADMIN_USER     = local.db_username_parameter_name
    DB_ADMIN_PASSWORD = local.db_password_parameter_name
    DB_HOST           = local.db_host_parameter_name
    DB_PORT           = local.db_port_parameter_name
  } : k => "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}" }
}

locals {
  pgadmin_secret_names = toset(concat(
    [for s in var.pgadmin_secrets : s.name],
    keys(local.ssm_param_arns_pgadmin)
  ))

  # Auto-quote PGADMIN_CONFIG_* plain strings so pgAdmin's config_distro.py stays valid Python.
  pgadmin_environment_effective = {
    for k, v in merge(local.default_environment_pgadmin, coalesce(var.pgadmin_environment, {})) :
    k => (
      startswith(k, "PGADMIN_CONFIG_") &&
      !can(regex("^\\s*['\"\\[{]", v)) &&
      !can(regex("^(True|False|None)$", v)) &&
      !can(regex("^[-+]?\\d+(\\.\\d+)?$", v))
      ? jsonencode(v) : v
    ) if !contains(local.pgadmin_secret_names, k)
  }

}

locals {
  gitlab_runner_url_effective = coalesce(
    var.gitlab_runner_url != null && trimspace(var.gitlab_runner_url) != "" ? trimspace(var.gitlab_runner_url) : null,
    var.create_gitlab ? "https://${local.gitlab_host}" : null
  )
  gitlab_runner_name_effective = "${local.name_prefix}-gitlab-runner"
  gitlab_runner_tags_csv       = join(",", var.gitlab_runner_tags)

  gitlab_runner_secret_names = toset(concat(
    [for s in var.gitlab_runner_secrets : s.name],
    keys(local.ssm_param_arns_gitlab_runner)
  ))

  default_environment_gitlab_runner = {
    GITLAB_RUNNER_URL            = coalesce(local.gitlab_runner_url_effective, "")
    GITLAB_RUNNER_NAME           = local.gitlab_runner_name_effective
    GITLAB_RUNNER_CONCURRENT     = tostring(var.gitlab_runner_concurrent)
    GITLAB_RUNNER_CHECK_INTERVAL = tostring(var.gitlab_runner_check_interval)
    GITLAB_RUNNER_BUILDS_DIR     = var.gitlab_runner_builds_dir
    GITLAB_RUNNER_CACHE_DIR      = var.gitlab_runner_cache_dir
    GITLAB_RUNNER_TAG_LIST       = local.gitlab_runner_tags_csv
    GITLAB_RUNNER_RUN_UNTAGGED   = var.gitlab_runner_run_untagged ? "true" : "false"
  }

  gitlab_runner_environment_effective = {
    for k, v in merge(local.default_environment_gitlab_runner, coalesce(var.gitlab_runner_environment, {})) :
    k => v if !contains(local.gitlab_runner_secret_names, k)
  }
}

locals {
  odoo_var_secrets_map          = { for s in var.odoo_secrets : s.name => (can(regex("^arn:aws:ssm", s.valueFrom)) ? s.valueFrom : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(s.valueFrom, "/") ? s.valueFrom : "/${s.valueFrom}"}") }
  gitlab_var_secrets_map        = { for s in var.gitlab_secrets : s.name => (can(regex("^arn:aws:ssm", s.valueFrom)) ? s.valueFrom : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(s.valueFrom, "/") ? s.valueFrom : "/${s.valueFrom}"}") }
  gitlab_runner_var_secrets_map = { for s in var.gitlab_runner_secrets : s.name => (can(regex("^arn:aws:ssm", s.valueFrom)) ? s.valueFrom : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(s.valueFrom, "/") ? s.valueFrom : "/${s.valueFrom}"}") }
  grafana_var_secrets_map       = { for s in var.grafana_secrets : s.name => (can(regex("^arn:aws:ssm", s.valueFrom)) ? s.valueFrom : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(s.valueFrom, "/") ? s.valueFrom : "/${s.valueFrom}"}") }
  pgadmin_var_secrets_map       = { for s in var.pgadmin_secrets : s.name => (can(regex("^arn:aws:ssm", s.valueFrom)) ? s.valueFrom : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(s.valueFrom, "/") ? s.valueFrom : "/${s.valueFrom}"}") }

  odoo_secrets_effective = [
    for name, value in merge(local.odoo_var_secrets_map, local.ssm_param_arns_odoo) : {
      name      = name
      valueFrom = value
    }
  ]
  gitlab_secrets_effective = [
    for name, value in merge(local.gitlab_var_secrets_map, local.ssm_param_arns_gitlab) : {
      name      = name
      valueFrom = value
    }
  ]
  gitlab_runner_secrets_effective = [
    for name, value in merge(local.gitlab_runner_var_secrets_map, local.ssm_param_arns_gitlab_runner) : {
      name      = name
      valueFrom = value
    }
  ]
  grafana_common_secrets_effective = [
    for name, value in merge(local.grafana_var_secrets_map, local.ssm_param_arns_grafana_common) : {
      name      = name
      valueFrom = value
    }
  ]
  pgadmin_secrets_effective = [
    for name, value in merge(local.pgadmin_var_secrets_map, local.ssm_param_arns_pgadmin) : {
      name      = name
      valueFrom = value
    }
  ]
}

locals {
  gitlab_webhook_secret_param_arns_by_realm = {
    for realm, name in local.gitlab_webhook_secret_parameter_names_by_realm :
    realm => "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(name, "/") ? name : "/${name}"}"
  }
  n8n_has_global_gitlab_webhook_secret = contains(keys(local.ssm_param_arns_n8n), "GITLAB_WEBHOOK_SECRET")
  n8n_has_global_gitlab_token          = contains(keys(local.ssm_param_arns_n8n), "GITLAB_TOKEN")
  gitlab_token_param_arns_by_realm = {
    for realm in local.n8n_realms :
    realm => "arn:aws:ssm:${var.region}:${local.account_id}:parameter/${local.name_prefix}/n8n/gitlab/token/${realm}"
  }
  n8n_extra_ssm_param_arns_by_realm = {
    for realm in local.n8n_realms :
    realm => {
      for k, v in lookup(local.n8n_ssm_params_combined_by_realm, realm, tomap({})) :
      k => (can(regex("^arn:aws:ssm", v)) ? v : "arn:aws:ssm:${var.region}:${local.account_id}:parameter${startswith(v, "/") ? v : "/${v}"}")
    }
  }
  n8n_gitlab_webhook_secret_arns_by_realm = {
    for realm in local.n8n_realms :
    realm => (
      local.n8n_has_global_gitlab_webhook_secret ? {} :
      contains(keys(local.gitlab_webhook_secret_param_arns_by_realm), realm)
      ? { GITLAB_WEBHOOK_SECRET = local.gitlab_webhook_secret_param_arns_by_realm[realm] }
      : {}
    )
  }
  n8n_gitlab_token_arns_by_realm = {
    for realm in local.n8n_realms :
    realm => (
      local.n8n_has_global_gitlab_token ? {} :
      contains(keys(local.gitlab_token_param_arns_by_realm), realm)
      ? { GITLAB_TOKEN = local.gitlab_token_param_arns_by_realm[realm] }
      : {}
    )
  }
  n8n_ssm_param_arns_by_realm = {
    for realm in local.n8n_realms :
    realm => merge(
      local.n8n_extra_ssm_param_arns_by_realm[realm],
      local.n8n_gitlab_webhook_secret_arns_by_realm[realm],
      local.n8n_gitlab_token_arns_by_realm[realm]
    )
  }
}

locals {
  ecs_base_container = {
    cpu       = 0
    memory    = null
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = ""
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }
}

resource "aws_ecs_task_definition" "n8n" {
  count = var.create_ecs && var.create_n8n ? 1 : 0

  family                   = "${local.name_prefix}-n8n"
  cpu                      = coalesce(var.n8n_task_cpu, var.ecs_task_cpu)
  memory                   = coalesce(var.n8n_task_memory, var.ecs_task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.n8n_has_efs_effective ? [1] : []
    content {
      name = "n8n-data"
      efs_volume_configuration {
        file_system_id     = local.n8n_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    local.n8n_has_efs_effective ? [
      merge(local.ecs_base_container, {
        name       = "n8n-fs-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            mkdir -p "${var.n8n_filesystem_path}"
            mkdir -p "${var.n8n_filesystem_path}/qdrant"
            if [ "${local.n8n_use_realm_suffix}" = "true" ]; then
              for realm in ${local.n8n_realms_csv}; do
                realm_path="${var.n8n_filesystem_path}/$${realm}"
                qdrant_path="${var.n8n_filesystem_path}/qdrant/$${realm}"
                mkdir -p "$${realm_path}"
                chown -R 1000:1000 "$${realm_path}"
                mkdir -p "$${qdrant_path}"
                chown -R 1000:1000 "$${qdrant_path}"
              done
            else
              chown -R 1000:1000 "${var.n8n_filesystem_path}"
              for realm in ${local.n8n_realms_csv}; do
                qdrant_path="${var.n8n_filesystem_path}/qdrant/$${realm}"
                mkdir -p "$${qdrant_path}"
                chown -R 1000:1000 "$${qdrant_path}"
              done
            fi
          EOT
        ]
        mountPoints = [
          {
            sourceVolume  = "n8n-data"
            containerPath = var.n8n_filesystem_path
            readOnly      = false
          }
        ]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "n8n--n8n-fs-init", aws_cloudwatch_log_group.ecs["n8n"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name       = "n8n-db-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            echo "Installing PostgreSQL client (15.x) to match RDS 15.x..."
            apk add --no-cache postgresql15-client >/dev/null

            db_host="$${DB_HOST:-}"
            db_port="$${DB_PORT:-5432}"
            db_user="$${DB_USER:-}"
            db_pass="$${DB_PASSWORD:-}"
            base_db_name="${var.n8n_db_name}"
            use_realm_suffix="${local.n8n_use_realm_suffix}"

            if [ -z "$${db_host}" ] || [ -z "$${db_user}" ] || [ -z "$${db_pass}" ] || [ -z "$${base_db_name}" ]; then
              echo "Database variables are incomplete."
              exit 1
            fi

            export PGPASSWORD="$${db_pass}"

            echo "Waiting for PostgreSQL to become available..."
            until pg_isready -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" >/dev/null 2>&1; do
              sleep 2
            done

            role_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -Atc "SELECT 1 FROM pg_roles WHERE rolname = '$${db_user}'" || true)"
            if [ "$${role_exists}" != "1" ]; then
              echo "Creating role $${db_user}..."
              psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -c "CREATE ROLE \"$${db_user}\" WITH LOGIN PASSWORD '$${db_pass}';" || true
            fi

            for realm in ${local.n8n_realms_csv}; do
              if [ "$${use_realm_suffix}" = "true" ]; then
                db_name="$${base_db_name}_$${realm}"
                schema_name="$(printf '%s' "$${realm}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_' '_')"
              else
                db_name="$${base_db_name}"
                schema_name="public"
              fi

              db_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$${db_name}'" || true)"
              if [ "$${db_exists}" != "1" ]; then
                echo "Creating database $${db_name}..."
                psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -c "CREATE DATABASE \"$${db_name}\" OWNER \"$${db_user}\";"
              else
                echo "Database $${db_name} already exists."
              fi

              echo "Ensuring schema $${schema_name} exists in $${db_name}..."
              psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d "$${db_name}" -c "CREATE SCHEMA IF NOT EXISTS \"$${schema_name}\" AUTHORIZATION \"$${db_user}\";"
            done
          EOT
        ]
        secrets = [for k, v in local.ssm_param_arns_n8n : { name = k, valueFrom = v }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "n8n--n8n-db-init", aws_cloudwatch_log_group.ecs["n8n"].name)
          })
        })
      })
    ],
    (local.n8n_qdrant_enabled && local.n8n_has_efs_effective) ? [
      for realm in local.n8n_realms : merge(local.ecs_base_container, {
        name  = "qdrant-${realm}"
        image = local.qdrant_image
        portMappings = [
          {
            containerPort = local.qdrant_realm_http_ports[realm]
            hostPort      = local.qdrant_realm_http_ports[realm]
            protocol      = "tcp"
          },
          {
            containerPort = local.qdrant_realm_grpc_ports[realm]
            hostPort      = local.qdrant_realm_grpc_ports[realm]
            protocol      = "tcp"
          }
        ]
        environment = [
          { name = "QDRANT__SERVICE__HTTP_PORT", value = tostring(local.qdrant_realm_http_ports[realm]) },
          { name = "QDRANT__SERVICE__GRPC_PORT", value = tostring(local.qdrant_realm_grpc_ports[realm]) },
          { name = "QDRANT__STORAGE__STORAGE_PATH", value = local.qdrant_realm_paths[realm] }
        ]
        mountPoints = local.n8n_has_efs_effective ? [
          {
            sourceVolume  = "n8n-data"
            containerPath = var.n8n_filesystem_path
            readOnly      = false
          }
        ] : []
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "n8n--qdrant-${realm}", aws_cloudwatch_log_group.ecs["n8n"].name)
          })
        })
      })
    ] : [],
    local.xray_n8n_enabled ? [
      merge(local.xray_daemon_container_common, {
        name = "xray-daemon-${local.ecs_n8n_shared_realm}"
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "n8n--xray-daemon-${local.ecs_n8n_shared_realm}", aws_cloudwatch_log_group.ecs["n8n"].name)
          })
        })
      })
    ] : [],
    [for realm in local.n8n_realms : merge(local.ecs_base_container, {
      name  = "n8n-${realm}"
      image = local.ecr_uri_n8n
      user  = "1000:1000"
      portMappings = [{
        containerPort = local.n8n_realm_ports[realm]
        hostPort      = local.n8n_realm_ports[realm]
        protocol      = "tcp"
      }]
      environment = [
        for k, v in merge(
          local.default_environment_n8n_base,
          lookup(local.n8n_grafana_event_inbox_env_by_realm, realm, {}),
          {
            N8N_HOST                = local.n8n_realm_hosts[realm]
            N8N_PORT                = tostring(local.n8n_realm_ports[realm])
            N8N_EDITOR_BASE_URL     = "https://${local.n8n_realm_hosts[realm]}/"
            N8N_PUBLIC_API_BASE_URL = "https://${local.n8n_realm_hosts[realm]}/"
            N8N_USER_FOLDER         = local.n8n_realm_paths[realm]
            N8N_OBSERVER_REALM      = realm
            N8N_OBSERVER_MAX_CHARS  = "4000"
          },
          var.create_sulu ? {
            N8N_OBSERVER_URL = "https://${local.sulu_realm_hosts[realm]}/api/n8n/observer/events"
          } : {},
          local.n8n_gitlab_token_env_by_realm[realm],
          (local.n8n_qdrant_enabled && local.n8n_has_efs_effective) ? {
            QDRANT_URL      = "http://127.0.0.1:${local.qdrant_realm_http_ports[realm]}"
            QDRANT_GRPC_URL = "http://127.0.0.1:${local.qdrant_realm_grpc_ports[realm]}"
          } : {},
          local.xray_n8n_enabled ? local.xray_daemon_env : {},
          local.n8n_use_realm_suffix ? {
            DB_NAME                = local.n8n_realm_db_names[realm]
            DB_POSTGRESDB_DATABASE = local.n8n_realm_db_names[realm]
            DB_POSTGRESDB_SCHEMA   = local.n8n_realm_db_schemas[realm]
          } : {},
          lookup(local.aiops_agent_environment_by_realm, realm, {})
        ) : { name = k, value = v }
      ]
      secrets = concat(
        var.n8n_secrets,
        [for k, v in local.ssm_param_arns_n8n : { name = k, valueFrom = v }],
        [for k, v in lookup(local.n8n_ssm_param_arns_by_realm, realm, {}) : { name = k, valueFrom = v }]
      )
      entryPoint = [var.n8n_shell_path, "-c"]
      command = [
        <<-EOT
            set -eu

            if ! command -v psql >/dev/null 2>&1; then
              echo "psql client not found in image; aborting startup."
              exit 1
            fi

            db_host="$${DB_HOST:-}"
            db_port="$${DB_PORT:-5432}"
            db_user="$${DB_USER:-}"
            db_name="$${DB_NAME:-}"

            if [ -z "$${db_host}" ] || [ -z "$${db_user}" ] || [ -z "$${db_name}" ] || [ -z "$${DB_PASSWORD:-}" ]; then
              echo "Database connection variables are not fully defined; aborting startup."
              exit 1
            fi

            export PGPASSWORD="$${DB_PASSWORD}"

            echo "Waiting for PostgreSQL to become available..."
            until pg_isready -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" >/dev/null 2>&1; do
              sleep 3
            done

            n8n_bin="$(command -v n8n || true)"
            if [ -z "$${n8n_bin}" ]; then
              echo "n8n binary not found in PATH; aborting."
              exit 1
            fi

            exec "$${n8n_bin}" start
          EOT
      ]
      mountPoints = local.n8n_has_efs_effective ? [
        {
          sourceVolume  = "n8n-data"
          containerPath = var.n8n_filesystem_path
          readOnly      = false
        }
      ] : []
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "n8n--n8n-${realm}", aws_cloudwatch_log_group.ecs["n8n"].name)
        })
      })
      dependsOn = concat(
        local.n8n_has_efs_effective ? [
          {
            containerName = "n8n-fs-init"
            condition     = "COMPLETE"
          }
        ] : [],
        (local.n8n_qdrant_enabled && local.n8n_has_efs_effective) ? [
          {
            containerName = "qdrant-${realm}"
            condition     = "START"
          }
        ] : [],
        [
          {
            containerName = "n8n-db-init"
            condition     = "COMPLETE"
          }
        ]
      )
      })
    ]
  ))

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-n8n-td" })
}

resource "aws_ecs_task_definition" "exastro" {
  count = var.create_ecs && local.exastro_service_enabled ? 1 : 0

  family                   = "${local.name_prefix}-exastro"
  cpu                      = local.exastro_task_cpu
  memory                   = local.exastro_task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = [1]
    content {
      name = "exastro-storage"
      dynamic "efs_volume_configuration" {
        for_each = local.exastro_efs_id != null ? [1] : []
        content {
          file_system_id     = local.exastro_efs_id
          root_directory     = "/"
          transit_encryption = "ENABLED"
          authorization_config {
            access_point_id = null
            iam             = "DISABLED"
          }
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    local.exastro_efs_id != null ? [
      merge(local.ecs_base_container, {
        name       = "exastro-fs-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            mkdir -p "${var.exastro_filesystem_path}"
            chown -R 1000:1000 "${var.exastro_filesystem_path}"
          EOT
        ]
        mountPoints = [{
          sourceVolume  = "exastro-storage"
          containerPath = var.exastro_filesystem_path
          readOnly      = false
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "exastro--exastro-fs-init", aws_cloudwatch_log_group.ecs["exastro"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name  = "exastro-web"
        image = local.ecr_uri_exastro_web
        user  = "1000:1000"
        portMappings = [{
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }]
        environment = [for k, v in merge(var.exastro_web_server_environment, local.exastro_web_keycloak_environment) : { name = k, value = v }]
        secrets = concat(
          var.exastro_web_server_secrets,
          [for k, v in local.ssm_param_arns_exastro_web : { name = k, valueFrom = v }],
          var.enable_exastro_keycloak ? [for k, v in local.ssm_param_arns_exastro_web_oidc : { name = k, valueFrom = v }] : []
        )
        mountPoints = local.exastro_efs_id != null ? [
          {
            sourceVolume  = "exastro-storage"
            containerPath = var.exastro_filesystem_path
            readOnly      = false
          }
        ] : []
        dependsOn = local.exastro_efs_id != null ? [
          {
            containerName = "exastro-fs-init"
            condition     = "COMPLETE"
          }
        ] : []
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "exastro--exastro-web", aws_cloudwatch_log_group.ecs["exastro"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name  = "exastro-api"
        image = local.ecr_uri_exastro_api
        user  = "1000:1000"
        portMappings = [{
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }]
        environment = [for k, v in merge(var.exastro_api_admin_environment, local.exastro_api_keycloak_environment) : { name = k, value = v }]
        secrets = concat(
          var.exastro_api_admin_secrets,
          [for k, v in local.ssm_param_arns_exastro_api : { name = k, valueFrom = v }],
          var.enable_exastro_keycloak ? [for k, v in local.ssm_param_arns_exastro_api_oidc : { name = k, valueFrom = v }] : []
        )
        mountPoints = local.exastro_efs_id != null ? [
          {
            sourceVolume  = "exastro-storage"
            containerPath = var.exastro_filesystem_path
            readOnly      = false
          }
        ] : []
        dependsOn = local.exastro_efs_id != null ? [
          {
            containerName = "exastro-fs-init"
            condition     = "COMPLETE"
          }
        ] : []
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "exastro--exastro-api", aws_cloudwatch_log_group.ecs["exastro"].name)
          })
        })
      })
    ]
  ))

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-exastro-td" })
}

resource "aws_ecs_task_definition" "sulu" {
  for_each = var.create_ecs && var.create_sulu ? local.sulu_realm_hosts : {}

  family                   = "${local.name_prefix}-sulu-${each.key}"
  cpu                      = coalesce(var.sulu_task_cpu, var.ecs_task_cpu)
  memory                   = coalesce(var.sulu_task_memory, var.ecs_task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.sulu_efs_id != null ? [1] : []
    content {
      name                = "sulu-share"
      configure_at_launch = false
      efs_volume_configuration {
        file_system_id     = local.sulu_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    local.sulu_efs_id != null ? [
      merge(local.ecs_base_container, {
        name       = "sulu-fs-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu

            realm="${each.key}"
            primary_realm="${local.sulu_primary_realm}"
            realm_dir="${var.sulu_filesystem_path}/$${realm}"
            mkdir -p "$${realm_dir}/media" "$${realm_dir}/loupe" "$${realm_dir}/locks"
            chown -R 33:33 "$${realm_dir}"

            if [ -n "$${primary_realm}" ] && [ "$${realm}" = "$${primary_realm}" ]; then
              legacy_media="${var.sulu_filesystem_path}/media"
              legacy_loupe="${var.sulu_filesystem_path}/loupe"
              legacy_locks="${var.sulu_filesystem_path}/locks"
              primary_dir="${var.sulu_filesystem_path}/$${primary_realm}"
              primary_media="$${primary_dir}/media"
              primary_loupe="$${primary_dir}/loupe"
              primary_locks="$${primary_dir}/locks"

              if [ -d "$${legacy_media}" ] && [ -z "$(ls -A "$${primary_media}" 2>/dev/null)" ]; then
                mv "$${legacy_media}"/* "$${primary_media}"/ 2>/dev/null || true
              fi
              if [ -d "$${legacy_loupe}" ] && [ -z "$(ls -A "$${primary_loupe}" 2>/dev/null)" ]; then
                mv "$${legacy_loupe}"/* "$${primary_loupe}"/ 2>/dev/null || true
              fi
              if [ -d "$${legacy_locks}" ] && [ -z "$(ls -A "$${primary_locks}" 2>/dev/null)" ]; then
                mv "$${legacy_locks}"/* "$${primary_locks}"/ 2>/dev/null || true
              fi
            fi
          EOT
        ]
        mountPoints = [{
          sourceVolume  = "sulu-share"
          containerPath = var.sulu_filesystem_path
          readOnly      = false
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "sulu--sulu-fs-init", aws_cloudwatch_log_group.ecs["sulu"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name      = "redis"
        image     = local.redis_image
        essential = true
        portMappings = [{
          containerPort = 6379
          hostPort      = 6379
          protocol      = "tcp"
        }]
        healthCheck = {
          command     = ["CMD-SHELL", "redis-cli ping | grep PONG"]
          interval    = 10
          timeout     = 5
          retries     = 5
          startPeriod = 10
        }
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group"         = lookup(local.ecs_log_group_name_by_container, "sulu--redis", aws_cloudwatch_log_group.ecs["sulu"].name)
            "awslogs-stream-prefix" = "redis"
          })
        })
      })
    ],
    [for realm in [each.key] : merge(local.ecs_base_container, {
      name      = "loupe-indexer-${realm}"
      image     = local.alpine_image_3_20
      essential = false
      command   = ["sh", "-c", "sleep infinity"]
      mountPoints = local.sulu_efs_id != null ? [
        {
          sourceVolume  = "sulu-share"
          containerPath = var.sulu_filesystem_path
          readOnly      = false
        }
      ] : []
      dependsOn = local.sulu_efs_id != null ? [
        {
          containerName = "sulu-fs-init"
          condition     = "COMPLETE"
        }
      ] : []
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group"         = lookup(local.ecs_log_group_name_by_container, "sulu--loupe-indexer-${realm}", aws_cloudwatch_log_group.ecs["sulu"].name)
          "awslogs-stream-prefix" = "loupe"
        })
      })
    })],
    [for realm in [each.key] : merge(local.ecs_base_container, {
      name       = "init-db-${realm}"
      image      = local.ecr_uri_sulu
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
          set -eu

          realm="$${SULU_REALM:-}"
          realm_root="${var.sulu_filesystem_path}"
          if [ -n "$${realm}" ]; then
            realm_root="${var.sulu_filesystem_path}/$${realm}"
          fi

          mkdir -p "$${realm_root}/media" "$${realm_root}/loupe" "$${realm_root}/locks"

          if [ -e "${var.sulu_share_dir}" ] && [ ! -L "${var.sulu_share_dir}" ]; then
            rm -rf "${var.sulu_share_dir}"
          fi
          if [ -e "/var/www/html/var/indexes" ] && [ ! -L "/var/www/html/var/indexes" ]; then
            rm -rf "/var/www/html/var/indexes"
          fi

          ln -snf "$${realm_root}/media" "${var.sulu_share_dir}"
          ln -snf "$${realm_root}/loupe" "/var/www/html/var/indexes"

          # Symfony resolves %...% in env var values as parameters.
          # DATABASE_URL includes %-encoded credentials, so escape % as %% for Symfony commands.
          database_url_raw="$${DATABASE_URL:-}"
          if [ -n "$${SULU_DB_SCHEMA:-}" ] && [ -n "$${database_url_raw}" ]; then
            case "$${database_url_raw}" in
              *\?*)
                database_url_raw="$${database_url_raw}&options=--search_path%3D$${SULU_DB_SCHEMA}"
                ;;
              *)
                database_url_raw="$${database_url_raw}?options=--search_path%3D$${SULU_DB_SCHEMA}"
                ;;
            esac
          fi

          database_url_escaped="$${database_url_raw}"
          if [ -n "$${database_url_escaped}" ]; then
            database_url_escaped="$(printf '%s' "$${database_url_escaped}" | sed 's/%/%%/g')"
          fi

          if [ "$${SULU_INIT_DEBUG:-}" = "1" ] || [ "$${SULU_INIT_DEBUG:-}" = "true" ]; then
            set -x
          fi

          REALM="$${SULU_REALM:-}"
          EFS_ROOT="/efs"
          if [ -n "$${REALM}" ]; then
            EFS_ROOT="/efs/$${REALM}"
          fi
          LOCK_DIR="$${EFS_ROOT}/locks"
          LOCK_FILE="$${LOCK_DIR}/db-init.lock"
          SENTINEL="$${LOCK_DIR}/db-init.done"
          SCRIPT_DIR="/var/www/html/docker"

          mkdir -p "$${LOCK_DIR}" "$${EFS_ROOT}/media" "$${EFS_ROOT}/loupe"
          chown -R www-data:www-data "$${EFS_ROOT}" || true

          DOWNLOAD_LANGUAGES="$${SULU_ADMIN_DOWNLOAD_LANGUAGES:-ja}"
          DOWNLOAD_LANGUAGES="$(printf '%s' "$${DOWNLOAD_LANGUAGES}" | tr ',' ' ' | awk '{$1=$1};1')"
          DOWNLOAD_FORCE="$${SULU_ADMIN_DOWNLOAD_FORCE:-0}"

          PAGES_JSON="$${SULU_PAGES_JSON_PATH:-/var/www/html/content/pages.json}"
          PAGES_BIN="$${SULU_PAGES_BIN_PATH:-/var/www/html/bin/replace_sulu_pages.php}"
          PAGES_RETRIES="$${SULU_PAGES_SYNC_RETRIES:-5}"
          PAGES_RETRY_SLEEP_SECONDS="$${SULU_PAGES_SYNC_RETRY_SLEEP_SECONDS:-5}"

          ensure_database_exists() {
            if [ -z "$${database_url_raw}" ]; then
              echo "[init-db] DATABASE_URL is missing; cannot ensure database exists."
              return 1
            fi

            set +eu
            DATABASE_URL="$${database_url_raw}" php "$${SCRIPT_DIR}/init-db.php"
            status=$?
            set -eu
            return $${status}
          }

          sentinel_exists="0"
          if [ -f "$${SENTINEL}" ]; then
            sentinel_exists="1"
            echo "[init-db] sentinel exists; skipping heavy init."
          fi

          echo "[init-db] ensuring database exists if missing..."
          ensure_database_exists || true

          echo "[init-db] waiting for database..."
          until DATABASE_URL="$${database_url_escaped}" php bin/console doctrine:query:sql "SELECT 1" >/dev/null 2>&1; do
            echo "[init-db] database not reachable yet; creating if missing and retrying in 3s..."
            ensure_database_exists || true
            sleep 3
          done

          exec 9>"$${LOCK_FILE}"
          flock 9

          if [ -f "$${SENTINEL}" ]; then
            sentinel_exists="1"
          fi

          if [ "$${sentinel_exists}" != "1" ]; then
            if [ -n "$${SULU_DB_SCHEMA:-}" ]; then
              echo "[init-db] ensuring schema $${SULU_DB_SCHEMA} exists..."
              DATABASE_URL="$${database_url_escaped}" php bin/console doctrine:query:sql "CREATE SCHEMA IF NOT EXISTS \\\"$${SULU_DB_SCHEMA}\\\"" >/dev/null 2>&1 || true
            fi

            if [ -n "$${SULU_DB_SCHEMA:-}" ] && [ -n "$${SULU_PRIMARY_REALM:-}" ] && [ "$${SULU_REALM:-}" = "$${SULU_PRIMARY_REALM}" ]; then
              echo "[init-db] migrating public schema into $${SULU_DB_SCHEMA} when needed..."
              DATABASE_URL="$${database_url_escaped}" php bin/console doctrine:query:sql "$(
                cat <<SQL
DO $$
DECLARE
  target_schema text := '$${SULU_DB_SCHEMA}';
  r record;
  non_system_tables integer := 0;
BEGIN
  IF target_schema IS NULL OR target_schema = '' OR target_schema = 'public' THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO non_system_tables
    FROM information_schema.tables
   WHERE table_schema = target_schema
     AND table_type = 'BASE TABLE'
     AND table_name NOT IN ('n8n_observer_events');

  IF non_system_tables = 0 AND EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
  ) THEN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
      EXECUTE format('ALTER TABLE public.%I SET SCHEMA %I', r.tablename, target_schema);
    END LOOP;

    FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public' LOOP
      EXECUTE format('ALTER SEQUENCE public.%I SET SCHEMA %I', r.sequence_name, target_schema);
    END LOOP;

    FOR r IN SELECT table_name FROM information_schema.views WHERE table_schema = 'public' LOOP
      EXECUTE format('ALTER VIEW public.%I SET SCHEMA %I', r.table_name, target_schema);
    END LOOP;
  END IF;
END $$;
SQL
              )" >/dev/null 2>&1 || true
            fi

            echo "[init-db] running sulu:build prod ..."
            DATABASE_URL="$${database_url_escaped}" php bin/adminconsole sulu:build prod --no-interaction
          fi

          if [ -n "$${DOWNLOAD_LANGUAGES}" ]; then
            for lang in $${DOWNLOAD_LANGUAGES}; do
              [ -n "$${lang}" ] || continue
              if [ "$${DOWNLOAD_FORCE}" = "1" ] || [ "$${DOWNLOAD_FORCE}" = "true" ] || [ ! -f "/var/www/html/translations/sulu_admin.$${lang}.yaml" ]; then
                echo "[init-db] attempting to download admin language: $${lang}"
                DATABASE_URL="$${database_url_escaped}" php bin/adminconsole sulu:admin:download-language "$${lang}" --no-interaction || true
              fi
            done
          fi

          if [ -f "$${PAGES_JSON}" ] && [ -f "$${PAGES_BIN}" ]; then
            echo "[init-db] ensuring default pages from $${PAGES_JSON}"
            i=1
            while :; do
              if SULU_CONTEXT=admin DATABASE_URL="$${database_url_escaped}" php "$${PAGES_BIN}" "$${PAGES_JSON}"; then
                break
              fi
              if [ "$${i}" -ge "$${PAGES_RETRIES}" ]; then
                echo "[init-db] ERROR: replace_sulu_pages.php failed after $${PAGES_RETRIES} attempt(s); continuing without pages sync" >&2
                break
              fi
              echo "[init-db] WARN: replace_sulu_pages.php failed (attempt $${i}/$${PAGES_RETRIES}); retrying in $${PAGES_RETRY_SLEEP_SECONDS}s..." >&2
              i=$((i + 1))
              sleep "$${PAGES_RETRY_SLEEP_SECONDS}"
            done
          else
            echo "[init-db] WARN: pages sync skipped (missing $${PAGES_JSON} or $${PAGES_BIN})" >&2
          fi

          if [ "$${sentinel_exists}" != "1" ]; then
            date -Iseconds > "$${SENTINEL}"
            echo "[init-db] completed."
          else
            echo "[init-db] completed (sentinel already exists)."
          fi
        EOT
      ]
      environment = [
        for k, v in merge(
          local.default_environment_sulu_base,
          {
            DEFAULT_URI         = "https://${local.sulu_realm_hosts[realm]}"
            SULU_HOST           = local.sulu_realm_hosts[realm]
            SULU_KEYCLOAK_REALM = realm
            SULU_REALM          = realm
            SULU_DB_SCHEMA      = local.sulu_realm_db_schemas[realm]
            SULU_PRIMARY_REALM  = local.sulu_primary_realm
          },
          coalesce(var.sulu_environment, {})
          ) : {
          name  = k
          value = v
        }
      ]
      secrets = concat(
        var.sulu_secrets,
        [for k, v in local.ssm_param_arns_sulu : { name = k, valueFrom = v }]
      )
      mountPoints = local.sulu_efs_id != null ? [
        {
          sourceVolume  = "sulu-share"
          containerPath = var.sulu_filesystem_path
          readOnly      = false
        }
      ] : []
      dependsOn = concat(
        local.sulu_efs_id != null ? [
          {
            containerName = "sulu-fs-init"
            condition     = "COMPLETE"
          }
        ] : [],
        [
          {
            containerName = "redis"
            condition     = "HEALTHY"
          },
          {
            containerName = "loupe-indexer-${realm}"
            condition     = "START"
          }
        ]
      )
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group"         = lookup(local.ecs_log_group_name_by_container, "sulu--init-db-${realm}", aws_cloudwatch_log_group.ecs["sulu"].name)
          "awslogs-stream-prefix" = "init-db"
        })
      })
    })],
    [for realm in [each.key] : merge(local.ecs_base_container, {
      name  = "php-fpm-${realm}"
      image = local.ecr_uri_sulu
      user  = "0:0"
      portMappings = [{
        containerPort = local.sulu_realm_fpm_ports[realm]
        hostPort      = local.sulu_realm_fpm_ports[realm]
        protocol      = "tcp"
      }]
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
          set -eu

          realm="$${SULU_REALM:-}"
          realm_root="${var.sulu_filesystem_path}"
          if [ -n "$${realm}" ]; then
            realm_root="${var.sulu_filesystem_path}/$${realm}"
          fi

          mkdir -p "$${realm_root}/media" "$${realm_root}/loupe" "$${realm_root}/locks"

          if [ -e "${var.sulu_share_dir}" ] && [ ! -L "${var.sulu_share_dir}" ]; then
            rm -rf "${var.sulu_share_dir}"
          fi
          if [ -e "/var/www/html/var/indexes" ] && [ ! -L "/var/www/html/var/indexes" ]; then
            rm -rf "/var/www/html/var/indexes"
          fi

          ln -snf "$${realm_root}/media" "${var.sulu_share_dir}"
          ln -snf "$${realm_root}/loupe" "/var/www/html/var/indexes"

          # Ensure Symfony cache/log dirs are writable by php-fpm workers (www-data).
          mkdir -p /var/www/html/var/cache/admin/prod /var/www/html/var/cache/website/prod /var/www/html/var/log
          chown -R www-data:www-data /var/www/html/var/cache /var/www/html/var/log || true
          chmod -R ug+rwX /var/www/html/var/cache /var/www/html/var/log || true

          # If ja is configured, make ja the default localization.
          # This avoids "No url found for \"/\" in locale \"ja\"" errors when the website context uses ja by default.
          if [ -f "/var/www/html/config/webspaces/website.xml" ] && grep -q 'language="ja"' "/var/www/html/config/webspaces/website.xml"; then
            php -r '
              $path = "/var/www/html/config/webspaces/website.xml";
              libxml_use_internal_errors(true);
              $dom = new DOMDocument();
              $dom->preserveWhiteSpace = true;
              $dom->formatOutput = false;
              if (!$dom->load($path)) {
                exit(0);
              }
              $xpath = new DOMXPath($dom);
              $xpath->registerNamespace("w", "http://schemas.sulu.io/webspace/webspace");

              // Remove default from all localizations, then set ja as default (idempotent).
              foreach ($xpath->query("//w:localization[@default]") as $node) {
                $node->removeAttribute("default");
              }
              foreach ($xpath->query("//w:localizations/w:localization[@language=\"ja\"][1]") as $node) {
                $node->setAttribute("default", "true");
              }

              // Ensure portal URLs are unique per locale.
              // Having the same URL for en/ja can lead to only one PortalInformation being registered.
              foreach ($xpath->query("//w:environment/w:urls/w:url[@language=\"en\"]") as $node) {
                $v = trim($node->textContent);
                if ($v === "{host}" || $v === "https://{host}" || $v === "http://{host}") {
                  $node->nodeValue = "{host}/en";
                }
              }
              foreach ($xpath->query("//w:environment/w:urls/w:url[@language=\"ja\"]") as $node) {
                $v = trim($node->textContent);
                if ($v === "{host}/ja") {
                  $node->nodeValue = "{host}";
                }
              }
              $dom->save($path);
            ' || true

            rm -rf /var/www/html/var/cache/* || true
          fi

          if [ -n "$${SULU_DB_SCHEMA:-}" ] && [ -n "$${DATABASE_URL:-}" ]; then
            database_url_raw="$${DATABASE_URL}"
            case "$${database_url_raw}" in
              *\?*)
                database_url_raw="$${database_url_raw}&options=--search_path%3D$${SULU_DB_SCHEMA}"
                ;;
              *)
                database_url_raw="$${database_url_raw}?options=--search_path%3D$${SULU_DB_SCHEMA}"
                ;;
            esac

            export DATABASE_URL="$(printf '%s' "$${database_url_raw}" | sed 's/%/%%/g')"
          elif [ -n "$${DATABASE_URL:-}" ]; then
            export DATABASE_URL="$(printf '%s' "$${DATABASE_URL}" | sed 's/%/%%/g')"
          fi

          if [ -n "$${SULU_FPM_PORT:-}" ]; then
            for conf in \
              /usr/local/etc/php-fpm.d/zz-docker.conf \
              /usr/local/etc/php-fpm.d/www.conf \
              /usr/local/etc/php-fpm.d/docker.conf \
              /usr/local/etc/php-fpm.d/www.conf.default; do
              if [ -f "$${conf}" ]; then
                sed -i "s/^listen[[:space:]]*=.*/listen = 0.0.0.0:$${SULU_FPM_PORT}/" "$${conf}"
              fi
            done
          fi

          exec php-fpm
        EOT
      ]
      environment = [
        for k, v in merge(
          local.default_environment_sulu_base,
          {
            DEFAULT_URI         = "https://${local.sulu_realm_hosts[realm]}"
            SULU_HOST           = local.sulu_realm_hosts[realm]
            SULU_KEYCLOAK_REALM = realm
            SULU_REALM          = realm
            SULU_DB_SCHEMA      = local.sulu_realm_db_schemas[realm]
            SULU_FPM_PORT       = tostring(local.sulu_realm_fpm_ports[realm])
            PGOPTIONS           = "--search_path=${local.sulu_realm_db_schemas[realm]},public"
          },
          coalesce(var.sulu_environment, {})
          ) : {
          name  = k
          value = v
        }
      ]
      secrets = concat(
        var.sulu_secrets,
        [for k, v in local.ssm_param_arns_sulu : { name = k, valueFrom = v }]
      )
      mountPoints = local.sulu_efs_id != null ? [
        {
          sourceVolume  = "sulu-share"
          containerPath = var.sulu_filesystem_path
          readOnly      = false
        }
      ] : []
      dependsOn = concat(
        local.sulu_efs_id != null ? [
          {
            containerName = "sulu-fs-init"
            condition     = "COMPLETE"
          }
        ] : [],
        [
          {
            containerName = "init-db-${realm}"
            condition     = "SUCCESS"
          },
          {
            containerName = "redis"
            condition     = "HEALTHY"
          },
          {
            containerName = "loupe-indexer-${realm}"
            condition     = "START"
          }
        ]
      )
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group"         = lookup(local.ecs_log_group_name_by_container, "sulu--php-fpm-${realm}", aws_cloudwatch_log_group.ecs["sulu"].name),
          "awslogs-stream-prefix" = "php"
        })
      })
    })],
    [for realm in [each.key] : merge(local.ecs_base_container, {
      name      = "nginx-${realm}"
      image     = local.ecr_uri_sulu_nginx
      essential = true
      portMappings = [{
        containerPort = local.sulu_realm_ports[realm]
        hostPort      = local.sulu_realm_ports[realm]
        protocol      = "tcp"
      }]
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
          set -eu

          realm="$${SULU_REALM:-}"
          realm_root="${var.sulu_filesystem_path}"
          if [ -n "$${realm}" ]; then
            realm_root="${var.sulu_filesystem_path}/$${realm}"
          fi

          mkdir -p "$${realm_root}/media"

          if [ -e "${var.sulu_share_dir}" ] && [ ! -L "${var.sulu_share_dir}" ]; then
            rm -rf "${var.sulu_share_dir}"
          fi

          ln -snf "$${realm_root}/media" "${var.sulu_share_dir}"

          if [ -n "$${SULU_HTTP_PORT:-}" ]; then
            sed -i "s/listen 80;/listen $${SULU_HTTP_PORT};/" /etc/nginx/conf.d/default.conf
          fi
          if [ -n "$${SULU_FPM_PORT:-}" ]; then
            sed -i "s/fastcgi_pass 127.0.0.1:9000;/fastcgi_pass 127.0.0.1:$${SULU_FPM_PORT};/" /etc/nginx/conf.d/default.conf
          fi

          exec nginx -g 'daemon off;'
        EOT
      ]
      environment = [
        {
          name  = "SULU_REALM"
          value = realm
        },
        {
          name  = "SULU_HTTP_PORT"
          value = tostring(local.sulu_realm_ports[realm])
        },
        {
          name  = "SULU_FPM_PORT"
          value = tostring(local.sulu_realm_fpm_ports[realm])
        }
      ]
      mountPoints = local.sulu_efs_id != null ? [
        {
          sourceVolume  = "sulu-share"
          containerPath = var.sulu_filesystem_path
          readOnly      = false
        }
      ] : []
      dependsOn = [
        {
          containerName = "php-fpm-${realm}"
          condition     = "START"
        }
      ]
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group"         = lookup(local.ecs_log_group_name_by_container, "sulu--nginx-${realm}", aws_cloudwatch_log_group.ecs["sulu"].name),
          "awslogs-stream-prefix" = "nginx"
        })
      })
    })]
  ))

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { realm = each.key, Name = "${local.name_prefix}-sulu-${each.key}-td" })
}

resource "aws_ecs_task_definition" "keycloak" {
  count = var.create_ecs && var.create_keycloak ? 1 : 0

  family                   = "${local.name_prefix}-keycloak"
  cpu                      = coalesce(var.keycloak_task_cpu, var.ecs_task_cpu)
  memory                   = coalesce(var.keycloak_task_memory, var.ecs_task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.keycloak_efs_id != null ? [1] : []
    content {
      name = "keycloak-data"
      efs_volume_configuration {
        file_system_id     = local.keycloak_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    local.keycloak_efs_id != null ? [
      merge(local.ecs_base_container, {
        name       = "keycloak-fs-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            mkdir -p "${var.keycloak_filesystem_path}/tmp"
            chown -R 1000:0 "${var.keycloak_filesystem_path}"
          EOT
        ]
        mountPoints = [{
          sourceVolume  = "keycloak-data"
          containerPath = var.keycloak_filesystem_path
          readOnly      = false
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "keycloak--keycloak-fs-init", aws_cloudwatch_log_group.ecs["keycloak"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name       = "keycloak-db-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            apk add --no-cache postgresql15-client >/dev/null

            db_host="$${KC_DB_HOST:-}"
            db_port="$${KC_DB_PORT:-5432}"
            db_user="$${KC_DB_USERNAME:-}"
            db_pass="$${KC_DB_PASSWORD:-}"
            db_name="$${KC_DB_NAME:-keycloak}"

            if [ -z "$${db_host}" ] || [ -z "$${db_user}" ] || [ -z "$${db_pass}" ]; then
              echo "Database variables are incomplete."
              exit 1
            fi

            export PGPASSWORD="$${db_pass}"

            echo "Waiting for PostgreSQL to become available..."
            until pg_isready -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" >/dev/null 2>&1; do
              sleep 2
            done

            role_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -Atc "SELECT 1 FROM pg_roles WHERE rolname = '$${db_user}'" || true)"
            if [ "$${role_exists}" != "1" ]; then
              echo "Creating role $${db_user}..."
              psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -c "CREATE ROLE \"$${db_user}\" WITH LOGIN PASSWORD '$${db_pass}';" || true
            fi

            db_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$${db_name}'" || true)"
            if [ "$${db_exists}" != "1" ]; then
              echo "Creating database $${db_name}..."
              psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -c "CREATE DATABASE \"$${db_name}\" OWNER \"$${db_user}\";"
            else
              echo "Database $${db_name} already exists."
            fi
          EOT
        ]
        secrets = [for k, v in local.ssm_param_arns_keycloak : { name = k, valueFrom = v }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "keycloak--keycloak-db-init", aws_cloudwatch_log_group.ecs["keycloak"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name       = "keycloak-realm-import"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            import_dir="${var.keycloak_filesystem_path}/import"
            mkdir -p "$${import_dir}"
            cat > "$${import_dir}/realm-ja.json" <<'JSON'
{
  "realm": "master",
  "enabled": true,
  "internationalizationEnabled": ${local.keycloak_realm_master_i18n_enabled},
  "defaultLocale": ${jsonencode(local.keycloak_realm_master_default_locale)},
  "supportedLocales": ${jsonencode(local.keycloak_realm_master_supported_locales)},
  "smtpServer": {
    "auth": "true",
    "from": ${jsonencode(local.keycloak_realm_master_email_from)},
    "fromDisplayName": ${jsonencode(local.keycloak_realm_master_email_from_display_name)},
    "host": "email-smtp.${var.region}.amazonaws.com",
    "port": "587",
    "replyTo": ${jsonencode(local.keycloak_realm_master_email_reply_to)},
    "replyToDisplayName": ${jsonencode(local.keycloak_realm_master_email_reply_to_display_name)},
    "envelopeFrom": ${jsonencode(local.keycloak_realm_master_email_envelope_from)},
    "starttls": "true",
    "ssl": "false"
  }
}
JSON
            chown -R 1000:0 "$${import_dir}"
          EOT
        ]
        mountPoints = local.keycloak_efs_id != null ? [{
          sourceVolume  = "keycloak-data"
          containerPath = var.keycloak_filesystem_path
          readOnly      = false
        }] : []
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "keycloak--keycloak-realm-import", aws_cloudwatch_log_group.ecs["keycloak"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name    = "keycloak"
        image   = local.ecr_uri_keycloak
        user    = "1000:0"
        command = ["start"]
        portMappings = [{
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
          }, {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        }]
        environment = [for k, v in merge(local.default_environment_keycloak, var.keycloak_environment) : { name = k, value = v }]
        secrets = concat(
          var.keycloak_secrets,
          [for k, v in local.ssm_param_arns_keycloak : { name = k, valueFrom = v }]
        )
        mountPoints = local.keycloak_efs_id != null ? [{
          sourceVolume  = "keycloak-data"
          containerPath = var.keycloak_filesystem_path
          readOnly      = false
        }] : []
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "keycloak--keycloak", aws_cloudwatch_log_group.ecs["keycloak"].name)
          })
        })
        dependsOn = concat(
          local.keycloak_efs_id != null ? [
            {
              containerName = "keycloak-fs-init"
              condition     = "COMPLETE"
            }
          ] : [],
          [
            {
              containerName = "keycloak-db-init"
              condition     = "COMPLETE"
            },
            {
              containerName = "keycloak-realm-import"
              condition     = "COMPLETE"
            }
          ]
        )
      })
    ]
  ))

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-keycloak-td" })
}

resource "aws_ecs_task_definition" "odoo" {
  count = var.create_ecs && var.create_odoo ? 1 : 0

  family                   = "${local.name_prefix}-odoo"
  cpu                      = coalesce(var.odoo_task_cpu, var.ecs_task_cpu)
  memory                   = coalesce(var.odoo_task_memory, var.ecs_task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.odoo_efs_id != null ? [1] : []
    content {
      name = "odoo-data"
      efs_volume_configuration {
        file_system_id     = local.odoo_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([
    merge(local.ecs_base_container, {
      name       = "odoo-db-init"
      image      = local.alpine_image_3_19
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
          set -eu
          apk add --no-cache postgresql15-client >/dev/null

          db_host="$${ODOO_DB_HOST:-$${DB_HOST:-$${HOST:-}}}"
          db_port="$${ODOO_DB_PORT:-$${DB_PORT:-$${PORT:-5432}}}"
          db_admin="$${DB_ADMIN_USER:-$${USER:-}}"
          db_admin_pass="$${DB_ADMIN_PASSWORD:-$${DB_PASSWORD:-$${PASSWORD:-}}}"
          db_user="$${ODOO_DB_USER:-$${DB_USER:-$${USER:-}}}"
          db_pass="$${ODOO_DB_PASSWORD:-$${DB_PASSWORD:-$${PASSWORD:-}}}"
          db_name="$${ODOO_DB_NAME:-$${DB_NAME:-$${DATABASE:-}}}"

          if [ -z "$${db_admin}" ]; then
            db_admin="$${db_user}"
          fi
          if [ -z "$${db_admin_pass}" ]; then
            db_admin_pass="$${db_pass}"
          fi

          if [ -z "$${db_host}" ] || [ -z "$${db_admin}" ] || [ -z "$${db_admin_pass}" ] || [ -z "$${db_name}" ]; then
            echo "Database variables are incomplete."
            exit 1
          fi

          export PGPASSWORD="$${db_admin_pass}"

          echo "Waiting for PostgreSQL to become available..."
          until pg_isready -h "$${db_host}" -p "$${db_port}" -U "$${db_admin}" >/dev/null 2>&1; do
            sleep 2
          done

          role_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_admin}" -d postgres -Atc "SELECT 1 FROM pg_roles WHERE rolname = '$${db_user}'" || true)"
          if [ "$${role_exists}" != "1" ] && [ -n "$${db_user}" ] && [ -n "$${db_pass}" ]; then
            echo "Creating role $${db_user} with the provided password..."
            psql -h "$${db_host}" -p "$${db_port}" -U "$${db_admin}" -d postgres -c "CREATE ROLE \"$${db_user}\" WITH LOGIN PASSWORD '$${db_pass}';" || true
            role_exists="1"
          fi

          if [ "$${role_exists}" == "1" ] && [ -n "$${db_user}" ] && [ -n "$${db_pass}" ]; then
            echo "Ensuring password for role $${db_user} is up to date..."
            psql -h "$${db_host}" -p "$${db_port}" -U "$${db_admin}" -d postgres -c "ALTER ROLE \"$${db_user}\" WITH LOGIN PASSWORD '$${db_pass}';" || true
          fi

          owner="$${db_user}"
          if [ -z "$${db_user}" ] || [ "$${role_exists}" != "1" ]; then
            echo "Role $${db_user:-<empty>} not found. Using admin user $${db_admin} as owner."
            owner="$${db_admin}"
          fi

          db_exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_admin}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$${db_name}'" || true)"
          if [ "$${db_exists}" != "1" ]; then
            echo "Creating database $${db_name} owned by $${owner}..."
            psql -h "$${db_host}" -p "$${db_port}" -U "$${db_admin}" -d postgres -c "CREATE DATABASE \"$${db_name}\" OWNER \"$${owner}\";"
          else
            echo "Database $${db_name} already exists."
          fi

          mkdir -p "${var.odoo_filesystem_path}/.local/share/Odoo"
          mkdir -p "${var.odoo_filesystem_path}/extra-addons"
          chown -R 101:101 "${var.odoo_filesystem_path}"
        EOT
      ]
      # Avoid duplicate secret names (e.g., DB_HOST) by merging the maps first.
      secrets = [for k, v in merge(local.db_ssm_param_arns, local.ssm_param_arns_odoo) : { name = k, valueFrom = v }]
      mountPoints = local.odoo_efs_id != null ? [{
        sourceVolume  = "odoo-data"
        containerPath = var.odoo_filesystem_path
        readOnly      = false
      }] : []
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "odoo--odoo-db-init", aws_cloudwatch_log_group.ecs["odoo"].name)
        })
      })
    }),
    merge(local.ecs_base_container, {
      name  = "odoo"
      image = local.ecr_uri_odoo
      user  = "101:101"
      portMappings = [{
        containerPort = 8069
        hostPort      = 8069
        protocol      = "tcp"
      }]
      mountPoints = local.odoo_efs_id != null ? [{
        sourceVolume  = "odoo-data"
        containerPath = var.odoo_filesystem_path
        readOnly      = false
      }] : []
      environment = [for k, v in merge(local.default_environment_odoo, var.odoo_environment) : { name = k, value = v }]
      secrets     = local.odoo_secrets_effective
      logConfiguration = merge(local.ecs_base_container.logConfiguration, {
        options = merge(local.ecs_base_container.logConfiguration.options, {
          "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "odoo--odoo", aws_cloudwatch_log_group.ecs["odoo"].name)
        })
      })
      dependsOn = [
        {
          containerName = "odoo-db-init"
          condition     = "COMPLETE"
        }
      ]
    })
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-odoo-td" })
}

resource "aws_ecs_task_definition" "gitlab" {
  count = var.create_ecs && var.create_gitlab ? 1 : 0

  family                   = "${local.name_prefix}-gitlab"
  cpu                      = var.gitlab_task_cpu
  memory                   = var.gitlab_task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.gitlab_data_efs_id != null ? [1] : []
    content {
      name = "gitlab-data"
      efs_volume_configuration {
        file_system_id     = local.gitlab_data_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  dynamic "volume" {
    for_each = local.gitlab_config_efs_id != null ? [1] : []
    content {
      name = "gitlab-config"
      efs_volume_configuration {
        file_system_id     = local.gitlab_config_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = local.gitlab_config_access_point_id_effective
          iam             = "DISABLED"
        }
      }
    }
  }

  dynamic "volume" {
    for_each = var.create_grafana && local.grafana_efs_id != null ? [1] : []
    content {
      name = "grafana-data"
      efs_volume_configuration {
        file_system_id     = local.grafana_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    (local.gitlab_data_efs_id != null || local.gitlab_config_efs_id != null) ? [
      merge(local.ecs_base_container, {
        name       = "gitlab-fs-init"
        image      = local.ecr_uri_gitlab
        essential  = false
        entryPoint = ["/bin/bash", "-lc"]
        command = [
          <<-EOT
	            set -euo pipefail

	            if [ -d "${var.gitlab_data_filesystem_path}" ]; then
	              echo "=== /var/opt/gitlab (before) ==="
	              ls -ld "${var.gitlab_data_filesystem_path}" || true
	            fi

	            # Ensure EFS paths used by omnibus are directories (avoid Errno::EEXIST).
	            if [ -e "${var.gitlab_data_filesystem_path}/gitlab-workhorse" ] && [ ! -d "${var.gitlab_data_filesystem_path}/gitlab-workhorse" ]; then
	              rm -f "${var.gitlab_data_filesystem_path}/gitlab-workhorse"
	            fi
	            mkdir -p "${var.gitlab_data_filesystem_path}/gitlab-workhorse/sockets"

	            if [ -e "${var.gitlab_data_filesystem_path}/redis" ] && [ ! -d "${var.gitlab_data_filesystem_path}/redis" ]; then
	              rm -f "${var.gitlab_data_filesystem_path}/redis"
	            fi
	            mkdir -p "${var.gitlab_data_filesystem_path}/redis"

	            redis_user=""
	            if getent passwd gitlab-redis >/dev/null; then
	              redis_user="gitlab-redis"
	            fi

	            prometheus_user=""
	            if getent passwd gitlab-prometheus >/dev/null; then
	              prometheus_user="gitlab-prometheus"
	            fi

	            alertmanager_user=""
	            if getent passwd gitlab-alertmanager >/dev/null; then
	              alertmanager_user="gitlab-alertmanager"
	            elif [ -n "$${prometheus_user}" ]; then
	              alertmanager_user="$${prometheus_user}"
	            fi

	            if [ -n "$${redis_user}" ]; then
	              redis_group="$(id -gn "$${redis_user}")"
	              mkdir -p "${var.gitlab_data_filesystem_path}/redis"
	              chown "$${redis_user}:$${redis_group}" "${var.gitlab_data_filesystem_path}/redis"
	              chmod 0700 "${var.gitlab_data_filesystem_path}/redis"
	              chown -R "$${redis_user}:$${redis_group}" "${var.gitlab_data_filesystem_path}/redis" || true
	            fi

	            if [ -n "$${prometheus_user}" ]; then
	              prometheus_group="$(id -gn "$${prometheus_user}")"
	              mkdir -p "${var.gitlab_data_filesystem_path}/prometheus/data"
	              chown "$${prometheus_user}:$${prometheus_group}" "${var.gitlab_data_filesystem_path}/prometheus"
	              chown "$${prometheus_user}:$${prometheus_group}" "${var.gitlab_data_filesystem_path}/prometheus/data"
	              chmod 0750 "${var.gitlab_data_filesystem_path}/prometheus"
	              chmod 0750 "${var.gitlab_data_filesystem_path}/prometheus/data"
	              chown -R "$${prometheus_user}:$${prometheus_group}" "${var.gitlab_data_filesystem_path}/prometheus" || true
	            fi

	            if [ -n "$${alertmanager_user}" ]; then
	              alertmanager_group="$(id -gn "$${alertmanager_user}")"
	              mkdir -p "${var.gitlab_data_filesystem_path}/alertmanager/data"
	              chown "$${alertmanager_user}:$${alertmanager_group}" "${var.gitlab_data_filesystem_path}/alertmanager"
	              chown "$${alertmanager_user}:$${alertmanager_group}" "${var.gitlab_data_filesystem_path}/alertmanager/data"
	              chmod 0750 "${var.gitlab_data_filesystem_path}/alertmanager"
	              chmod 0750 "${var.gitlab_data_filesystem_path}/alertmanager/data"
	              chown -R "$${alertmanager_user}:$${alertmanager_group}" "${var.gitlab_data_filesystem_path}/alertmanager" || true
	            fi

	            echo "=== /var/opt/gitlab (after) ==="
	            ls -ld "${var.gitlab_data_filesystem_path}" || true
	            ls -ld "${var.gitlab_data_filesystem_path}/redis" || true
	            ls -ld "${var.gitlab_data_filesystem_path}/prometheus/data" || true
	            ls -ld "${var.gitlab_data_filesystem_path}/alertmanager/data" || true
	          EOT
        ]
        mountPoints = concat(
          local.gitlab_data_efs_id != null ? [{
            sourceVolume  = "gitlab-data"
            containerPath = var.gitlab_data_filesystem_path
            readOnly      = false
          }] : [],
          local.gitlab_config_efs_id != null ? [{
            sourceVolume  = "gitlab-config"
            containerPath = var.gitlab_config_mount_base
            readOnly      = false
          }] : []
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "gitlab--gitlab-fs-init", aws_cloudwatch_log_group.ecs["gitlab"].name)
          })
        })
      })
    ] : [],
    var.create_grafana && local.grafana_efs_id != null ? [
      merge(local.ecs_base_container, {
        name       = "grafana-fs-init"
        image      = local.ecr_uri_grafana
        user       = "0"
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        dependsOn  = var.create_gitlab ? [{ containerName = "gitlab", condition = "START" }] : []
        command = [
          <<-EOT
            set -eu
            mkdir -p "${var.grafana_filesystem_path}"
            mkdir -p "${var.grafana_filesystem_path}/plugins"
            /usr/share/grafana/bin/grafana-cli plugins install grafana-athena-datasource || true
            for realm in ${local.grafana_realms_csv}; do
              realm_path="${var.grafana_filesystem_path}/$${realm}"
              mkdir -p "$${realm_path}"
              provisioning_path="$${realm_path}/provisioning"
              datasource_path="$${provisioning_path}/datasources"
              mkdir -p "$${datasource_path}"
              {
                printf '%s\n' "apiVersion: 1"
                printf '%s\n' "datasources:"
                printf '%s\n' "  - name: Athena"
                printf '%s\n' "    type: grafana-athena-datasource"
                printf '%s\n' "    access: proxy"
                printf '%s\n' "    isDefault: false"
                printf '%s\n' "    jsonData:"
                printf '%s\n' "      authType: default"
                printf '%s\n' "      defaultRegion: ${var.region}"
                printf '%s\n' "      outputLocation: s3://${local.grafana_athena_output_bucket_name}/$${realm}/"
              } > "$${datasource_path}/athena.yaml"
              {
                printf '%s\n' "apiVersion: 1"
                printf '%s\n' "datasources:"
                printf '%s\n' "  - name: CloudWatch"
                printf '%s\n' "    type: cloudwatch"
                printf '%s\n' "    access: proxy"
                printf '%s\n' "    isDefault: false"
                printf '%s\n' "    jsonData:"
                printf '%s\n' "      authType: default"
                printf '%s\n' "      defaultRegion: ${var.region}"
              } > "$${datasource_path}/cloudwatch.yaml"
              chown -R 472:472 "$${realm_path}"
            done
            chown -R 472:472 "${var.grafana_filesystem_path}/plugins" || true
          EOT
        ]
        mountPoints = [{
          sourceVolume  = "grafana-data"
          containerPath = var.grafana_filesystem_path
          readOnly      = false
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "grafana--grafana-fs-init", aws_cloudwatch_log_group.ecs["grafana"].name)
          })
        })
      })
    ] : [],
    var.create_grafana ? [
      merge(local.ecs_base_container, {
        name       = "grafana-db-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        dependsOn  = var.create_gitlab ? [{ containerName = "gitlab", condition = "START" }] : []
        command = [
          <<-EOT
            set -eu
            apk add --no-cache postgresql15-client >/dev/null

            db_host="$${GF_DATABASE_HOST:-}"
            db_port="$${GF_DATABASE_PORT:-5432}"
            db_user="$${GF_DATABASE_USER:-}"
            db_pass="$${GF_DATABASE_PASSWORD:-}"

            if [ -z "$${db_host}" ] || [ -z "$${db_user}" ] || [ -z "$${db_pass}" ]; then
              echo "Database variables are incomplete."
              exit 1
            fi

            export PGPASSWORD="$${db_pass}"

            echo "Waiting for PostgreSQL $${db_host}:$${db_port} ..."
            until pg_isready -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" >/dev/null 2>&1; do
              sleep 3
            done

            for realm in ${local.grafana_realms_csv}; do
              db_name="grafana_$${realm}"
              exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$${db_name}'" || true)"
              if [ "$${exists}" != "1" ]; then
                echo "Creating database $${db_name} owned by $${db_user}..."
                psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -c "CREATE DATABASE \"$${db_name}\" OWNER \"$${db_user}\";"
              else
                echo "Database $${db_name} already exists."
              fi
            done
          EOT
        ]
        secrets = [for k, v in local.ssm_param_arns_grafana_common : { name = k, valueFrom = v }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "grafana--grafana-db-init", aws_cloudwatch_log_group.ecs["grafana"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name       = "gitlab-db-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            apk add --no-cache postgresql15-client >/dev/null

            db_host="$${GITLAB_DB_HOST:-}"
            db_port="$${GITLAB_DB_PORT:-5432}"
            db_user="$${GITLAB_DB_USER:-}"
            db_pass="$${GITLAB_DB_PASSWORD:-}"
            db_name="$${GITLAB_DB_NAME:-gitlabhq_production}"

            if [ -z "$${db_host}" ] || [ -z "$${db_user}" ] || [ -z "$${db_pass}" ] || [ -z "$${db_name}" ]; then
              echo "Database variables are incomplete."
              exit 1
            fi

            export PGPASSWORD="$${db_pass}"

            echo "Waiting for PostgreSQL $${db_host}:$${db_port} ..."
            until pg_isready -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" >/dev/null 2>&1; do
              sleep 3
            done

            exists="$(psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$${db_name}'" || true)"
            if [ "$${exists}" != "1" ]; then
              echo "Creating database $${db_name} owned by $${db_user}..."
              psql -h "$${db_host}" -p "$${db_port}" -U "$${db_user}" -d postgres -c "CREATE DATABASE \"$${db_name}\" OWNER \"$${db_user}\";"
            else
              echo "Database $${db_name} already exists."
            fi
          EOT
        ]
        secrets = [for k, v in local.ssm_param_arns_gitlab : { name = k, valueFrom = v }]
        mountPoints = concat(
          local.gitlab_data_efs_id != null ? [{
            sourceVolume  = "gitlab-data"
            containerPath = var.gitlab_data_filesystem_path
            readOnly      = false
          }] : [],
          local.gitlab_config_efs_id != null ? concat(
            [{
              sourceVolume  = "gitlab-config"
              containerPath = var.gitlab_config_mount_base
              readOnly      = false
            }],
            [for p in var.gitlab_config_bind_paths : {
              sourceVolume  = "gitlab-config"
              containerPath = p
              readOnly      = false
            }]
          ) : []
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "gitlab--gitlab-db-init", aws_cloudwatch_log_group.ecs["gitlab"].name)
          })
        })
      }),
      merge(local.ecs_base_container, {
        name  = "gitlab"
        image = local.ecr_uri_gitlab
        portMappings = [
          {
            containerPort = 80
            hostPort      = 80
            protocol      = "tcp"
          },
          {
            containerPort = 22
            hostPort      = 22
            protocol      = "tcp"
          }
        ]
        environment = [for k, v in merge(local.default_environment_gitlab, var.gitlab_environment) : { name = k, value = v }]
        secrets     = local.gitlab_secrets_effective
        mountPoints = concat(
          local.gitlab_data_efs_id != null ? [{
            sourceVolume  = "gitlab-data"
            containerPath = var.gitlab_data_filesystem_path
            readOnly      = false
          }] : [],
          local.gitlab_config_efs_id != null ? concat(
            [{
              sourceVolume  = "gitlab-config"
              containerPath = var.gitlab_config_mount_base
              readOnly      = false
            }],
            [for p in var.gitlab_config_bind_paths : {
              sourceVolume  = "gitlab-config"
              containerPath = p
              readOnly      = false
            }]
          ) : []
        )
        dependsOn = concat(
          (local.gitlab_data_efs_id != null || local.gitlab_config_efs_id != null) ? [
            {
              containerName = "gitlab-fs-init"
              condition     = "COMPLETE"
            }
          ] : [],
          [{
            condition     = "SUCCESS"
            containerName = "gitlab-db-init"
          }]
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "gitlab--gitlab", aws_cloudwatch_log_group.ecs["gitlab"].name)
          })
        })
      })
    ],
    var.create_grafana && local.xray_grafana_enabled ? [
      merge(local.xray_daemon_container_common, {
        name = "xray-daemon-${local.ecs_grafana_shared_realm}"
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "grafana--xray-daemon-${local.ecs_grafana_shared_realm}", aws_cloudwatch_log_group.ecs["grafana"].name)
          })
        })
      })
    ] : [],
    var.create_grafana ? [
      for realm in local.grafana_realms : merge(local.ecs_base_container, {
        name  = "grafana-${realm}"
        image = local.ecr_uri_grafana
        user  = "472"
        portMappings = [{
          containerPort = local.grafana_realm_ports[realm]
          hostPort      = local.grafana_realm_ports[realm]
          protocol      = "tcp"
        }]
        environment = [
          for k, v in merge(
            local.default_environment_grafana_base,
            {
              GF_SERVER_ROOT_URL    = local.grafana_realm_root_urls[realm]
              GF_SERVER_DOMAIN      = local.grafana_realm_domains[realm]
              GF_SERVER_HTTP_PORT   = tostring(local.grafana_realm_ports[realm])
              GF_PATHS_DATA         = local.grafana_realm_paths[realm]
              GF_PATHS_PROVISIONING = "${var.grafana_filesystem_path}/${realm}/provisioning"
              GF_DATABASE_NAME      = local.grafana_realm_db_names[realm]
            },
            local.xray_grafana_enabled ? local.xray_daemon_env : {},
            var.enable_grafana_keycloak ? {
              GF_AUTH_GENERIC_OAUTH_ENABLED   = "true"
              GF_AUTH_GENERIC_OAUTH_NAME      = local.grafana_oidc_display_name_effective_by_realm[realm]
              GF_AUTH_GENERIC_OAUTH_AUTH_URL  = local.grafana_oidc_auth_url_by_realm[realm]
              GF_AUTH_GENERIC_OAUTH_TOKEN_URL = local.grafana_oidc_token_url_by_realm[realm]
              GF_AUTH_GENERIC_OAUTH_API_URL   = local.grafana_oidc_userinfo_url_effective_by_realm[realm]
              GF_AUTH_GENERIC_OAUTH_SCOPES    = local.grafana_oidc_scopes_effective_by_realm[realm]
            } : {},
            coalesce(var.grafana_environment, {})
          ) : { name = k, value = v }
        ]
        secrets = concat(
          local.grafana_common_secrets_effective,
          [for k, v in lookup(local.grafana_oidc_param_arns_by_realm, realm, {}) : { name = k, valueFrom = v }]
        )
        mountPoints = local.grafana_efs_id != null ? [{
          sourceVolume  = "grafana-data"
          containerPath = var.grafana_filesystem_path
          readOnly      = false
        }] : []
        dependsOn = concat(
          local.grafana_efs_id != null ? [
            {
              containerName = "grafana-fs-init"
              condition     = "COMPLETE"
            }
          ] : [],
          [
            {
              containerName = "grafana-db-init"
              condition     = "SUCCESS"
            },
            {
              containerName = "gitlab"
              condition     = "START"
            }
          ]
        )
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "grafana--grafana-${realm}", aws_cloudwatch_log_group.ecs["grafana"].name)
          })
        })
      })
    ] : []
  ))

  tags = merge(local.tags, { Name = "${local.name_prefix}-gitlab-td" })
}

resource "aws_ecs_task_definition" "pgadmin" {
  count = var.create_ecs && var.create_pgadmin ? 1 : 0

  family                   = "${local.name_prefix}-pgadmin"
  cpu                      = coalesce(var.pgadmin_task_cpu, var.ecs_task_cpu)
  memory                   = coalesce(var.pgadmin_task_memory, var.ecs_task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  dynamic "volume" {
    for_each = local.pgadmin_efs_id != null ? [1] : []
    content {
      name = "pgadmin-data"
      efs_volume_configuration {
        file_system_id     = local.pgadmin_efs_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = null
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(concat(
    local.pgadmin_efs_id != null ? [
      merge(local.ecs_base_container, {
        name       = "pgadmin-fs-init"
        image      = local.alpine_image_3_19
        essential  = false
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -eu
            mkdir -p "${var.pgadmin_filesystem_path}"
            chown -R 5050:5050 "${var.pgadmin_filesystem_path}"
          EOT
        ]
        mountPoints = [{
          sourceVolume  = "pgadmin-data"
          containerPath = var.pgadmin_filesystem_path
          readOnly      = false
        }]
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "pgadmin--pgadmin-fs-init", aws_cloudwatch_log_group.ecs["pgadmin"].name)
          })
        })
      })
    ] : [],
    [
      merge(local.ecs_base_container, {
        name  = "pgadmin"
        image = local.ecr_uri_pgadmin
        user  = "5050:5050"
        portMappings = [{
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }]
        entryPoint = ["/bin/sh", "-c"]
        command = [
          <<-EOT
            set -euo pipefail

            if [ -n "$${PGADMIN_OIDC_CLIENT_ID:-}" ] && [ -n "$${PGADMIN_OIDC_CLIENT_SECRET:-}" ]; then
              export PGADMIN_CONFIG_OAUTH2_CONFIG="$(python - <<'PY'
            import json
            import os

            cfg = {
                "OAUTH2_NAME": "keycloak",
                "OAUTH2_DISPLAY_NAME": "${local.pgadmin_oidc_display_name}",
                "OAUTH2_CLIENT_ID": os.environ["PGADMIN_OIDC_CLIENT_ID"],
                "OAUTH2_CLIENT_SECRET": os.environ["PGADMIN_OIDC_CLIENT_SECRET"],
                "OAUTH2_SERVER_METADATA_URL": "${local.pgadmin_oidc_metadata_url}",
                "OAUTH2_AUTHORIZATION_URL": "${local.pgadmin_oidc_auth_url}",
                "OAUTH2_TOKEN_URL": "${local.pgadmin_oidc_token_url}",
                "OAUTH2_API_BASE_URL": "${local.pgadmin_oidc_api_base_url}",
                "OAUTH2_USERINFO_ENDPOINT": "${local.pgadmin_oidc_userinfo_url}",
                "OAUTH2_SCOPE": "${local.pgadmin_oidc_scope}",
                "OAUTH2_USERNAME_CLAIM": "preferred_username",
                "OAUTH2_ICON": "fa-key",
                "OAUTH2_BUTTON_COLOR": "#2C4F9E",
            }

            print(json.dumps([cfg]))
            PY
              )"
            fi

            exec /entrypoint.sh
          EOT
        ]
        mountPoints = local.pgadmin_efs_id != null ? [{
          sourceVolume  = "pgadmin-data"
          containerPath = var.pgadmin_filesystem_path
          readOnly      = false
        }] : []
        environment = [for k, v in local.pgadmin_environment_effective : { name = k, value = v }]
        secrets     = local.pgadmin_secrets_effective
        dependsOn = local.pgadmin_efs_id != null ? [
          {
            containerName = "pgadmin-fs-init"
            condition     = "COMPLETE"
          }
        ] : []
        logConfiguration = merge(local.ecs_base_container.logConfiguration, {
          options = merge(local.ecs_base_container.logConfiguration.options, {
            "awslogs-group" = lookup(local.ecs_log_group_name_by_container, "pgadmin--pgadmin", aws_cloudwatch_log_group.ecs["pgadmin"].name)
          })
        })
      })
    ]
  ))

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.image_architecture_cpu
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-pgadmin-td" })
}
