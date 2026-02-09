locals {
  ssm_console_base = "https://${var.region}.console.aws.amazon.com/systems-manager/parameters"
  admin_param_names = {
    keycloak_admin_username  = var.create_ecs && var.create_keycloak ? local.keycloak_admin_username_parameter_name : null
    keycloak_admin_password  = var.create_ecs && var.create_keycloak ? local.keycloak_admin_password_parameter_name : null
    grafana_admin_username   = var.create_ecs && var.create_grafana ? local.grafana_admin_username_parameter_name : null
    grafana_admin_password   = var.create_ecs && var.create_grafana ? local.grafana_admin_password_parameter_name : null
    odoo_admin_password      = var.create_ecs && var.create_odoo ? local.odoo_admin_password_parameter_name : null
    pgadmin_default_password = var.create_ecs && var.create_pgadmin ? local.pgadmin_default_password_parameter_name : null
    zulip_admin_api_key      = var.create_ecs && var.create_zulip ? local.zulip_admin_api_key_parameter_name : null
  }
  admin_param_console_urls = {
    for key, param in local.admin_param_names :
    key => param != null ? "${local.ssm_console_base}/${urlencode(param)}/description?region=${var.region}" : null
  }
}

output "vpc_id" {
  description = "ID of the selected or created VPC"
  value       = local.vpc_id
  sensitive   = true
}

output "internet_gateway_id" {
  description = "ID of the selected or created internet gateway"
  value       = local.igw_id
  sensitive   = true
}

output "hosted_zone_id" {
  description = "Managed Route53 hosted zone ID"
  value       = local.hosted_zone_id
  sensitive   = true
}

output "hosted_zone_name_servers" {
  description = "Name servers for the managed hosted zone"
  value       = local.hosted_zone_name_servers
  sensitive   = true
}

output "hosted_zone_name" {
  description = "Managed Route53 hosted zone name (root domain)"
  value       = local.hosted_zone_name_input
  sensitive   = true
}

output "db_credentials_ssm_parameters" {
  description = "SSM parameter names for DB credentials (if created)"
  value = {
    username = try(aws_ssm_parameter.db_username[0].name, null)
    password = try(aws_ssm_parameter.db_password[0].name, null)
    host     = try(aws_ssm_parameter.db_host[0].name, null)
    port     = try(aws_ssm_parameter.db_port[0].name, null)
    name     = try(aws_ssm_parameter.db_name[0].name, null)
  }
  sensitive = true
}

output "zulip_admin_api_key_parameter_name" {
  description = "SSM parameter name for the Zulip admin API key (if created)"
  value       = var.create_ecs && var.create_zulip && var.zulip_admin_api_key != null ? local.zulip_admin_api_key_parameter_name : null
  sensitive   = true
}

output "zulip_bot_tokens_parameter_name" {
  description = "SSM parameter name for the Zulip realm bot token mapping (if created)"
  value       = var.create_ecs && var.create_zulip && local.zulip_bot_tokens_value != null ? local.zulip_bot_tokens_parameter_name : null
  sensitive   = true
}

output "aiops_zulip_api_base_url_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip API base URL by realm"
  value       = local.aiops_zulip_api_base_url_parameter_names_by_realm
  sensitive   = true
}

output "aiops_zulip_bot_email_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip bot email by realm"
  value       = local.aiops_zulip_bot_email_parameter_names_by_realm
  sensitive   = true
}

output "aiops_zulip_bot_token_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip bot token by realm"
  value       = local.aiops_zulip_bot_token_parameter_names_by_realm
  sensitive   = true
}

output "aiops_zulip_outgoing_token_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip outgoing token by realm"
  value       = local.aiops_zulip_outgoing_token_parameter_names_by_realm
  sensitive   = true
}

output "aiops_cloudwatch_webhook_secret_param_by_realm" {
  description = "SSM parameter names for the AIOps CloudWatch webhook secret by realm"
  value       = local.aiops_cloudwatch_webhook_secret_parameter_names_by_realm
  sensitive   = true
}

output "gitlab_admin_token_parameter_name" {
  description = "SSM parameter name for the GitLab admin token (if created)"
  value       = local.gitlab_admin_token_write_enabled ? local.gitlab_admin_token_parameter_name : null
  sensitive   = true
}

output "gitlab_runner_token_parameter_name" {
  description = "SSM parameter name for the GitLab Runner token (if created)"
  value       = local.gitlab_runner_token_write_enabled ? local.gitlab_runner_token_parameter_name : null
  sensitive   = true
}

output "gitlab_efs_mirror_state_machine_arn" {
  description = "Step Functions state machine ARN for GitLab->EFS mirror loop (if enabled)"
  value       = local.gitlab_efs_mirror_enabled ? try(aws_sfn_state_machine.gitlab_efs_mirror[0].arn, null) : null
  sensitive   = true
}

output "gitlab_efs_mirror_task_definition_arn" {
  description = "ECS task definition ARN used by the GitLab->EFS mirror loop (if enabled)"
  value       = local.gitlab_efs_mirror_enabled ? try(aws_ecs_task_definition.gitlab_efs_mirror[0].arn, null) : null
  sensitive   = true
}

output "gitlab_efs_indexer_state_machine_arn" {
  description = "Step Functions state machine ARN for GitLab EFS -> Qdrant indexer loop (if enabled)"
  value       = local.gitlab_efs_indexer_enabled ? try(aws_sfn_state_machine.gitlab_efs_indexer[0].arn, null) : null
  sensitive   = true
}

output "gitlab_efs_indexer_task_definition_arn" {
  description = "ECS task definition ARN used by the GitLab EFS -> Qdrant indexer loop (if enabled)"
  value       = local.gitlab_efs_indexer_enabled ? try(aws_ecs_task_definition.gitlab_efs_indexer[0].arn, null) : null
  sensitive   = true
}

output "gitlab_efs_indexer_collection_alias_map" {
  description = "Qdrant collection alias map by management domain used by the GitLab EFS indexer"
  value       = var.gitlab_efs_indexer_collection_alias_map
  sensitive   = false
}

output "gitlab_realm_admin_tokens_yaml_parameter_name" {
  description = "SSM parameter name for the GitLab realm admin token mapping (YAML) (if created)"
  value       = local.gitlab_realm_admin_tokens_yaml_value != null ? local.gitlab_realm_admin_tokens_yaml_parameter_name : null
  sensitive   = true
}

output "gitlab_realm_admin_tokens_json_parameter_name" {
  description = "SSM parameter name for the GitLab realm admin token mapping (JSON) (if created)"
  value       = local.gitlab_realm_admin_tokens_json_value != null ? local.gitlab_realm_admin_tokens_json_parameter_name : null
  sensitive   = true
}

output "zulip_admin_api_key_parameter_names_by_realm" {
  description = "SSM parameter names for Zulip realm admin API keys (per realm) (if created)"
  value = var.create_ecs && var.create_n8n ? {
    for realm in local.n8n_realms :
    realm => lookup(local.zulip_admin_api_key_ssm_params_by_realm[realm], "ZULIP_ADMIN_API_KEY", null)
  } : {}
  sensitive = true
}

output "ecs_cluster" {
  description = "ECS cluster and roles"
  value = {
    name               = try(aws_ecs_cluster.this[0].name, null)
    arn                = try(aws_ecs_cluster.this[0].arn, null)
    execution_role_arn = try(aws_iam_role.ecs_execution[0].arn, null)
    task_role_arn      = try(aws_iam_role.ecs_task[0].arn, null)
  }
  sensitive = true
}

output "service_urls" {
  description = "Endpoints for user-facing services"
  value = {
    n8n         = var.create_ecs && var.create_n8n && local.n8n_primary_host != null ? "https://${local.n8n_primary_host}" : null
    qdrant      = var.create_ecs && var.create_n8n && var.enable_n8n_qdrant && local.n8n_has_efs_effective && local.qdrant_primary_host != null ? "https://${local.qdrant_primary_host}" : null
    zulip       = var.create_ecs && var.create_zulip ? "https://${local.zulip_host}" : null
    exastro     = local.exastro_service_enabled ? "https://${local.exastro_web_host}" : null
    pgadmin     = var.create_ecs && var.create_pgadmin ? "https://${local.pgadmin_host}" : null
    odoo        = var.create_ecs && var.create_odoo ? "https://${local.odoo_host}" : null
    keycloak    = var.create_ecs && var.create_keycloak ? "https://${local.keycloak_host}" : null
    gitlab      = var.create_ecs && var.create_gitlab ? "https://${local.gitlab_host}" : null
    grafana     = var.create_ecs && var.create_gitlab && var.create_grafana && local.grafana_primary_host != null ? "https://${local.grafana_primary_host}" : null
    sulu        = var.create_ecs && var.create_sulu && local.sulu_primary_host != null ? "https://${local.sulu_primary_host}" : null
    control_ui  = "https://${local.control_site_domain}"
    alb_dns     = try(aws_lb.app[0].dns_name, null)
    control_cf  = try(aws_cloudfront_distribution.control_site[0].domain_name, null)
    control_api = local.control_api_base_url_effective != "" ? "${local.control_api_base_url_effective}" : null
  }
  sensitive = true
}

output "gitlab_service_projects_path" {
  description = "Default GitLab service project path mapping by realm (realm => \"<realm>/service-management\")"
  value       = local.gitlab_service_projects_path_by_realm
}

output "gitlab_general_projects_path" {
  description = "Default GitLab general project path mapping by realm (realm => \"<realm>/general-management\")"
  value       = local.gitlab_general_projects_path_by_realm
}

output "gitlab_technical_projects_path" {
  description = "Default GitLab technical project path mapping by realm (realm => \"<realm>/technical-management\")"
  value       = local.gitlab_technical_projects_path_by_realm
}

output "gitlab_projects_path_json_parameter_name" {
  description = "SSM parameter name for GitLab projects path mapping JSON (if created)"
  value       = local.ssm_writes_enabled && var.create_ecs && var.create_n8n ? "/${local.name_prefix}/aiops/gitlab/projects_path_json" : null
  sensitive   = true
}

output "grafana_athena_output_bucket" {
  description = "S3 bucket used for Grafana Athena query results"
  value       = try(aws_s3_bucket.grafana_athena_output[0].bucket, null)
  sensitive   = true
}

output "alb_access_logs_athena_database" {
  description = "Glue database name for ALB access logs (Athena)."
  value       = local.alb_access_logs_athena_enabled ? try(aws_glue_catalog_database.alb_access_logs[0].name, null) : null
  sensitive   = true
}

output "alb_access_logs_athena_table" {
  description = "Glue table name for ALB access logs when realm sorter is disabled."
  value       = local.alb_access_logs_athena_enabled && !local.alb_access_logs_realm_sorter_enabled ? try(aws_glue_catalog_table.alb_access_logs[0].name, null) : null
  sensitive   = true
}

output "alb_access_logs_athena_tables_by_realm" {
  description = "Glue table names for ALB access logs per realm when realm sorter is enabled."
  value       = local.alb_access_logs_athena_enabled && local.alb_access_logs_realm_sorter_enabled ? local.alb_access_logs_athena_table_names_by_realm : {}
  sensitive   = true
}

output "service_logs_athena_database" {
  description = "Glue database name for service logs (n8n/grafana)."
  value       = local.service_logs_athena_enabled ? try(aws_glue_catalog_database.service_logs[0].name, null) : null
  sensitive   = true
}

output "n8n_logs_athena_table" {
  description = "Glue table name for n8n logs (Athena)."
  value       = local.n8n_logs_athena_enabled ? try(aws_glue_catalog_table.n8n_logs[0].name, null) : null
  sensitive   = true
}

output "grafana_logs_athena_tables_by_realm" {
  description = "Glue table names for Grafana logs per realm."
  value       = local.grafana_logs_athena_enabled ? local.grafana_logs_athena_table_names_by_realm : {}
  sensitive   = true
}

output "service_control_metrics_athena_database" {
  description = "Glue database name for service control metrics (Athena)."
  value       = local.service_control_metrics_athena_enabled ? try(aws_glue_catalog_database.service_control_metrics[0].name, null) : null
  sensitive   = true
}

output "service_control_metrics_athena_table" {
  description = "Glue table name for service control metrics (Athena)."
  value       = local.service_control_metrics_athena_enabled ? try(aws_glue_catalog_table.service_control_metrics[0].name, null) : null
  sensitive   = true
}

output "grafana_realm_urls" {
  description = "Grafana URLs per realm (https://<realm>.grafana.<domain>)"
  value = var.create_ecs && var.create_gitlab && var.create_grafana ? {
    for realm, host in local.grafana_realm_hosts : realm => "https://${host}"
  } : {}
  sensitive = true
}

output "itsm_monitoring_context" {
  description = "Non-secret monitoring context derived from monitoring_yaml (realm => config)."
  value       = local.itsm_monitoring_context_by_realm
  sensitive   = false
}

output "n8n_realm_urls" {
  description = "n8n URLs per realm (https://<realm>.<subdomain>.<domain>)"
  value = var.create_ecs && var.create_n8n ? {
    for realm, host in local.n8n_realm_hosts : realm => "https://${host}"
  } : {}
  sensitive = true
}

output "qdrant_realm_urls" {
  description = "Qdrant URLs per realm (https://<realm>.qdrant.<domain>)"
  value = var.create_ecs && var.create_n8n && var.enable_n8n_qdrant && local.n8n_has_efs_effective ? {
    for realm, host in local.qdrant_realm_hosts : realm => "https://${host}"
  } : {}
  sensitive = true
}

output "aiops_workflows_token" {
  description = "Workflow catalog token consumed by n8n workflows (N8N_WORKFLOWS_TOKEN)"
  value       = local.aiops_workflows_token_value
  sensitive   = true
}

output "n8n_api_key" {
  description = "Public API key for n8n (used by workflow catalog endpoints)"
  value       = local.n8n_api_key_value
  sensitive   = true
}

output "n8n_encryption_key_param" {
  description = "SSM parameter name for the legacy (single) n8n encryption key"
  value       = local.n8n_encryption_key_parameter_name
  sensitive   = true
}

output "n8n_encryption_key" {
  description = "n8n encryption key values by realm"
  value       = local.n8n_encryption_key_by_realm_effective
  sensitive   = true
}

output "n8n_encryption_key_param_by_realm" {
  description = "SSM parameter names for the n8n encryption key by realm"
  value       = local.n8n_encryption_key_parameter_names_by_realm
  sensitive   = true
}

output "n8n_encryption_key_single" {
  description = "Legacy (single) n8n encryption key value"
  value       = local.n8n_encryption_key_effective
  sensitive   = true
}

output "openai_model_api_key_param" {
  description = "SSM parameter name for the OpenAI-compatible API key"
  value       = local.openai_model_api_key_parameter_name
  sensitive   = true
}

output "openai_model_api_key_param_by_realm" {
  description = "SSM parameter names for the OpenAI-compatible API key by realm"
  value       = local.openai_model_api_key_parameter_names_by_realm
  sensitive   = true
}

output "openai_model_param_by_realm" {
  description = "SSM parameter names for the OpenAI-compatible model by realm"
  value       = local.openai_model_parameter_names_by_realm
}

output "openai_base_url_param_by_realm" {
  description = "SSM parameter names for the OpenAI-compatible base URL by realm"
  value       = local.openai_base_url_parameter_names_by_realm
}

output "aiops_s3_prefix_param" {
  description = "SSM parameter name for N8N_S3_PREFIX"
  value       = local.aiops_s3_prefix_parameter_name
}

output "aiops_s3_bucket_names_by_realm" {
  description = "AIOPS S3 bucket names by realm"
  value       = local.aiops_s3_bucket_names_by_realm
}

output "aiops_s3_bucket_param_by_realm" {
  description = "SSM parameter names for N8N_S3_BUCKET by realm"
  value       = local.aiops_s3_bucket_parameter_names_by_realm
}

output "aiops_gitlab_first_contact_done_label_param" {
  description = "SSM parameter name for N8N_GITLAB_FIRST_CONTACT_DONE_LABEL"
  value       = local.aiops_gitlab_first_contact_done_label_parameter_name
}

output "aiops_gitlab_escalation_label_param" {
  description = "SSM parameter name for N8N_GITLAB_ESCALATION_LABEL"
  value       = local.aiops_gitlab_escalation_label_parameter_name
}

output "gitlab_ssh_endpoint" {
  description = "GitLab SSH endpoint (host/port) when SSH is enabled"
  value       = local.gitlab_ssh_enabled ? "ssh://git@${local.gitlab_ssh_host}:${var.gitlab_ssh_port}" : null
  sensitive   = true
}

output "keycloak_realm_master_email_settings" {
  description = "Master realm email settings applied to Keycloak"
  value = var.create_ecs && var.create_keycloak ? {
    from                  = local.keycloak_realm_master_email_from
    from_display_name     = local.keycloak_realm_master_email_from_display_name
    reply_to              = local.keycloak_realm_master_email_reply_to
    reply_to_display_name = local.keycloak_realm_master_email_reply_to_display_name
    envelope_from         = local.keycloak_realm_master_email_envelope_from
    allow_utf8            = local.keycloak_realm_master_email_allow_utf8
  } : null
}

output "keycloak_realm_master_localization" {
  description = "Master realm localization settings applied to Keycloak"
  value = var.create_ecs && var.create_keycloak ? {
    internationalization_enabled = local.keycloak_realm_master_i18n_enabled
    supported_locales            = local.keycloak_realm_master_supported_locales
    default_locale               = local.keycloak_realm_master_default_locale
  } : null
}

output "default_realm" {
  description = "Effective Keycloak realm used by the stack"
  value       = local.keycloak_realm_effective
}

output "ecs_logs_per_container_services" {
  description = "Services configured to use per-container CloudWatch log groups."
  value       = local.ecs_logs_per_container_services_effective
}

output "ecs_log_destinations_by_realm" {
  description = "CloudWatch log groups by realm and service (service-level + container-level)."
  value       = local.ecs_log_destinations_by_realm
}

output "enable_logs_to_s3" {
  description = "Service log shipping configuration for CloudWatch Logs to S3."
  value       = var.enable_logs_to_s3
}

output "enabled_services" {
  description = "ECS services enabled for deployment"
  value       = local.enabled_services
  sensitive   = true
}

# output "zulip_dependencies" {
#   description = "Connection details and parameter names for Zulip dependencies"
#   value = {
#     redis_host                   = local.zulip_redis_host
#     redis_port                   = local.zulip_redis_port
#     memcached_endpoint           = local.zulip_memcached_endpoint
#     memcached_host               = local.zulip_memcached_host
#     memcached_port               = local.zulip_memcached_port_effective
#     mq_endpoint                  = local.zulip_mq_amqp_endpoint
#     mq_host                      = local.zulip_mq_host
#     mq_port                      = local.zulip_mq_port_effective
#     mq_username                  = var.zulip_mq_username
#     mq_password_parameter        = local.zulip_mq_password_parameter_name
#     db_username_parameter        = local.zulip_db_username_parameter_name
#     db_password_parameter        = local.zulip_db_password_parameter_name
#     db_name_parameter            = local.zulip_db_name_parameter_name
#     secret_key_parameter         = local.zulip_secret_key_parameter_name
#     oidc_client_id_parameter     = local.zulip_oidc_client_id_parameter_name
#     oidc_client_secret_parameter = local.zulip_oidc_client_secret_parameter_name
#     oidc_idps_parameter          = local.zulip_oidc_idps_parameter_name
#   }
# }

output "service_control_api_base_url" {
  description = "Base URL for the service control API (n8n/zulip/sulu/keycloak/odoo/pgadmin/gitlab)"
  value       = local.service_control_api_base_url_effective
  sensitive   = true
}

output "n8n_filesystem_id" {
  description = "EFS ID used for n8n (if created or supplied)"
  value       = local.n8n_filesystem_id_effective
  sensitive   = true
}

output "zulip_filesystem_id" {
  description = "EFS ID used for Zulip (if created or supplied)"
  value       = local.zulip_filesystem_id_effective
  sensitive   = true
}

output "sulu_filesystem_id" {
  description = "EFS ID used for sulu (if created or supplied)"
  value       = try(local.sulu_filesystem_id_effective, null)
  sensitive   = true
}

output "exastro_filesystem_id" {
  description = "EFS ID used for Exastro IT Automation (if created or supplied)"
  value       = local.exastro_filesystem_id_effective
  sensitive   = true
}


output "keycloak_filesystem_id" {
  description = "EFS ID used for Keycloak (if created or supplied)"
  value       = local.keycloak_filesystem_id_effective
  sensitive   = true
}

output "odoo_filesystem_id" {
  description = "EFS ID used for Odoo (if created or supplied)"
  value       = local.odoo_filesystem_id_effective
  sensitive   = true
}

output "pgadmin_filesystem_id" {
  description = "EFS ID used for pgAdmin (if created or supplied)"
  value       = local.pgadmin_filesystem_id_effective
  sensitive   = true
}

output "grafana_filesystem_id" {
  description = "EFS ID used for Grafana (if created or supplied)"
  value       = local.grafana_filesystem_id_effective
  sensitive   = true
}

output "gitlab_data_filesystem_id" {
  description = "EFS ID used for GitLab data (if created or supplied)"
  value       = local.gitlab_data_filesystem_id_effective
  sensitive   = true
}

output "gitlab_config_filesystem_id" {
  description = "EFS ID used for GitLab config (if created or supplied)"
  value       = local.gitlab_config_filesystem_id_effective
  sensitive   = true
}

output "gitlab_data_access_point_id" {
  description = "Access Point ID that ensures GitLab data is mounted as UID/GID 998."
  value       = local.gitlab_data_access_point_id_effective
  sensitive   = true
}

output "gitlab_config_access_point_id" {
  description = "Access Point ID that ensures GitLab config is mounted as UID/GID 998."
  value       = local.gitlab_config_access_point_id_effective
  sensitive   = true
}

output "rds" {
  description = "RDS instance details (if created)"
  value = {
    identifier     = try(aws_db_instance.this[0].id, null)
    endpoint       = try(aws_db_instance.this[0].address, null)
    port           = try(aws_db_instance.this[0].port, null)
    engine         = try(aws_db_instance.this[0].engine, null)
    engine_version = try(aws_db_instance.this[0].engine_version, null)
  }
  sensitive = true
}

output "rds_postgresql" {
  description = "PostgreSQL RDS connection details (if created)"
  value = {
    host               = var.create_rds ? try(aws_db_instance.this[0].address, null) : null
    port               = var.create_rds ? try(aws_db_instance.this[0].port, null) : null
    database           = var.create_rds ? var.pg_db_name : null
    username           = var.create_rds ? local.master_username : null
    password_parameter = var.create_rds ? local.db_password_parameter_name : null
  }
  sensitive = true
}

output "pg_db_password" {
  description = "Effective PostgreSQL master password (if created)"
  value       = var.create_rds ? local.db_password_effective : null
  sensitive   = true
}

output "rds_mysql" {
  description = "MySQL RDS connection details (if created)"
  value = {
    host               = var.create_mysql_rds ? try(aws_db_instance.mysql[0].address, null) : null
    port               = var.create_mysql_rds ? try(aws_db_instance.mysql[0].port, null) : null
    database           = var.create_mysql_rds ? local.mysql_db_name_value : null
    username           = var.create_mysql_rds ? local.mysql_db_username_value : null
    password_parameter = var.create_mysql_rds ? local.mysql_db_password_parameter_name : null
  }
  sensitive = true
}

output "mysql_db_password" {
  description = "Effective MySQL database password (if created)"
  value       = var.create_mysql_rds ? local.mysql_db_password_value : null
  sensitive   = true
}

output "sulu_database_url" {
  description = "Effective Sulu DATABASE_URL (if created; includes credentials)"
  value       = local.sulu_database_url_value
  sensitive   = true
}

output "aiops_cloudwatch_webhook_secret_by_realm" {
  description = "CloudWatch webhook secret mapping by realm (for /notify; includes default)"
  value       = local.aiops_cloudwatch_webhook_secret_value_by_realm
  sensitive   = true
}

output "keycloak_admin_credentials" {
  description = "Initial Keycloak admin username/password and their backing SSM parameter names (if created)"
  value = var.create_ecs && var.create_keycloak ? {
    username     = local.keycloak_admin_username_value
    password     = local.keycloak_admin_password_value
    username_ssm = local.keycloak_admin_username_parameter_name
    password_ssm = local.keycloak_admin_password_parameter_name
  } : null
  sensitive = true
}

output "grafana_admin_credentials" {
  description = "Initial Grafana admin username/password and their backing SSM parameter names (if created)"
  value = var.create_ecs && var.create_grafana ? {
    username     = local.grafana_admin_username_value
    password     = local.grafana_admin_password_value
    username_ssm = local.grafana_admin_username_parameter_name
    password_ssm = local.grafana_admin_password_parameter_name
  } : null
  sensitive = true
}

output "initial_credentials" {
  description = "Initial admin credentials (user/password SSM) for selected services. Passwords are stored in SSM SecureString."
  sensitive   = true
  value = {
    zulip = {
      username     = null
      password_ssm = null
    }
    exastro = {
      username     = null
      password_ssm = null
    }
    odoo = {
      username     = var.create_ecs && var.create_odoo ? "admin" : null
      password_ssm = var.create_ecs && var.create_odoo ? local.odoo_admin_password_parameter_name : null
    }
    keycloak = {
      username_ssm = var.create_ecs && var.create_keycloak ? local.keycloak_admin_username_parameter_name : null
      password_ssm = var.create_ecs && var.create_keycloak ? local.keycloak_admin_password_parameter_name : null
    }
    n8n = {
      username     = null
      password_ssm = null
    }
    gitlab = {
      username     = null
      password_ssm = null
    }
    grafana = {
      username     = var.create_ecs && var.create_grafana ? local.grafana_admin_username_value : null
      password_ssm = var.create_ecs && var.create_grafana ? local.grafana_admin_password_parameter_name : null
    }
    pgadmin = {
      username     = var.create_ecs && var.create_pgadmin ? "admin@${local.hosted_zone_name_input}" : null
      password_ssm = var.create_ecs && var.create_pgadmin ? local.pgadmin_default_password_parameter_name : null
    }
  }
}

output "service_admin_info" {
  description = "Initial admin URLs and credential pointers per service (password values are not exposed; console links point to SSM SecureString entries)"
  value = {
    n8n = {
      admin_url                  = var.create_ecs && var.create_n8n && local.n8n_primary_host != null ? "https://${local.n8n_primary_host}/" : null
      admin_username             = null
      admin_username_console_url = null
      admin_password_console_url = null
      notes                      = "Create the first workspace user on initial visit; no default admin credentials are stored."
    }
    zulip = {
      admin_url                  = var.create_ecs && var.create_zulip ? "https://${local.zulip_host}/" : null
      admin_username             = null
      admin_username_console_url = null
      admin_password_console_url = null
      notes                      = "Create the first Zulip organization admin during initial signup; no default admin credentials are stored."
    }
    exastro = {
      admin_url                  = local.exastro_service_enabled ? "https://${local.exastro_web_host}/" : null
      admin_username             = null
      admin_username_console_url = null
      admin_password_console_url = null
      notes                      = "Exastro ITA web/API; default credentials are managed externally (not stored in Terraform)."
    }
    keycloak = {
      admin_url                  = var.create_ecs && var.create_keycloak ? "https://${local.keycloak_host}/admin" : null
      admin_username             = var.create_ecs && var.create_keycloak ? var.keycloak_admin_username : null
      admin_username_console_url = local.admin_param_console_urls.keycloak_admin_username
      admin_password_console_url = local.admin_param_console_urls.keycloak_admin_password
      notes                      = "Keycloak Admin Console; username/password are stored in SSM SecureString. Use the console link to view secrets."
    }
    odoo = {
      admin_url                  = var.create_ecs && var.create_odoo ? "https://${local.odoo_host}/web/login" : null
      admin_username             = var.create_ecs && var.create_odoo ? "admin" : null
      admin_username_console_url = null
      admin_password_console_url = local.admin_param_console_urls.odoo_admin_password
      notes                      = "Odoo backend login; the admin password is stored in SSM SecureString. Use the console link to reveal it."
    }
    pgadmin = {
      admin_url                  = var.create_ecs && var.create_pgadmin ? "https://${local.pgadmin_host}/" : null
      admin_username             = var.create_ecs && var.create_pgadmin ? "admin@${local.hosted_zone_name_input}" : null
      admin_username_console_url = null
      admin_password_console_url = local.admin_param_console_urls.pgadmin_default_password
      notes                      = "pgAdmin default user; the password is stored in SSM SecureString. Use the console link to reveal it."
    }
    gitlab = {
      admin_url                  = var.create_ecs && var.create_gitlab ? "https://${local.gitlab_host}/users/sign_in" : null
      admin_username             = var.create_ecs && var.create_gitlab ? "root" : null
      admin_username_console_url = null
      admin_password_console_url = null
      notes                      = "GitLab initial root password is generated on first start and written to /etc/gitlab/initial_root_password and container logs; not stored in SSM."
    }
    grafana = {
      admin_url                  = var.create_ecs && var.create_gitlab && var.create_grafana && local.grafana_primary_host != null ? "https://${local.grafana_primary_host}/" : null
      admin_username             = var.create_ecs && var.create_grafana ? local.grafana_admin_username_value : null
      admin_username_console_url = local.admin_param_console_urls.grafana_admin_username
      admin_password_console_url = local.admin_param_console_urls.grafana_admin_password
      notes                      = "Grafana admin password is stored in SSM SecureString."
    }
  }
  sensitive = true
}

output "ses_smtp_username" {
  description = "Auto-created SES SMTP username (if SES SMTP auto is enabled)"
  value       = local.ses_smtp_username_value
  sensitive   = true
}

output "ses_smtp_password" {
  description = "Auto-created SES SMTP password (if SES SMTP auto is enabled)"
  value       = local.ses_smtp_password_value
  sensitive   = true
}

output "ses_smtp_endpoint" {
  description = "SES SMTP endpoint for the selected region"
  value       = "email-smtp.${var.region}.amazonaws.com"
}

output "ses_smtp_starttls_port" {
  description = "SES SMTP STARTTLS port (TLS upgrade via 587)"
  value       = 587
}

output "ses_smtp_ssl_port" {
  description = "SES SMTP implicit TLS port (465)"
  value       = 465
}
