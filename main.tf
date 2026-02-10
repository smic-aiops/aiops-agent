terraform {
  required_version = ">= 1.14.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "~> 4.1"
    }
  }
}

locals {
  name_prefix_effective = coalesce(var.name_prefix, "${var.environment}-${var.platform}")
  ecr_namespace_effective_raw = coalesce(
    trimspace(var.ecr_namespace != null ? var.ecr_namespace : "") != "" ? trimspace(var.ecr_namespace) : null,
    local.name_prefix_effective
  )
  # Normalize for ECR repository naming. Keep it simple/stable: lower + replace invalid chars with "-".
  ecr_namespace_effective = trim(lower(replace(local.ecr_namespace_effective_raw, "/[^0-9A-Za-z._-]/", "-")), "-._")
  default_realm_effective = coalesce(
    var.default_realm != null && var.default_realm != "" ? var.default_realm : null,
    local.name_prefix_effective
  )
  gitlab_omnibus_semver = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.gitlab_omnibus_image_tag)) ? regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.gitlab_omnibus_image_tag) : ""
  gitlab_runner_image_tag_effective = coalesce(
    trimspace(var.gitlab_runner_image_tag != null ? var.gitlab_runner_image_tag : "") != "" ? trimspace(var.gitlab_runner_image_tag) : null,
    local.gitlab_omnibus_semver != "" ? "alpine-v${local.gitlab_omnibus_semver}" : null,
    "alpine-v17.11.7"
  )
  default_tags = merge(
    {
      environment = var.environment
      platform    = var.platform
      app         = local.name_prefix_effective
      realm       = local.default_realm_effective
    },
    coalesce(var.tags, {})
  )
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile

  default_tags {
    tags = local.default_tags
  }
}

data "aws_caller_identity" "current" {}

module "stack" {
  source = "./modules/stack"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix                                          = var.name_prefix
  environment                                          = var.environment
  platform                                             = var.platform
  region                                               = var.region
  hosted_zone_name                                     = var.hosted_zone_name
  ecr_namespace                                        = local.ecr_namespace_effective
  vpc_cidr                                             = var.vpc_cidr
  public_subnets                                       = var.public_subnets
  private_subnets                                      = var.private_subnets
  existing_vpc_id                                      = var.existing_vpc_id
  efs_transition_to_ia                                 = var.efs_transition_to_ia
  manage_existing_efs                                  = var.manage_existing_efs
  rds_deletion_protection                              = var.rds_deletion_protection
  rds_skip_final_snapshot                              = var.rds_skip_final_snapshot
  rds_backup_retention                                 = var.rds_backup_retention
  rds_max_locks_per_transaction                        = var.rds_max_locks_per_transaction
  rds_log_connections                                  = var.rds_log_connections
  rds_log_disconnections                               = var.rds_log_disconnections
  rds_performance_insights_enabled                     = var.rds_performance_insights_enabled
  rds_performance_insights_retention_period            = var.rds_performance_insights_retention_period
  pg_db_password                                       = var.pg_db_password
  existing_internet_gateway_id                         = var.existing_internet_gateway_id
  existing_nat_gateway_id                              = var.existing_nat_gateway_id
  create_n8n                                           = var.create_n8n
  n8n_filesystem_id                                    = var.n8n_filesystem_id
  n8n_api_key                                          = var.n8n_api_key
  n8n_admin_email                                      = var.n8n_admin_email
  n8n_admin_password                                   = var.n8n_admin_password
  n8n_encryption_key                                   = var.n8n_encryption_key
  n8n_db_postgresdb_pool_size                          = var.n8n_db_postgresdb_pool_size
  n8n_db_postgresdb_connection_timeout                 = var.n8n_db_postgresdb_connection_timeout
  n8n_db_postgresdb_idle_connection_timeout            = var.n8n_db_postgresdb_idle_connection_timeout
  n8n_db_ping_interval_seconds                         = var.n8n_db_ping_interval_seconds
  aiops_agent_environment                              = var.aiops_agent_environment
  aiops_s3_bucket_names                                = var.aiops_s3_bucket_names
  aiops_s3_bucket_parameter_name_prefix                = var.aiops_s3_bucket_parameter_name_prefix
  aiops_s3_prefix                                      = var.aiops_s3_prefix
  aiops_s3_prefix_parameter_name                       = var.aiops_s3_prefix_parameter_name
  aiops_gitlab_first_contact_done_label                = var.aiops_gitlab_first_contact_done_label
  aiops_gitlab_escalation_label                        = var.aiops_gitlab_escalation_label
  aiops_gitlab_first_contact_done_label_parameter_name = var.aiops_gitlab_first_contact_done_label_parameter_name
  aiops_gitlab_escalation_label_parameter_name         = var.aiops_gitlab_escalation_label_parameter_name
  aiops_ingest_rate_limit_rps                          = var.aiops_ingest_rate_limit_rps
  aiops_ingest_burst_rps                               = var.aiops_ingest_burst_rps
  aiops_tenant_rate_limit_rps                          = var.aiops_tenant_rate_limit_rps
  aiops_ingest_payload_max_bytes                       = var.aiops_ingest_payload_max_bytes
  openai_model_api_key_parameter_name                  = var.openai_model_api_key_parameter_name
  create_zulip                                         = var.create_zulip
  create_pgadmin                                       = var.create_pgadmin
  create_sulu                                          = var.create_sulu
  create_sulu_efs                                      = var.create_sulu_efs
  create_keycloak                                      = var.create_keycloak
  default_realm                                        = var.default_realm
  enable_zulip_alb_oidc                                = var.enable_zulip_alb_oidc
  create_odoo                                          = var.create_odoo
  create_gitlab                                        = var.create_gitlab
  create_gitlab_runner                                 = var.create_gitlab_runner
  create_grafana                                       = var.create_grafana
  ecs_task_additional_trust_principal_arns             = var.ecs_task_additional_trust_principal_arns
  gitlab_ssh_cidr_blocks                               = var.gitlab_ssh_cidr_blocks
  gitlab_ssh_port                                      = var.gitlab_ssh_port
  gitlab_ssh_host                                      = var.gitlab_ssh_host
  create_exastro                                       = var.create_exastro
  create_grafana_efs                                   = var.create_grafana_efs
  create_mysql_rds                                     = var.create_mysql_rds
  mysql_rds_skip_final_snapshot                        = var.mysql_rds_skip_final_snapshot
  enable_exastro                                       = var.enable_exastro
  create_ssm_parameters                                = var.create_ssm_parameters
  enable_ssm_key_expiry_checker                        = var.enable_ssm_key_expiry_checker
  ssm_key_expiry_sns_email                             = var.ssm_key_expiry_sns_email
  ssm_key_expiry_max_age_days                          = var.ssm_key_expiry_max_age_days
  ssm_key_expiry_warn_days                             = var.ssm_key_expiry_warn_days
  ssm_key_expiry_schedule_expression                   = var.ssm_key_expiry_schedule_expression
  ssm_key_expiry_manage_expires_at_tag                 = var.ssm_key_expiry_manage_expires_at_tag
  enable_n8n_autostop                                  = var.enable_n8n_autostop
  enable_exastro_autostop                              = var.enable_exastro_autostop
  n8n_desired_count                                    = var.n8n_desired_count
  enable_n8n_qdrant                                    = var.enable_n8n_qdrant
  qdrant_image_tag                                     = var.qdrant_image_tag
  enable_gitlab_efs_mirror                             = var.enable_gitlab_efs_mirror
  gitlab_efs_mirror_interval_seconds                   = var.gitlab_efs_mirror_interval_seconds
  gitlab_efs_mirror_parent_group_full_path             = var.gitlab_efs_mirror_parent_group_full_path
  gitlab_efs_mirror_project_paths                      = var.gitlab_efs_mirror_project_paths
  enable_gitlab_efs_indexer                            = var.enable_gitlab_efs_indexer
  gitlab_efs_indexer_interval_seconds                  = var.gitlab_efs_indexer_interval_seconds
  gitlab_efs_indexer_collection_alias                  = var.gitlab_efs_indexer_collection_alias
  gitlab_efs_indexer_collection_alias_map              = var.gitlab_efs_indexer_collection_alias_map
  gitlab_efs_indexer_embedding_model                   = var.gitlab_efs_indexer_embedding_model
  gitlab_efs_indexer_include_extensions                = var.gitlab_efs_indexer_include_extensions
  gitlab_efs_indexer_max_file_bytes                    = var.gitlab_efs_indexer_max_file_bytes
  gitlab_efs_indexer_chunk_size_chars                  = var.gitlab_efs_indexer_chunk_size_chars
  gitlab_efs_indexer_chunk_overlap_chars               = var.gitlab_efs_indexer_chunk_overlap_chars
  gitlab_efs_indexer_points_batch_size                 = var.gitlab_efs_indexer_points_batch_size
  enable_zulip_autostop                                = var.enable_zulip_autostop
  zulip_admin_email                                    = var.zulip_admin_email
  zulip_admin_api_key                                  = var.zulip_admin_api_key
  zulip_admin_api_keys_yaml                            = var.zulip_admin_api_keys_yaml
  zulip_mess_bot_tokens_yaml                           = var.zulip_mess_bot_tokens_yaml
  zulip_mess_bot_emails_yaml                           = var.zulip_mess_bot_emails_yaml
  zulip_api_mess_base_urls_yaml                        = var.zulip_api_mess_base_urls_yaml
  zulip_outgoing_tokens_yaml                           = var.zulip_outgoing_tokens_yaml
  zulip_outgoing_bot_emails_yaml                       = var.zulip_outgoing_bot_emails_yaml
  zulip_bot_tokens_param                               = var.zulip_bot_tokens_param
  zulip_desired_count                                  = var.zulip_desired_count
  sulu_desired_count                                   = var.sulu_desired_count
  sulu_health_check_grace_period_seconds               = var.sulu_health_check_grace_period_seconds
  enable_sulu_autostop                                 = var.enable_sulu_autostop
  enable_pgadmin_autostop                              = var.enable_pgadmin_autostop
  pgadmin_email                                        = var.pgadmin_email
  pgadmin_default_sender                               = var.pgadmin_default_sender
  sulu_db_name                                         = var.sulu_db_name
  sulu_db_username                                     = var.sulu_db_username
  sulu_share_dir                                       = var.sulu_share_dir
  sulu_filesystem_id                                   = var.sulu_filesystem_id
  sulu_filesystem_path                                 = var.sulu_filesystem_path
  sulu_app_secret                                      = var.sulu_app_secret
  sulu_mailer_dsn                                      = var.sulu_mailer_dsn
  sulu_admin_email                                     = var.sulu_admin_email
  sulu_sso_default_role_key                            = var.sulu_sso_default_role_key
  enable_keycloak_autostop                             = var.enable_keycloak_autostop
  enable_odoo_autostop                                 = var.enable_odoo_autostop
  pgadmin_desired_count                                = var.pgadmin_desired_count
  keycloak_desired_count                               = var.keycloak_desired_count
  keycloak_health_check_grace_period_seconds           = var.keycloak_health_check_grace_period_seconds
  exastro_desired_count                                = var.exastro_desired_count
  gitlab_desired_count                                 = var.gitlab_desired_count
  gitlab_runner_desired_count                          = var.gitlab_runner_desired_count
  gitlab_runner_task_cpu                               = var.gitlab_runner_task_cpu
  gitlab_runner_task_memory                            = var.gitlab_runner_task_memory
  gitlab_runner_ephemeral_storage_gib                  = var.gitlab_runner_ephemeral_storage_gib
  gitlab_runner_url                                    = var.gitlab_runner_url
  gitlab_runner_token                                  = var.gitlab_runner_token
  gitlab_runner_concurrent                             = var.gitlab_runner_concurrent
  gitlab_runner_check_interval                         = var.gitlab_runner_check_interval
  gitlab_runner_builds_dir                             = var.gitlab_runner_builds_dir
  gitlab_runner_cache_dir                              = var.gitlab_runner_cache_dir
  gitlab_runner_tags                                   = var.gitlab_runner_tags
  gitlab_runner_run_untagged                           = var.gitlab_runner_run_untagged
  gitlab_runner_environment                            = var.gitlab_runner_environment
  gitlab_runner_ssm_params                             = var.gitlab_runner_ssm_params
  gitlab_runner_secrets                                = var.gitlab_runner_secrets
  gitlab_data_filesystem_id                            = var.gitlab_data_filesystem_id
  gitlab_config_filesystem_id                          = var.gitlab_config_filesystem_id
  gitlab_data_efs_availability_zone                    = var.gitlab_data_efs_availability_zone
  gitlab_config_efs_availability_zone                  = var.gitlab_config_efs_availability_zone
  grafana_filesystem_id                                = var.grafana_filesystem_id
  grafana_efs_availability_zone                        = var.grafana_efs_availability_zone
  odoo_desired_count                                   = var.odoo_desired_count
  grafana_root_url                                     = var.grafana_root_url
  grafana_domain                                       = var.grafana_domain
  grafana_serve_from_sub_path                          = var.grafana_serve_from_sub_path
  grafana_filesystem_path                              = var.grafana_filesystem_path
  grafana_environment                                  = var.grafana_environment
  grafana_secrets                                      = var.grafana_secrets
  grafana_ssm_params                                   = var.grafana_ssm_params
  grafana_db_name                                      = var.grafana_db_name
  grafana_db_ssm_params                                = var.grafana_db_ssm_params
  grafana_admin_username                               = var.grafana_admin_username
  grafana_admin_password                               = var.grafana_admin_password
  grafana_api_tokens_by_realm                          = var.grafana_api_tokens_by_realm
  grafana_athena_output_bucket_name                    = var.grafana_athena_output_bucket_name
  enable_gitlab_autostop                               = var.enable_gitlab_autostop
  keycloak_base_url                                    = var.keycloak_base_url
  keycloak_admin_username                              = var.keycloak_admin_username
  keycloak_admin_password                              = var.keycloak_admin_password
  keycloak_realm_master_email_from                     = var.keycloak_realm_master_email_from
  keycloak_realm_master_email_from_display_name        = var.keycloak_realm_master_email_from_display_name
  keycloak_realm_master_email_reply_to                 = var.keycloak_realm_master_email_reply_to
  keycloak_realm_master_email_reply_to_display_name    = var.keycloak_realm_master_email_reply_to_display_name
  keycloak_realm_master_email_envelope_from            = var.keycloak_realm_master_email_envelope_from
  keycloak_realm_master_email_allow_utf8               = var.keycloak_realm_master_email_allow_utf8
  keycloak_realm_master_i18n_enabled                   = var.keycloak_realm_master_i18n_enabled
  keycloak_realm_master_supported_locales              = var.keycloak_realm_master_supported_locales
  keycloak_realm_master_default_locale                 = var.keycloak_realm_master_default_locale
  root_redirect_target_url                             = var.root_redirect_target_url
  s3_endpoint_route_table_ids                          = var.s3_endpoint_route_table_ids
  control_subdomain                                    = var.control_subdomain
  realms                                               = var.realms
  service_subdomain_map                                = var.service_subdomain_map
  ses_domain                                           = var.ses_domain
  ecr_repo_n8n                                         = var.ecr_repo_n8n
  ecr_repo_zulip                                       = var.ecr_repo_zulip
  ecr_repo_sulu                                        = var.ecr_repo_sulu
  ecr_repo_sulu_nginx                                  = var.ecr_repo_sulu_nginx
  ecr_repo_gitlab                                      = var.ecr_repo_gitlab
  ecr_repo_gitlab_runner                               = var.ecr_repo_gitlab_runner
  ecr_repo_grafana                                     = var.ecr_repo_grafana
  ecr_repo_pgadmin                                     = var.ecr_repo_pgadmin
  ecr_repo_keycloak                                    = var.ecr_repo_keycloak
  ecr_repo_exastro_it_automation_web_server            = var.ecr_repo_exastro_it_automation_web_server
  ecr_repo_exastro_it_automation_api_admin             = var.ecr_repo_exastro_it_automation_api_admin
  ecr_repo_odoo                                        = var.ecr_repo_odoo
  ecr_repo_alpine                                      = var.ecr_repo_alpine
  ecr_repo_redis                                       = var.ecr_repo_redis
  ecr_repo_memcached                                   = var.ecr_repo_memcached
  ecr_repo_rabbitmq                                    = var.ecr_repo_rabbitmq
  ecr_repo_mongo                                       = var.ecr_repo_mongo
  ecr_repo_python                                      = var.ecr_repo_python
  ecr_repo_qdrant                                      = var.ecr_repo_qdrant
  ecr_repo_xray_daemon                                 = var.ecr_repo_xray_daemon
  gitlab_omnibus_image_tag                             = var.gitlab_omnibus_image_tag
  gitlab_runner_image_tag                              = local.gitlab_runner_image_tag_effective
  keycloak_image_tag                                   = var.keycloak_image_tag
  pgadmin_image_tag                                    = var.pgadmin_image_tag
  enable_gitlab_keycloak                               = var.enable_gitlab_keycloak
  enable_grafana_keycloak                              = var.enable_grafana_keycloak
  enable_pgadmin_keycloak                              = var.enable_pgadmin_keycloak
  grafana_oidc_client_id                               = var.grafana_oidc_client_id
  grafana_oidc_client_secret                           = var.grafana_oidc_client_secret
  enable_odoo_keycloak                                 = var.enable_odoo_keycloak
  enable_sulu_keycloak                                 = var.enable_sulu_keycloak
  enable_service_control                               = var.enable_service_control
  monitoring_yaml                                      = var.monitoring_yaml
  service_control_api_base_url                         = var.service_control_api_base_url
  service_control_jwt_issuer                           = var.service_control_jwt_issuer
  service_control_jwt_audiences                        = var.service_control_jwt_audiences
  service_control_ui_client_id                         = var.service_control_ui_client_id
  service_control_oidc_client_id                       = var.service_control_oidc_client_id
  service_control_oidc_client_secret                   = var.service_control_oidc_client_secret
  service_control_oidc_client_id_parameter_name        = var.service_control_oidc_client_id_parameter_name
  service_control_oidc_client_secret_parameter_name    = var.service_control_oidc_client_secret_parameter_name
  enable_control_site_oidc_auth                        = var.enable_control_site_oidc_auth
  control_site_auth_allowed_group                      = var.control_site_auth_allowed_group
  control_site_auth_callback_path                      = var.control_site_auth_callback_path
  control_site_auth_edge_replica_cleanup_wait          = var.control_site_auth_edge_replica_cleanup_wait
  locked_schedule_services                             = var.locked_schedule_services
  service_control_lambda_reserved_concurrency          = var.service_control_lambda_reserved_concurrency
  service_control_schedule_overrides                   = var.service_control_schedule_overrides
  service_control_schedule_overwrite                   = var.service_control_schedule_overwrite
  service_control_metrics_stream_services              = var.service_control_metrics_stream_services
  service_control_metrics_bucket_name                  = var.service_control_metrics_bucket_name
  service_control_metrics_bucket_kms_key_arn           = var.service_control_metrics_bucket_kms_key_arn
  service_control_metrics_retention_days               = var.service_control_metrics_retention_days
  service_control_metrics_object_lock_enabled          = var.service_control_metrics_object_lock_enabled
  service_control_metrics_object_lock_mode             = var.service_control_metrics_object_lock_mode
  service_control_metrics_object_lock_retention_days   = var.service_control_metrics_object_lock_retention_days
  service_control_metrics_firehose_buffer_interval     = var.service_control_metrics_firehose_buffer_interval
  service_control_metrics_firehose_buffer_size         = var.service_control_metrics_firehose_buffer_size
  service_control_metrics_firehose_compression_format  = var.service_control_metrics_firehose_compression_format
  service_control_metrics_firehose_prefix              = var.service_control_metrics_firehose_prefix
  service_control_metrics_firehose_error_prefix        = var.service_control_metrics_firehose_error_prefix
  service_control_metrics_stream_output_format         = var.service_control_metrics_stream_output_format
  service_control_metrics_stream_include_filters       = var.service_control_metrics_stream_include_filters
  service_control_metrics_stream_exclude_filters       = var.service_control_metrics_stream_exclude_filters
  enable_service_control_metrics_athena                = var.enable_service_control_metrics_athena
  service_control_metrics_glue_database_name           = var.service_control_metrics_glue_database_name
  service_control_metrics_glue_table_name              = var.service_control_metrics_glue_table_name
  service_control_metrics_athena_prefix                = var.service_control_metrics_athena_prefix
  itsm_audit_event_anchor_enabled                      = var.itsm_audit_event_anchor_enabled
  itsm_audit_event_anchor_bucket_name                  = var.itsm_audit_event_anchor_bucket_name
  itsm_audit_event_anchor_bucket_kms_key_arn           = var.itsm_audit_event_anchor_bucket_kms_key_arn
  itsm_audit_event_anchor_retention_days               = var.itsm_audit_event_anchor_retention_days
  itsm_audit_event_anchor_object_lock_enabled          = var.itsm_audit_event_anchor_object_lock_enabled
  itsm_audit_event_anchor_object_lock_mode             = var.itsm_audit_event_anchor_object_lock_mode
  itsm_audit_event_anchor_object_lock_retention_days   = var.itsm_audit_event_anchor_object_lock_retention_days
  enable_efs_backup                                    = var.enable_efs_backup
  efs_backup_delete_after_days                         = var.efs_backup_delete_after_days
  enable_exastro_keycloak                              = var.enable_exastro_keycloak
  exastro_oidc_idps_yaml                               = var.exastro_oidc_idps_yaml
  sulu_oidc_idps_yaml                                  = var.sulu_oidc_idps_yaml
  keycloak_oidc_idps_yaml                              = var.keycloak_oidc_idps_yaml
  odoo_oidc_idps_yaml                                  = var.odoo_oidc_idps_yaml
  pgadmin_oidc_idps_yaml                               = var.pgadmin_oidc_idps_yaml
  gitlab_oidc_idps_yaml                                = var.gitlab_oidc_idps_yaml
  grafana_oidc_idps_yaml                               = var.grafana_oidc_idps_yaml
  zulip_oidc_idps_yaml                                 = var.zulip_oidc_idps_yaml
  aiops_workflows_token_parameter_name                 = var.aiops_workflows_token_parameter_name
  n8n_api_key_parameter_name                           = var.n8n_api_key_parameter_name
  n8n_smtp_username                                    = var.n8n_smtp_username
  n8n_smtp_password                                    = var.n8n_smtp_password
  n8n_smtp_sender                                      = var.n8n_smtp_sender
  zulip_smtp_username                                  = var.zulip_smtp_username
  zulip_smtp_password                                  = var.zulip_smtp_password
  zulip_environment                                    = var.zulip_environment
  zulip_missing_dictionaries                           = var.zulip_missing_dictionaries
  zulip_mq_port                                        = var.zulip_mq_port
  keycloak_smtp_username                               = var.keycloak_smtp_username
  keycloak_smtp_password                               = var.keycloak_smtp_password
  odoo_smtp_username                                   = var.odoo_smtp_username
  odoo_smtp_password                                   = var.odoo_smtp_password
  gitlab_smtp_username                                 = var.gitlab_smtp_username
  gitlab_smtp_password                                 = var.gitlab_smtp_password
  gitlab_admin_token                                   = var.gitlab_admin_token
  gitlab_realm_admin_tokens_yaml                       = var.gitlab_realm_admin_tokens_yaml
  gitlab_webhook_secrets_yaml                          = var.gitlab_webhook_secrets_yaml
  gitlab_email_from                                    = var.gitlab_email_from
  gitlab_email_reply_to                                = var.gitlab_email_reply_to
  pgadmin_smtp_username                                = var.pgadmin_smtp_username
  pgadmin_smtp_password                                = var.pgadmin_smtp_password
  sulu_efs_availability_zone                           = var.sulu_efs_availability_zone
  ecs_task_cpu                                         = var.ecs_task_cpu
  ecs_task_memory                                      = var.ecs_task_memory
  enable_alb_access_logs                               = var.enable_alb_access_logs
  alb_access_logs_bucket_name                          = var.alb_access_logs_bucket_name
  alb_access_logs_prefix                               = var.alb_access_logs_prefix
  alb_access_logs_retention_days                       = var.alb_access_logs_retention_days
  enable_alb_access_logs_athena                        = var.enable_alb_access_logs_athena
  alb_access_logs_glue_database_name                   = var.alb_access_logs_glue_database_name
  alb_access_logs_glue_table_name                      = var.alb_access_logs_glue_table_name
  enable_alb_access_logs_realm_sorter                  = var.enable_alb_access_logs_realm_sorter
  alb_access_logs_realm_sorter_source_prefix           = var.alb_access_logs_realm_sorter_source_prefix
  alb_access_logs_realm_sorter_target_prefix           = var.alb_access_logs_realm_sorter_target_prefix
  alb_access_logs_realm_sorter_delete_source           = var.alb_access_logs_realm_sorter_delete_source
  enable_logs_to_s3                                    = var.enable_logs_to_s3
  n8n_logs_bucket_name                                 = var.n8n_logs_bucket_name
  n8n_logs_prefix                                      = var.n8n_logs_prefix
  n8n_logs_error_prefix                                = var.n8n_logs_error_prefix
  n8n_logs_retention_days                              = var.n8n_logs_retention_days
  n8n_logs_subscription_filter_pattern                 = var.n8n_logs_subscription_filter_pattern
  grafana_logs_bucket_name                             = var.grafana_logs_bucket_name
  grafana_logs_prefix                                  = var.grafana_logs_prefix
  grafana_logs_error_prefix                            = var.grafana_logs_error_prefix
  grafana_logs_retention_days                          = var.grafana_logs_retention_days
  grafana_logs_subscription_filter_pattern             = var.grafana_logs_subscription_filter_pattern
  service_logs_retention_days                          = var.service_logs_retention_days
  service_logs_subscription_filter_pattern             = var.service_logs_subscription_filter_pattern
  enable_service_logs_athena                           = var.enable_service_logs_athena
  service_logs_glue_database_name                      = var.service_logs_glue_database_name
  xray_services                                        = var.xray_services
  xray_sampling_rate                                   = var.xray_sampling_rate
  xray_retention_days                                  = var.xray_retention_days
  enable_aiops_cloudwatch_alarm_sns                    = var.enable_aiops_cloudwatch_alarm_sns
  enable_sulu_updown_alarm                             = var.enable_sulu_updown_alarm
  exastro_task_cpu                                     = var.exastro_task_cpu
  exastro_task_memory                                  = var.exastro_task_memory
  sulu_task_cpu                                        = var.sulu_task_cpu
  sulu_task_memory                                     = var.sulu_task_memory
  keycloak_task_cpu                                    = var.keycloak_task_cpu
  keycloak_task_memory                                 = var.keycloak_task_memory
  pgadmin_task_cpu                                     = var.pgadmin_task_cpu
  pgadmin_task_memory                                  = var.pgadmin_task_memory
  n8n_task_cpu                                         = var.n8n_task_cpu
  n8n_task_memory                                      = var.n8n_task_memory
  zulip_task_cpu                                       = var.zulip_task_cpu
  zulip_task_memory                                    = var.zulip_task_memory
  odoo_task_cpu                                        = var.odoo_task_cpu
  odoo_task_memory                                     = var.odoo_task_memory
  gitlab_task_cpu                                      = var.gitlab_task_cpu
  gitlab_task_memory                                   = var.gitlab_task_memory
  zulip_image_tag                                      = var.zulip_image_tag
}
