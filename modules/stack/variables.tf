variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = null
}

variable "environment" {
  description = "Deployment environment (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

variable "platform" {
  description = "Platform or business unit name"
  type        = string
  default     = "aiops"
}

variable "name_prefix" {
  description = "Prefix used for naming resources; defaults to \"<environment>-<platform>\" when null"
  type        = string
  default     = null
}

variable "existing_vpc_id" {
  description = "If set, use this existing VPC instead of creating a new one (e.g., prod-aiops-vpc)"
  type        = string
  default     = null
}

variable "existing_internet_gateway_id" {
  description = "If set, reuse this internet gateway instead of creating a new one"
  type        = string
  default     = null
}

variable "existing_nat_gateway_id" {
  description = "If set, reuse this NAT gateway instead of creating a new one"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC"
  type        = string
  default     = null
}

variable "public_subnets" {
  description = "List of public subnets with name, cidr, and az"
  type = list(object({
    name = string
    cidr = string
    az   = string
  }))
  default = null
}

variable "private_subnets" {
  description = "List of private subnets with name, cidr, and az"
  type = list(object({
    name = string
    cidr = string
    az   = string
  }))
  default = null
}

variable "efs_transition_to_ia" {
  description = "EFS lifecycle policy setting to transition files to Infrequent Access (IA)"
  type        = string
  default     = "AFTER_1_DAY"

  validation {
    condition = contains([
      "AFTER_1_DAY",
      "AFTER_7_DAYS",
      "AFTER_14_DAYS",
      "AFTER_30_DAYS",
      "AFTER_60_DAYS",
      "AFTER_90_DAYS",
    ], var.efs_transition_to_ia)
    error_message = "efs_transition_to_ia must be one of AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS."
  }
}

variable "rds_deletion_protection" {
  description = "When true, enable deletion protection on RDS instances"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "When true, skip creating a final snapshot on RDS deletion (PostgreSQL)"
  type        = bool
  default     = true
}

variable "pg_db_username" {
  description = "Master username for the PostgreSQL instance"
  type        = string
  default     = null
}

variable "pg_db_password" {
  description = "Master password for the PostgreSQL instance"
  type        = string
  sensitive   = false
  default     = null
}

variable "n8n_db_password" {
  description = "Database password for n8n (optional, auto-generated if null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_db_password" {
  description = "Database password for Zulip (optional, auto-generated if null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "keycloak_db_username" {
  description = "Database username for Keycloak (defaults to master username when null)"
  type        = string
  default     = null
}

variable "keycloak_db_password" {
  description = "Database password for Keycloak (defaults to master password when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password (SecureString in SSM when set; auto-generated when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "keycloak_realm_master_email_from" {
  description = "From address for the master realm email settings (defaults to admin@<hosted_zone>)"
  type        = string
  default     = null
}

variable "keycloak_realm_master_email_from_display_name" {
  description = "From display name for the master realm email settings"
  type        = string
  default     = null
}

variable "keycloak_realm_master_email_reply_to" {
  description = "Reply-To address for the master realm email settings (defaults to no-reply@<hosted_zone>)"
  type        = string
  default     = null
}

variable "keycloak_realm_master_email_reply_to_display_name" {
  description = "Reply-To display name for the master realm email settings"
  type        = string
  default     = null
}

variable "keycloak_realm_master_email_envelope_from" {
  description = "Envelope From address for the master realm email settings (defaults to no-reply@<hosted_zone>)"
  type        = string
  default     = null
}

variable "keycloak_realm_master_email_allow_utf8" {
  description = "Allow UTF-8 characters in master realm email addresses"
  type        = bool
  default     = true
}

variable "keycloak_realm_master_i18n_enabled" {
  description = "Whether to enable internationalization for the master realm"
  type        = bool
  default     = true
}

variable "keycloak_realm_master_supported_locales" {
  description = "Supported locales for the master realm"
  type        = list(string)
  default     = ["ja", "en"]
}

variable "keycloak_realm_master_default_locale" {
  description = "Default locale for the master realm"
  type        = string
  default     = "ja"
}

variable "odoo_db_username" {
  description = "Database username for Odoo (defaults to master username when null)"
  type        = string
  default     = null
}

variable "odoo_db_password" {
  description = "Database password for Odoo (defaults to master password when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "odoo_admin_password" {
  description = "Odoo admin_passwd value (SecureString in SSM when set; auto-generated when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_db_username" {
  description = "Database username for GitLab (defaults to master username when null)"
  type        = string
  default     = null
}

variable "gitlab_db_password" {
  description = "Database password for GitLab (defaults to master password when null)"
  type        = string
  sensitive   = false
  default     = null
}
variable "oase_db_username" {
  description = "Database username for Exastro OASE (defaults to master username when null)"
  type        = string
  default     = null
}

variable "oase_db_password" {
  description = "Database password for Exastro OASE (defaults to master password when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "exastro_pf_db_username" {
  description = "Database username for Exastro ITA Platform DB (defaults to master username when null)"
  type        = string
  default     = null
}

variable "exastro_pf_db_password" {
  description = "Database password for Exastro ITA Platform DB (defaults to master password when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "exastro_ita_db_username" {
  description = "Database username for Exastro ITA Application DB (defaults to master username when null)"
  type        = string
  default     = null
}

variable "exastro_ita_db_password" {
  description = "Database password for Exastro ITA Application DB (defaults to master password when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "create_rds" {
  description = "Whether to create/manage the RDS instance"
  type        = bool
  default     = true
}

variable "rds_identifier" {
  description = "Identifier for the RDS instance; defaults to <name_prefix>-pg"
  type        = string
  default     = null
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.small"
}

variable "rds_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Max allocated storage in GB"
  type        = number
  default     = 100
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.15"
}

variable "rds_max_locks_per_transaction" {
  description = "PostgreSQL max_locks_per_transaction for RDS parameter group"
  type        = number
  default     = 512
}

variable "rds_backup_retention" {
  description = "Backup retention days"
  type        = number
  default     = 1
}

variable "rds_log_connections" {
  description = "When true, enable PostgreSQL log_connections in the RDS parameter group"
  type        = bool
  default     = false
}

variable "rds_log_disconnections" {
  description = "When true, enable PostgreSQL log_disconnections in the RDS parameter group"
  type        = bool
  default     = false
}

variable "rds_performance_insights_enabled" {
  description = "When true, enable Performance Insights for PostgreSQL RDS"
  type        = bool
  default     = false
}

variable "rds_performance_insights_retention_period" {
  description = "Performance Insights retention period in days (7 or 731)"
  type        = number
  default     = 7
  validation {
    condition     = contains([7, 731], var.rds_performance_insights_retention_period)
    error_message = "rds_performance_insights_retention_period must be 7 or 731."
  }
}

variable "create_db_credentials_parameters" {
  description = "Create SSM parameters for DB username/password"
  type        = bool
  default     = true
}

variable "db_username_parameter_name" {
  description = "SSM parameter name for DB username; defaults to /<name_prefix>/db/username"
  type        = string
  default     = null
}

variable "db_password_parameter_name" {
  description = "SSM parameter name for DB password; defaults to /<name_prefix>/db/password"
  type        = string
  default     = null
}

variable "hosted_zone_name" {
  description = "Hosted zone name to manage"
  type        = string
  default     = null
}

variable "keycloak_base_url" {
  description = "Base URL for Keycloak admin endpoint (defaults to https://keycloak.<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "default_realm" {
  description = "Keycloak realm used by services deployed via this module (defaults to name_prefix)"
  type        = string
  default     = "master"
}

variable "hosted_zone_id" {
  description = "Existing hosted zone ID to use when hosted_zone_name is not provided"
  type        = string
  default     = null
}

variable "hosted_zone_comment" {
  description = "Comment for the hosted zone"
  type        = string
  default     = "Managed by Terraform"
}

variable "hosted_zone_force_destroy" {
  description = "Whether to allow deletion of all records when destroying the zone"
  type        = bool
  default     = false
}

variable "hosted_zone_tag_name" {
  description = "Value for Name tag on hosted zone; defaults to hosted_zone_name"
  type        = string
  default     = null
}

variable "create_hosted_zone" {
  description = "Create the hosted zone if not found (set true to create a new public zone)"
  type        = bool
  default     = false
}

variable "root_redirect_target_url" {
  description = "Target URL for apex/www domain redirects (set null to disable redirect buckets)"
  type        = string
  default     = "https://github.com/smic-aiops/aiops-agent/blob/main/docs/usage-guide.md"
}

variable "s3_endpoint_route_table_ids" {
  description = "Route table IDs to associate with the S3 gateway endpoint (defaults to managed private route tables)"
  type        = list(string)
  default     = null
}

variable "control_subdomain" {
  description = "Subdomain for the business-site control UI (e.g., control)"
  type        = string
  default     = null
}

variable "realms" {
  description = "Realm names that should be reachable as <realm>.zulip.<hosted_zone_name> and <realm>.<n8n_subdomain>.<hosted_zone_name>"
  type        = list(string)
  default     = ["master"]
}

variable "service_subdomain_map" {
  description = <<EOF
Overrides for service subdomain prefixes. Keys match the internal service IDs
(e.g., n8n, zulip, gitlab); values are the label prepended to the shared root
hosted zone.
EOF
  type        = map(string)
  default     = null
}

variable "manage_existing_efs" {
  description = "Allow managing existing EFS with the expected Name tag (requires terraform import first)"
  type        = bool
  default     = true
}

variable "n8n_filesystem_id" {
  description = "Existing EFS ID to mount for n8n (if not creating new)"
  type        = string
  default     = null
}

variable "n8n_efs_availability_zone" {
  description = "AZ for One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "zulip_filesystem_id" {
  description = "Existing EFS ID to mount for Zulip (if not creating new)"
  type        = string
  default     = null
}

variable "sulu_filesystem_id" {
  description = "Existing EFS ID to mount for sulu (uploads/share)"
  type        = string
  default     = null
}

variable "pgadmin_filesystem_id" {
  description = "Existing EFS ID to mount for pgAdmin (if not creating new)"
  type        = string
  default     = null
}

variable "keycloak_filesystem_id" {
  description = "Existing EFS ID to mount for Keycloak (if not creating new)"
  type        = string
  default     = null
}

variable "odoo_filesystem_id" {
  description = "Existing EFS ID to mount for Odoo (if not creating new)"
  type        = string
  default     = null
}

variable "gitlab_data_filesystem_id" {
  description = "Existing EFS ID to mount for GitLab data (/var/opt/gitlab)"
  type        = string
  default     = null
}

variable "gitlab_config_filesystem_id" {
  description = "Existing EFS ID to mount for GitLab config (/etc/gitlab, /etc/letsencrypt)"
  type        = string
  default     = null
}

variable "grafana_filesystem_id" {
  description = "Existing EFS ID to mount for Grafana (if not creating new)"
  type        = string
  default     = null
}

variable "exastro_filesystem_id" {
  description = "Existing EFS ID to mount for Exastro IT Automation (if not creating new)"
  type        = string
  default     = null
}

variable "zulip_efs_availability_zone" {
  description = "AZ for One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "sulu_efs_availability_zone" {
  description = "AZ for One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "sulu_filesystem_path" {
  description = "Container path where the shared EFS is mounted"
  type        = string
  default     = "/efs"
}

variable "pgadmin_efs_availability_zone" {
  description = "AZ for One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "keycloak_efs_availability_zone" {
  description = "AZ for One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "odoo_efs_availability_zone" {
  description = "AZ for One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "gitlab_data_efs_availability_zone" {
  description = "AZ for GitLab data One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "gitlab_config_efs_availability_zone" {
  description = "AZ for GitLab config One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "grafana_efs_availability_zone" {
  description = "AZ for Grafana One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "exastro_efs_availability_zone" {
  description = "AZ for Exastro One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "create_n8n" {
  description = "Whether to create n8n service resources"
  type        = bool
  default     = true
}

variable "enable_n8n_qdrant" {
  description = "Whether to run Qdrant sidecar containers per n8n realm (EFS-backed, isolated by realm directory)"
  type        = bool
  default     = true
}

variable "qdrant_image_tag" {
  description = "Qdrant Docker image tag"
  type        = string
  default     = "v1.16.3"
}

variable "enable_gitlab_efs_mirror" {
  description = "Whether to enable GitLab project mirror into the n8n EFS (under /<n8n_filesystem_path>/qdrant/<realm>/gitlab/...)"
  type        = bool
  default     = true
}

variable "gitlab_efs_mirror_interval_seconds" {
  description = "Mirror interval (seconds) for the Step Functions loop"
  type        = number
  default     = 600
}

variable "gitlab_efs_mirror_parent_group_full_path" {
  description = "Optional GitLab parent group full_path; if set, realm group becomes <parent>/<realm> (used for clone URLs and EFS paths)"
  type        = string
  default     = null
}

variable "gitlab_efs_mirror_project_paths" {
  description = "GitLab project paths to mirror per realm (under the realm group)"
  type        = list(string)
  default = [
    "general-management",
    "general-management.wiki",
    "service-management",
    "service-management.wiki",
    "technical-management",
    "technical-management.wiki",
  ]
}

variable "enable_gitlab_efs_indexer" {
  description = "Whether to enable periodic indexing of mirrored GitLab repositories into Qdrant (per realm) via ECS + Step Functions loop"
  type        = bool
  default     = true
}

variable "gitlab_efs_indexer_interval_seconds" {
  description = "Indexer interval (seconds) for the Step Functions loop"
  type        = number
  default     = 3600
}

variable "gitlab_efs_indexer_collection_alias" {
  description = "Fallback Qdrant collection alias used for the GitLab EFS index (used when gitlab_efs_indexer_collection_alias_map is empty)"
  type        = string
  default     = "gitlab_efs"
}

variable "gitlab_efs_indexer_collection_alias_map" {
  description = "Qdrant collection alias map by management domain (e.g., general-management/service-management/technical-management). If set, the indexer writes into separate collections per domain."
  type        = map(string)
  default = {
    "general_management"   = "gitlab_efs_general_management"
    "service_management"   = "gitlab_efs_service_management"
    "technical_management" = "gitlab_efs_technical_management"
  }
}

variable "gitlab_efs_indexer_embedding_model" {
  description = "OpenAI-compatible embedding model name used by the GitLab EFS indexer"
  type        = string
  default     = "text-embedding-3-small"
}

variable "gitlab_efs_indexer_include_extensions" {
  description = "File extensions to index (case-insensitive); files not matching are skipped"
  type        = list(string)
  default = [
    ".md",
    ".markdown",
    ".mdx",
    ".txt",
    ".rst",
    ".adoc",
    ".org",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".ini",
    ".cfg",
    ".conf",
    ".env",
    ".tf",
    ".tfvars",
    ".sh",
    ".bash",
    ".zsh",
    ".py",
    ".js",
    ".ts",
    ".tsx",
    ".jsx",
    ".go",
    ".rb",
    ".java",
    ".kt",
    ".rs",
    ".php",
    ".cs",
    ".c",
    ".h",
    ".cpp",
    ".hpp",
    ".sql",
    ".graphql",
    ".proto",
    ".dockerfile",
    "Dockerfile",
    ".gitignore",
  ]
}

variable "gitlab_efs_indexer_max_file_bytes" {
  description = "Maximum file size (bytes) to index from Git; larger files are skipped"
  type        = number
  default     = 262144
}

variable "gitlab_efs_indexer_chunk_size_chars" {
  description = "Chunk size (characters) used for splitting long files for embedding"
  type        = number
  default     = 1200
}

variable "gitlab_efs_indexer_chunk_overlap_chars" {
  description = "Chunk overlap (characters) used for splitting long files for embedding"
  type        = number
  default     = 200
}

variable "gitlab_efs_indexer_points_batch_size" {
  description = "Batch size for Qdrant upsert requests"
  type        = number
  default     = 64
}

variable "create_zulip" {
  description = "Whether to create Zulip service resources"
  type        = bool
  default     = true
}


variable "create_sulu" {
  description = "Whether to create sulu service resources"
  type        = bool
  default     = true
}

variable "create_pgadmin" {
  description = "Whether to create pgAdmin service resources"
  type        = bool
  default     = true
}

variable "create_keycloak" {
  description = "Whether to create Keycloak service resources"
  type        = bool
  default     = true
}

variable "create_odoo" {
  description = "Whether to create Odoo service resources"
  type        = bool
  default     = true
}

variable "create_gitlab" {
  description = "Whether to create GitLab Omnibus service resources"
  type        = bool
  default     = true
}

variable "create_gitlab_runner" {
  description = "Whether to create GitLab Runner (shell executor on Fargate) resources"
  type        = bool
  default     = false
}

variable "create_grafana" {
  description = "Whether to add Grafana sidecar to the GitLab task"
  type        = bool
  default     = true
}

variable "enable_gitlab_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into GitLab task definition"
  type        = bool
  default     = true
}

variable "enable_grafana_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into Grafana"
  type        = bool
  default     = false
}

variable "enable_exastro" {
  description = "Flag to enable Exastro web + API services (tfvars-driven toggle)"
  type        = bool
  default     = false
}


variable "enable_n8n_autostop" {
  description = "Whether to enable n8n idle auto-stop (AppAutoScaling + CloudWatch alarm); service_control のスケジュール中はアラームを無効化するため競合しません。"
  type        = bool
  default     = true
}

variable "enable_exastro_autostop" {
  description = "Whether to enable Exastro idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "n8n_desired_count" {
  description = "Default desired count for n8n ECS service"
  type        = number
  default     = 1
}

variable "enable_zulip_autostop" {
  description = "Whether to enable Zulip idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "zulip_admin_email" {
  description = "Zulip admin email (defaults to admin@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "zulip_admin_api_key" {
  description = "Zulip admin API key (tfvars から読み取り SSM に格納する)"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_mess_bot_tokens_yaml" {
  description = "Zulip レルムごとの mess 用 Bot API キーマッピング（YAML: realm: token）"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_mess_bot_emails_yaml" {
  description = "Zulip レルムごとの mess 用 Bot メールアドレス（YAML: realm: email）"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_api_mess_base_urls_yaml" {
  description = "Zulip レルムごとの mess 用 API Base URL（YAML: realm: url）"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_outgoing_tokens_yaml" {
  description = "Zulip Outgoing Webhook のトークンマップ（YAML: realm: token）"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_outgoing_bot_emails_yaml" {
  description = "Zulip Outgoing Webhook bot のメールアドレスマップ（YAML: realm: email）"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_bot_tokens_param" {
  description = "Zulip Bot API キーマッピングを保存する SSM パラメータ名（未指定なら /<name_prefix>/zulip/bot_tokens）"
  type        = string
  sensitive   = false
  default     = null
}

variable "enable_sulu_autostop" {
  description = "Whether to enable sulu idle auto-stop (reserved for future use)"
  type        = bool
  default     = true
}

variable "enable_sulu_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into sulu task definition"
  type        = bool
  default     = false
}

variable "zulip_desired_count" {
  description = "Default desired count for Zulip ECS service"
  type        = number
  default     = 1
}

variable "sulu_desired_count" {
  description = "Default desired count for sulu ECS service"
  type        = number
  default     = 1
}

variable "sulu_health_check_grace_period_seconds" {
  description = "Grace period for Sulu ECS service load balancer health checks (seconds)"
  type        = number
  default     = 300
}

variable "exastro_desired_count" {
  description = "Default desired count for Exastro IT Automation web + API ECS services"
  type        = number
  default     = 1
}

variable "enable_pgadmin_autostop" {
  description = "Whether to enable pgAdmin idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "enable_keycloak_autostop" {
  description = "Whether to enable Keycloak idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "enable_odoo_autostop" {
  description = "Whether to enable Odoo idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "enable_odoo_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into Odoo task definition"
  type        = bool
  default     = true
}

variable "pgadmin_desired_count" {
  description = "Default desired count for pgAdmin ECS service"
  type        = number
  default     = 1
}

variable "enable_pgadmin_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into pgAdmin task definition"
  type        = bool
  default     = true
}

variable "keycloak_desired_count" {
  description = "Default desired count for Keycloak ECS service"
  type        = number
  default     = 1
}

variable "keycloak_health_check_grace_period_seconds" {
  description = "Grace period for Keycloak ECS service load balancer health checks (seconds)"
  type        = number
  default     = 300
}

variable "odoo_desired_count" {
  description = "Default desired count for Odoo ECS service"
  type        = number
  default     = 1
}

variable "gitlab_desired_count" {
  description = "Default desired count for GitLab ECS service"
  type        = number
  default     = 1
}

variable "gitlab_runner_desired_count" {
  description = "Default desired count for GitLab Runner ECS service"
  type        = number
  default     = 1
}

variable "gitlab_runner_task_cpu" {
  description = "Override CPU units for GitLab Runner task definition (null to use ecs_task_cpu)"
  type        = number
  default     = null
}

variable "gitlab_runner_task_memory" {
  description = "Override memory (MB) for GitLab Runner task definition (null to use ecs_task_memory)"
  type        = number
  default     = null
}

variable "gitlab_runner_ephemeral_storage_gib" {
  description = "Ephemeral storage size (GiB) for the GitLab Runner task (null to use Fargate default). Recommended when using shell executor."
  type        = number
  default     = 30

  validation {
    condition     = var.gitlab_runner_ephemeral_storage_gib == null || (var.gitlab_runner_ephemeral_storage_gib >= 21 && var.gitlab_runner_ephemeral_storage_gib <= 200)
    error_message = "gitlab_runner_ephemeral_storage_gib must be null or between 21 and 200."
  }
}

variable "gitlab_runner_url" {
  description = "GitLab URL for Runner registration/connection (defaults to the managed GitLab URL when create_gitlab is true)."
  type        = string
  default     = null
}

variable "gitlab_runner_token" {
  description = "GitLab Runner authentication token (stored in SSM if set). Prefer providing via SSM in production."
  type        = string
  sensitive   = true
  default     = null
}

variable "gitlab_runner_concurrent" {
  description = "Runner concurrent jobs limit (config.toml: concurrent)"
  type        = number
  default     = 1
}

variable "gitlab_runner_check_interval" {
  description = "Runner check interval seconds (config.toml: check_interval)"
  type        = number
  default     = 0
}

variable "gitlab_runner_builds_dir" {
  description = "Runner builds_dir (ephemeral recommended)."
  type        = string
  default     = "/tmp/gitlab-runner/builds"
}

variable "gitlab_runner_cache_dir" {
  description = "Runner cache_dir (ephemeral recommended)."
  type        = string
  default     = "/tmp/gitlab-runner/cache"
}

variable "gitlab_runner_tags" {
  description = "Runner tag list"
  type        = list(string)
  default     = []
}

variable "gitlab_runner_run_untagged" {
  description = "Whether the runner can pick untagged jobs"
  type        = bool
  default     = true
}

variable "gitlab_runner_environment" {
  description = "Extra environment variables for the runner container (non-secret)."
  type        = map(string)
  default     = {}
}

variable "gitlab_runner_ssm_params" {
  description = "Extra SSM parameter names to inject into the runner container (merged into secrets). Map of ENV_NAME => parameter name or full ARN."
  type        = map(string)
  default     = {}
}

variable "gitlab_runner_secrets" {
  description = "Additional secrets for the runner container (SSM parameter name or ARN)."
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "enable_gitlab_autostop" {
  description = "Whether to enable GitLab idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "n8n_smtp_username" {
  description = "SES SMTP username for n8n (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "n8n_smtp_password" {
  description = "SES SMTP password for n8n (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "n8n_smtp_sender" {
  description = "n8n SMTP sender address (defaults to no-reply@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "keycloak_smtp_username" {
  description = "SES SMTP username for Keycloak (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "keycloak_smtp_password" {
  description = "SES SMTP password for Keycloak (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "odoo_smtp_username" {
  description = "SES SMTP username for Odoo (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "odoo_smtp_password" {
  description = "SES SMTP password for Odoo (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_smtp_username" {
  description = "SES SMTP username for GitLab (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_smtp_password" {
  description = "SES SMTP password for GitLab (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_admin_token" {
  description = "GitLab admin personal access token (stored in SSM if set)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitlab_realm_admin_tokens_yaml" {
  description = "GitLab realm group access tokens mapping (YAML: realm: token)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitlab_realm_admin_tokens_yaml_parameter_name" {
  description = "SSM parameter name where the GitLab realm admin token mapping (YAML) is stored"
  type        = string
  default     = null
}

variable "zulip_admin_api_keys_yaml" {
  description = "Zulip realm admin API keys mapping (YAML: realm: api_key)"
  type        = string
  sensitive   = true
  default     = null
}

variable "grafana_api_tokens_by_realm" {
  description = "Grafana API tokens by realm (for automation scripts)"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "monitoring_yaml" {
  description = "Non-secret monitoring config (YAML/JSON string). Used for ITSM docs + n8n env injection (e.g., Grafana event inbox dashboard/panel IDs)."
  type        = string
  default     = null
}

variable "gitlab_webhook_secrets_yaml" {
  description = "GitLab webhook secrets mapping for n8n (YAML: realm: secret)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitlab_email_from" {
  description = "GitLab email From address (defaults to gitlab@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "gitlab_email_reply_to" {
  description = "GitLab email Reply-To address (defaults to noreply@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "pgadmin_smtp_username" {
  description = "SES SMTP username for pgAdmin (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "pgadmin_smtp_password" {
  description = "SES SMTP password for pgAdmin (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "ses_smtp_user_name" {
  description = "SES SMTP IAM user name override (defaults to <name_prefix>-ses-smtp)"
  type        = string
  default     = null
}

variable "ses_smtp_policy_name" {
  description = "SES SMTP IAM policy name override (defaults to <name_prefix>-ses-send-email)"
  type        = string
  default     = null
}

variable "enable_service_control" {
  description = "Enable service control API + waiting pages"
  type        = bool
  default     = true
}

variable "locked_schedule_services" {
  description = "Service IDs locked from schedule editing in the control site UI"
  type        = list(string)
  default     = []
}

variable "service_control_lambda_reserved_concurrency" {
  description = "Reserved concurrency for the service control API Lambda (set to guarantee capacity and avoid throttling; set to null to disable)"
  type        = number
  default     = null
}

variable "service_control_schedule_overrides" {
  description = "Overrides for service control automation schedule (weekday/weekend/holiday start/stop/idle)"
  type = map(object({
    enabled            = bool
    start_time         = string
    stop_time          = string
    idle_minutes       = number
    weekday_start_time = optional(string)
    weekday_stop_time  = optional(string)
    holiday_start_time = optional(string)
    holiday_stop_time  = optional(string)
  }))
  default = {}
}

variable "service_control_schedule_overwrite" {
  description = "Whether to overwrite existing service_control schedule SSM parameters"
  type        = bool
  default     = false
}

variable "service_control_metrics_stream_services" {
  description = "ECS service keys to export CloudWatch Metric Streams to S3 (e.g., n8n, zulip, gitlab). Use \"synthetics\" to include CloudWatch Synthetics metrics."
  type        = map(bool)
  default     = {}
}

variable "service_control_metrics_bucket_name" {
  description = "S3 bucket name for service control metrics (defaults to <name_prefix>-<region>-<account>-metrics)."
  type        = string
  default     = null
}

variable "service_control_metrics_bucket_kms_key_arn" {
  description = "KMS key ARN for service control metrics bucket encryption (uses SSE-S3 when null)."
  type        = string
  default     = null
}

variable "service_control_metrics_retention_days" {
  description = "Retention days for metric stream objects in S3."
  type        = number
  default     = 30

  validation {
    condition     = var.service_control_metrics_retention_days >= 1
    error_message = "service_control_metrics_retention_days must be >= 1."
  }
}

variable "service_control_metrics_object_lock_enabled" {
  description = "Whether to enable S3 Object Lock for service control metrics bucket."
  type        = bool
  default     = false
}

variable "service_control_metrics_object_lock_mode" {
  description = "Object Lock mode for service control metrics bucket (GOVERNANCE or COMPLIANCE)."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.service_control_metrics_object_lock_mode)
    error_message = "service_control_metrics_object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "service_control_metrics_object_lock_retention_days" {
  description = "Default Object Lock retention days for service control metrics bucket."
  type        = number
  default     = 30

  validation {
    condition     = !var.service_control_metrics_object_lock_enabled || var.service_control_metrics_object_lock_retention_days >= 1
    error_message = "service_control_metrics_object_lock_retention_days must be >= 1 when object lock is enabled."
  }
}

variable "itsm_audit_event_anchor_enabled" {
  description = "Whether to create a WORM S3 bucket to anchor ITSM audit_event hash-chain heads."
  type        = bool
  default     = false
}

variable "itsm_audit_event_anchor_bucket_name" {
  description = "S3 bucket name for ITSM audit_event anchors (defaults to <name_prefix>-<region>-<account>-itsm-audit-anchor)."
  type        = string
  default     = null
}

variable "itsm_audit_event_anchor_bucket_kms_key_arn" {
  description = "KMS key ARN for ITSM audit_event anchor bucket encryption (uses SSE-S3 when null)."
  type        = string
  default     = null
}

variable "itsm_audit_event_anchor_retention_days" {
  description = "Retention days for audit_event anchor objects in S3."
  type        = number
  default     = 3650

  validation {
    condition     = !var.itsm_audit_event_anchor_enabled || var.itsm_audit_event_anchor_retention_days >= 1
    error_message = "itsm_audit_event_anchor_retention_days must be >= 1 when itsm_audit_event_anchor_enabled is true."
  }
}

variable "itsm_audit_event_anchor_object_lock_enabled" {
  description = "Whether to enable S3 Object Lock for ITSM audit_event anchor bucket."
  type        = bool
  default     = true
}

variable "itsm_audit_event_anchor_object_lock_mode" {
  description = "Object Lock mode for ITSM audit_event anchor bucket (GOVERNANCE or COMPLIANCE)."
  type        = string
  default     = "COMPLIANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.itsm_audit_event_anchor_object_lock_mode)
    error_message = "itsm_audit_event_anchor_object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "itsm_audit_event_anchor_object_lock_retention_days" {
  description = "Default Object Lock retention days for ITSM audit_event anchor bucket."
  type        = number
  default     = 365

  validation {
    condition     = !var.itsm_audit_event_anchor_enabled || !var.itsm_audit_event_anchor_object_lock_enabled || var.itsm_audit_event_anchor_object_lock_retention_days >= 1
    error_message = "itsm_audit_event_anchor_object_lock_retention_days must be >= 1 when object lock is enabled."
  }
  validation {
    condition = (
      !var.itsm_audit_event_anchor_enabled
      || !var.itsm_audit_event_anchor_object_lock_enabled
      || var.itsm_audit_event_anchor_retention_days >= var.itsm_audit_event_anchor_object_lock_retention_days
    )
    error_message = "itsm_audit_event_anchor_retention_days must be >= itsm_audit_event_anchor_object_lock_retention_days."
  }
}

variable "service_control_metrics_firehose_buffer_interval" {
  description = "Firehose buffering interval (seconds) for service control metrics."
  type        = number
  default     = 300

  validation {
    condition     = var.service_control_metrics_firehose_buffer_interval >= 60 && var.service_control_metrics_firehose_buffer_interval <= 900
    error_message = "service_control_metrics_firehose_buffer_interval must be between 60 and 900 seconds."
  }
}

variable "service_control_metrics_firehose_buffer_size" {
  description = "Firehose buffering size (MB) for service control metrics."
  type        = number
  default     = 64

  validation {
    condition     = var.service_control_metrics_firehose_buffer_size >= 64 && var.service_control_metrics_firehose_buffer_size <= 128
    error_message = "service_control_metrics_firehose_buffer_size must be between 64 and 128 MB."
  }
}

variable "service_control_metrics_firehose_compression_format" {
  description = "Firehose compression format for service control metrics."
  type        = string
  default     = "GZIP"

  validation {
    condition = contains(
      ["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"],
      var.service_control_metrics_firehose_compression_format
    )
    error_message = "service_control_metrics_firehose_compression_format must be UNCOMPRESSED, GZIP, ZIP, Snappy, or HADOOP_SNAPPY."
  }
}

variable "service_control_metrics_firehose_prefix" {
  description = "S3 prefix for service control metrics in Firehose."
  type        = string
  default     = "metrics/realm=!{partitionKeyFromQuery:realm}/service=!{partitionKeyFromQuery:service}/container=!{partitionKeyFromQuery:container}/task=!{partitionKeyFromQuery:task}/dt=!{timestamp:yyyy/MM/dd/HH}/"
}

variable "service_control_metrics_firehose_error_prefix" {
  description = "S3 error prefix for service control metrics in Firehose."
  type        = string
  default     = "errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd/HH}/"
}

variable "service_control_metrics_stream_output_format" {
  description = "CloudWatch Metric Streams output format."
  type        = string
  default     = "opentelemetry1.0"

  validation {
    condition = contains(
      ["json", "opentelemetry0.7", "opentelemetry1.0"],
      var.service_control_metrics_stream_output_format
    )
    error_message = "service_control_metrics_stream_output_format must be json, opentelemetry0.7, or opentelemetry1.0."
  }
}

variable "service_control_metrics_stream_include_filters" {
  description = "Metric stream include filters (namespace + optional metric_names)."
  type = list(object({
    namespace    = string
    metric_names = optional(list(string))
  }))
  default = [
    {
      namespace = "ECS/ContainerInsights"
      metric_names = [
        "CpuUtilized",
        "CpuReserved",
        "MemoryUtilized",
        "MemoryReserved",
        "EphemeralStorageUtilized",
        "EphemeralStorageReserved"
      ]
    }
  ]
}

variable "service_control_metrics_stream_exclude_filters" {
  description = "Metric stream exclude filters (namespace + optional metric_names)."
  type = list(object({
    namespace    = string
    metric_names = optional(list(string))
  }))
  default = []
}

variable "enable_service_control_metrics_athena" {
  description = "Whether to create Glue catalog database/table for service control metrics in S3."
  type        = bool
  default     = false
}

variable "service_control_metrics_glue_database_name" {
  description = "Glue database name for service control metrics (defaults to <name_prefix>_service_metrics)."
  type        = string
  default     = null
}

variable "service_control_metrics_glue_table_name" {
  description = "Glue table name for service control metrics (defaults to service_metrics)."
  type        = string
  default     = null
}

variable "service_control_metrics_athena_prefix" {
  description = "S3 base prefix for service control metrics Athena table (defaults to metrics/)."
  type        = string
  default     = "metrics"
}

variable "enable_efs_backup" {
  description = "Enable the shared EFS backup configuration"
  type        = bool
  default     = false
}

variable "efs_backup_delete_after_days" {
  description = "EFS backup retention (days) for AWS Backup lifecycle"
  type        = number
  default     = 2
}

variable "ses_domain" {
  description = "SES domain identity (defaults to hosted_zone_name_input)"
  type        = string
  default     = null
}

variable "zulip_mq_password" {
  description = "Password for Amazon MQ (RabbitMQ) broker used by Zulip"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_secret_key" {
  description = "Override for Zulip SECRET_KEY (generate when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_oidc_client_id" {
  description = "OIDC client ID for Zulip SSO (stored in SSM SecureString)"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_oidc_client_secret" {
  description = "OIDC client secret for Zulip SSO (stored in SSM SecureString)"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_oidc_client_secret_parameter_name" {
  description = "Existing SSM parameter name/ARN for Zulip OIDC client secret (skip Terraform-managed creation when set)"
  type        = string
  default     = null
}

variable "zulip_oidc_full_name_validated" {
  description = "Whether to set SOCIAL_AUTH_OIDC_FULL_NAME_VALIDATED for Zulip"
  type        = bool
  default     = true
}

variable "zulip_oidc_pkce_enabled" {
  description = "Whether to set SOCIAL_AUTH_OIDC_PKCE_ENABLED for Zulip OIDC"
  type        = bool
  default     = true
}

variable "zulip_oidc_pkce_code_challenge_method" {
  description = "Value for SOCIAL_AUTH_OIDC_PKCE_CODE_CHALLENGE_METHOD (e.g., S256)"
  type        = string
  default     = "S256"
}

variable "zulip_oidc_idps_yaml" {
  description = "Override SOCIAL_AUTH_OIDC_ENABLED_IDPS YAML payload; defaults to Keycloak config when null"
  type        = string
  sensitive   = false
  default     = null
}

variable "exastro_oidc_idps_yaml" {
  description = "Optional override for Exastro Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}

variable "sulu_oidc_idps_yaml" {
  description = "Optional override for sulu Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}

variable "keycloak_oidc_idps_yaml" {
  description = "Optional override for Keycloak service Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}

variable "odoo_oidc_idps_yaml" {
  description = "Optional override for Odoo Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}

variable "pgadmin_oidc_idps_yaml" {
  description = "Optional override for pgAdmin Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_oidc_idps_yaml" {
  description = "Optional override for GitLab Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}

variable "grafana_oidc_idps_yaml" {
  description = "Optional override for Grafana Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}


variable "zulip_smtp_username" {
  description = "SES SMTP username for Zulip (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_smtp_password" {
  description = "SES SMTP password for Zulip (stored as SecureString in SSM if set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "enable_exastro_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into Exastro web + API task definitions"
  type        = bool
  default     = false
}

variable "exastro_web_oidc_client_id" {
  description = "Keycloak OIDC client ID for Exastro web (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "exastro_web_oidc_client_secret" {
  description = "Keycloak OIDC client secret for Exastro web (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "exastro_api_oidc_client_id" {
  description = "Keycloak OIDC client ID for Exastro API (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "exastro_api_oidc_client_secret" {
  description = "Keycloak OIDC client secret for Exastro API (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "odoo_oidc_client_id" {
  description = "Keycloak OIDC client ID for Odoo (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "odoo_oidc_client_secret" {
  description = "Keycloak OIDC client secret for Odoo (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_oidc_client_id" {
  description = "Keycloak OIDC client ID for GitLab (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_oidc_client_secret" {
  description = "Keycloak OIDC client secret for GitLab (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "grafana_oidc_client_id" {
  description = "Keycloak OIDC client ID for Grafana (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "grafana_oidc_client_secret" {
  description = "Keycloak OIDC client secret for Grafana (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "pgadmin_oidc_client_id" {
  description = "Keycloak OIDC client ID for pgAdmin (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "pgadmin_oidc_client_secret" {
  description = "Keycloak OIDC client secret for pgAdmin (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "local_image_dir" {
  description = "Local directory to store pulled Docker image tarballs (used by scripts)"
  type        = string
  default     = null
}

variable "aws_profile" {
  description = "Default AWS CLI profile to use in scripts"
  type        = string
  default     = null
}

variable "ecr_namespace" {
  description = "ECR repository namespace/prefix"
  type        = string
  default     = null
}

variable "ecr_repo_n8n" {
  description = "ECR repository name for n8n"
  type        = string
  default     = null
}

variable "ecr_repo_zulip" {
  description = "ECR repository name for Zulip"
  type        = string
  default     = null
}

variable "ecr_repo_sulu" {
  description = "ECR repository name for sulu"
  type        = string
  default     = null
}

variable "ecr_repo_sulu_nginx" {
  description = "ECR repository name for the Sulu nginx companion image"
  type        = string
  default     = null
}

variable "ecr_repo_gitlab" {
  description = "ECR repository name for GitLab Omnibus"
  type        = string
  default     = null
}

variable "ecr_repo_gitlab_runner" {
  description = "ECR repository name for GitLab Runner (shell executor)"
  type        = string
  default     = null
}

variable "ecr_repo_grafana" {
  description = "ECR repository name for Grafana"
  type        = string
  default     = null
}

variable "ecr_repo_keycloak" {
  description = "ECR repository name for Keycloak"
  type        = string
  default     = null
}

variable "ecr_repo_exastro_it_automation_web_server" {
  description = "ECR repository name for Exastro IT Automation web server"
  type        = string
  default     = null
}

variable "ecr_repo_exastro_it_automation_api_admin" {
  description = "ECR repository name for Exastro IT Automation API admin"
  type        = string
  default     = null
}

variable "ecr_repo_odoo" {
  description = "ECR repository name for Odoo"
  type        = string
  default     = null
}

variable "ecr_repo_pgadmin" {
  description = "ECR repository name for pgAdmin"
  type        = string
  default     = null
}

variable "ecr_repo_alpine" {
  description = "ECR repository name for shared Alpine base images (used by init/utility containers)"
  type        = string
  default     = null
}

variable "ecr_repo_redis" {
  description = "ECR repository name for shared Redis image"
  type        = string
  default     = null
}

variable "ecr_repo_memcached" {
  description = "ECR repository name for shared Memcached image"
  type        = string
  default     = null
}

variable "ecr_repo_rabbitmq" {
  description = "ECR repository name for shared RabbitMQ image"
  type        = string
  default     = null
}

variable "ecr_repo_mongo" {
  description = "ECR repository name for shared MongoDB image"
  type        = string
  default     = null
}

variable "ecr_repo_python" {
  description = "ECR repository name for shared Python base images"
  type        = string
  default     = null
}

variable "ecr_repo_qdrant" {
  description = "ECR repository name for Qdrant image (used by n8n sidecars)"
  type        = string
  default     = null
}

variable "ecr_repo_xray_daemon" {
  description = "ECR repository name for AWS X-Ray daemon image"
  type        = string
  default     = null
}

variable "n8n_image_tag" {
  description = "n8n image tag to use for pulls/builds"
  type        = string
  default     = null
}

variable "gitlab_omnibus_image_tag" {
  description = "GitLab Omnibus image tag to pull/build"
  type        = string
  default     = null
}

variable "gitlab_runner_image_tag" {
  description = "GitLab Runner image tag to pull/build (upstream tag, e.g. alpine-v17.11.7)"
  type        = string
  default     = "alpine-v17.11.7"
}

variable "sulu_image_tag" {
  description = "Shinsenter Sulu image tag used as the sulu foundation"
  type        = string
  default     = "3.0.3"
}

variable "sulu_db_name" {
  description = "Logical PostgreSQL database name used by sulu"
  type        = string
  default     = "sulu"
}

variable "sulu_db_username" {
  description = "Optional PostgreSQL username for sulu (falls back to the RDS master user)"
  type        = string
  default     = null
}

variable "sulu_share_dir" {
  description = "Filesystem path used as Sulu's share directory inside the container"
  type        = string
  default     = "/var/www/html/public/uploads/media"
}

variable "sulu_app_secret" {
  description = "Override APP_SECRET injected into the sulu task"
  type        = string
  sensitive   = false
  default     = null
}

variable "sulu_mailer_dsn" {
  description = "Override MAILER_DSN injected into the sulu task (defaults to SES credentials)"
  type        = string
  sensitive   = false
  default     = null
}

variable "sulu_admin_email" {
  description = "Sulu admin email (defaults to admin@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "sulu_sso_default_role_key" {
  description = "Default role key granted to Keycloak-single-sign-on users"
  type        = string
  default     = "ROLE_USER"
}

variable "keycloak_image_tag" {
  description = "Keycloak image tag to use for pulls/builds"
  type        = string
  default     = null
}

variable "odoo_image_tag" {
  description = "Odoo image tag to use for pulls/builds"
  type        = string
  default     = null
}

variable "pgadmin_image_tag" {
  description = "Image tag for pgAdmin"
  type        = string
  default     = null
}

variable "exastro_it_automation_web_server_image_tag" {
  description = "Exastro IT Automation web server image (repo:tag)"
  type        = string
  default     = null
}

variable "exastro_it_automation_api_admin_image_tag" {
  description = "Exastro IT Automation API admin image (repo:tag)"
  type        = string
  default     = null
}

variable "image_architecture" {
  description = "Container platform/architecture (e.g., linux/amd64, linux/arm64)"
  type        = string
  default     = null
}










variable "create_ecs" {
  type    = bool
  default = true
}

variable "ecs_task_additional_trust_principal_arns" {
  description = "Additional AWS principal ARNs allowed to sts:AssumeRole the ECS task role (useful for debugging)."
  type        = list(string)
  default     = []
}

variable "create_exastro_efs" {
  type    = bool
  default = true
}

variable "create_exastro" {
  description = "Whether to create Exastro IT Automation web + API admin resources"
  type        = bool
  default     = true
}

variable "create_exastro_api_admin" {
  description = "Deprecated: use create_exastro instead"
  type        = bool
  default     = null
}

variable "create_exastro_web_server" {
  description = "Deprecated: use create_exastro instead"
  type        = bool
  default     = null
}

variable "create_gitlab_config_efs" {
  type    = bool
  default = true
}

variable "create_gitlab_data_efs" {
  type    = bool
  default = true
}

variable "create_grafana_efs" {
  description = "Whether to create an EFS (One Zone) for Grafana persistent files"
  type        = bool
  default     = true
}

variable "create_keycloak_efs" {
  type    = bool
  default = true
}

variable "create_n8n_efs" {
  type    = bool
  default = true
}

variable "create_sulu_efs" {
  type    = bool
  default = true
}

variable "create_odoo_efs" {
  type    = bool
  default = true
}

variable "create_mysql_rds" {
  description = "Whether to create a dedicated MySQL RDS instance"
  type        = bool
  default     = false
}

variable "mysql_db_name" {
  description = "Database name for the dedicated MySQL RDS"
  type        = string
  default     = "appdb"
}

variable "mysql_db_username" {
  description = "Database username for the dedicated MySQL RDS"
  type        = string
  default     = "admin"
}

variable "mysql_db_password" {
  description = "Database password for the dedicated MySQL RDS (auto-generated when null)"
  type        = string
  sensitive   = false
  default     = null
}

variable "mysql_rds_skip_final_snapshot" {
  description = "When true, skip creating a final snapshot on MySQL RDS deletion"
  type        = bool
  default     = true
}

variable "create_pgadmin_efs" {
  type    = bool
  default = true
}

variable "create_ses" {
  description = "Whether to create SES domain identity/DKIM and Route53 records"
  type        = bool
  default     = true
}

variable "create_zulip_efs" {
  type    = bool
  default = true
}

variable "create_ssm_parameters" {
  description = "Whether this module should create/update SSM parameters (set false when external scripts manage SSM)"
  type        = bool
  default     = true
}

variable "pg_db_name" {
  type    = string
  default = "appDB"
}

variable "ecs_logs_retention_days" {
  type    = number
  default = 14
}

variable "enable_alb_access_logs" {
  description = "Whether to enable ALB access logs to S3."
  type        = bool
  default     = true
}

variable "alb_access_logs_bucket_name" {
  description = "S3 bucket name for ALB access logs (defaults to <name_prefix>-<region>-<account>-alb-logs)."
  type        = string
  default     = null
}

variable "alb_access_logs_prefix" {
  description = "S3 prefix for ALB access logs (defaults to alb/realm/<default_realm>)."
  type        = string
  default     = null
}

variable "alb_access_logs_retention_days" {
  description = "Retention days for ALB access log objects in S3."
  type        = number
  default     = 30
}

variable "enable_alb_access_logs_athena" {
  description = "Whether to create Glue catalog database/table for ALB access logs (Athena)."
  type        = bool
  default     = false
}

variable "alb_access_logs_glue_database_name" {
  description = "Glue database name for ALB access logs (defaults to <name_prefix>_alb_logs)."
  type        = string
  default     = null
}

variable "alb_access_logs_glue_table_name" {
  description = "Glue table name for ALB access logs (defaults to alb_access_logs)."
  type        = string
  default     = null
}

variable "enable_alb_access_logs_realm_sorter" {
  description = "Whether to enable Lambda sorting of ALB access logs into per-realm prefixes."
  type        = bool
  default     = false
}

variable "alb_access_logs_realm_sorter_source_prefix" {
  description = "S3 prefix to watch for ALB access logs before sorting."
  type        = string
  default     = "alb/realm/"
}

variable "alb_access_logs_realm_sorter_target_prefix" {
  description = "S3 prefix to store sorted ALB access logs per realm."
  type        = string
  default     = "alb"
}

variable "alb_access_logs_realm_sorter_delete_source" {
  description = "Whether to delete original ALB access logs after sorting."
  type        = bool
  default     = false
}

variable "enable_logs_to_s3" {
  description = "Services to ship CloudWatch Logs to S3 via Firehose (sulu only)."
  type = list(object({
    service = string
    enabled = bool
  }))
  default = []

  validation {
    condition     = length(distinct([for entry in var.enable_logs_to_s3 : entry.service])) == length(var.enable_logs_to_s3)
    error_message = "enable_logs_to_s3 must not contain duplicate service names."
  }

  validation {
    condition = alltrue([
      for entry in var.enable_logs_to_s3 :
      entry.service == "sulu"
    ])
    error_message = "enable_logs_to_s3 must contain only sulu."
  }
}

variable "n8n_logs_bucket_name" {
  description = "S3 bucket name for n8n CloudWatch Logs (defaults to <name_prefix>-<region>-<account>-n8n-logs)."
  type        = string
  default     = null
}

variable "n8n_logs_prefix" {
  description = "S3 prefix for n8n logs via Firehose."
  type        = string
  default     = null
}

variable "n8n_logs_error_prefix" {
  description = "S3 error prefix for n8n logs via Firehose."
  type        = string
  default     = null
}

variable "n8n_logs_retention_days" {
  description = "Retention days for n8n log objects in S3."
  type        = number
  default     = 30
}

variable "n8n_logs_subscription_filter_pattern" {
  description = "CloudWatch Logs subscription filter pattern for n8n logs (empty means all events)."
  type        = string
  default     = ""
}

variable "grafana_logs_bucket_name" {
  description = "S3 bucket name for Grafana CloudWatch Logs (defaults to <name_prefix>-<region>-<account>-grafana-logs)."
  type        = string
  default     = null
}

variable "grafana_logs_prefix" {
  description = "S3 prefix for Grafana logs via Firehose."
  type        = string
  default     = null
}

variable "grafana_logs_error_prefix" {
  description = "S3 error prefix for Grafana logs via Firehose."
  type        = string
  default     = null
}

variable "grafana_logs_retention_days" {
  description = "Retention days for Grafana log objects in S3."
  type        = number
  default     = 30
}

variable "grafana_logs_subscription_filter_pattern" {
  description = "CloudWatch Logs subscription filter pattern for Grafana logs (empty means all events)."
  type        = string
  default     = ""
}

variable "service_logs_retention_days" {
  description = "Retention days for service log objects in S3 (generic services)."
  type        = number
  default     = 30
}

variable "service_logs_subscription_filter_pattern" {
  description = "CloudWatch Logs subscription filter pattern for service logs (generic services)."
  type        = string
  default     = ""
}

variable "enable_service_logs_athena" {
  description = "Whether to create Glue catalog database/tables for service logs in S3."
  type        = bool
  default     = false
}

variable "service_logs_glue_database_name" {
  description = "Glue database name for service logs (defaults to <name_prefix>_service_logs)."
  type        = string
  default     = null
}

variable "xray_services" {
  description = "ECS services to enable X-Ray sidecar/ALB tracing for."
  type        = list(string)
  default     = ["n8n", "grafana"]
}

variable "xray_sampling_rate" {
  description = "X-Ray sampling rate (1.0 means sample all)."
  type        = number
  default     = 1.0
}

variable "xray_retention_days" {
  description = "Requested X-Ray retention days (AWS X-Ray currently retains 30 days)."
  type        = number
  default     = 90
}

variable "ecs_task_cpu" {
  type    = number
  default = 512
}

variable "ecs_task_memory" {
  type    = number
  default = 1024
}

variable "exastro_task_cpu" {
  description = "Override CPU units for Exastro task definition (null to use ecs_task_cpu)"
  type        = number
  default     = null
}

variable "exastro_task_memory" {
  description = "Override memory (MB) for Exastro task definition (null to use ecs_task_memory)"
  type        = number
  default     = null
}

variable "sulu_task_cpu" {
  description = "Override CPU units for sulu task definition (null to use ecs_task_cpu)"
  type        = number
  default     = null
}

variable "sulu_task_memory" {
  description = "Override memory (MB) for sulu task definition (null to use ecs_task_memory)"
  type        = number
  default     = null
}

variable "keycloak_task_cpu" {
  description = "Override CPU units for Keycloak task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 512
}

variable "keycloak_task_memory" {
  description = "Override memory (MB) for Keycloak task definition (null to use ecs_task_memory)"
  type        = number
  default     = 1024
}

variable "pgadmin_task_cpu" {
  description = "Override CPU units for pgAdmin task definition (null to use ecs_task_cpu)"
  type        = number
  default     = null
}

variable "pgadmin_task_memory" {
  description = "Override memory (MB) for pgAdmin task definition (null to use ecs_task_memory)"
  type        = number
  default     = null
}

variable "enable_zulip_alb_oidc" {
  description = "Whether to protect Zulip behind ALB OIDC authentication (Keycloak)"
  type        = bool
  default     = false
  validation {
    condition = var.enable_zulip_alb_oidc == false ? true : (
      var.zulip_oidc_idps_yaml != null
      && alltrue([
        for realm in var.realms : contains(keys(tomap(yamldecode(var.zulip_oidc_idps_yaml))), "keycloak_${realm}")
      ])
    )
    error_message = "When enable_zulip_alb_oidc is true, set zulip_oidc_idps_yaml and include a keycloak_<realm> entry for every value in realms."
  }
}

variable "n8n_task_cpu" {
  description = "Override CPU units for n8n task definition (null to use ecs_task_cpu)"
  type        = number
  default     = null
}

variable "n8n_task_memory" {
  description = "Override memory (MB) for n8n task definition (null to use ecs_task_memory)"
  type        = number
  default     = null
}

variable "zulip_task_cpu" {
  description = "Override CPU units for Zulip task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 2048
}

variable "zulip_task_memory" {
  description = "Override memory (MB) for Zulip task definition (null to use ecs_task_memory)"
  type        = number
  default     = 4096
}

variable "odoo_task_cpu" {
  description = "Override CPU units for Odoo task definition (null to use ecs_task_cpu)"
  type        = number
  default     = null
}

variable "odoo_task_memory" {
  description = "Override memory (MB) for Odoo task definition (null to use ecs_task_memory)"
  type        = number
  default     = null
}




variable "enable_ses_smtp_auto" {
  type    = bool
  default = true
}

variable "exastro_api_admin_environment" {
  description = "Environment variables for Exastro IT Automation API admin container"
  type        = map(string)
  default     = null
}

variable "exastro_common_environment" {
  description = "Common environment variables to inject into Exastro containers"
  type        = map(string)
  default = {
    "TZ" : "Asia/Tokyo"
  }
}

variable "exastro_api_admin_secrets" {
  description = "Secrets (name/valueFrom) for Exastro API admin container"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "exastro_api_admin_ssm_params" {
  description = "SSM params to inject into Exastro API admin"
  type        = map(string)
  default     = {}
}

variable "exastro_filesystem_path" {
  type    = string
  default = "/exastro/share"
}

variable "exastro_ita_db_name" {
  description = "Database name for Exastro ITA Application DB"
  type        = string
  default     = "itadb"
}

variable "exastro_pf_db_name" {
  description = "Database name for Exastro ITA Platform DB"
  type        = string
  default     = "pfdb"
}

variable "exastro_web_server_environment" {
  description = "Environment variables for Exastro IT Automation web server container"
  type        = map(string)
  default     = {}
}

variable "exastro_web_server_secrets" {
  description = "Secrets (name/valueFrom) for Exastro web server container"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "exastro_web_server_ssm_params" {
  description = "SSM params to inject into Exastro web server"
  type        = map(string)
  default     = {}
}

variable "gitlab_config_bind_paths" {
  type = list(string)
  default = [
    "/etc/gitlab",
    "/etc/letsencrypt"
  ]
}

variable "gitlab_config_mount_base" {
  type    = string
  default = "/mnt/gitlab-config"
}

variable "gitlab_data_filesystem_path" {
  type    = string
  default = "/var/opt/gitlab"
}

variable "gitlab_data_access_point_id" {
  description = "Optional Access Point ID to mount GitLab data EFS with the correct POSIX user."
  type        = string
  default     = null
}

variable "gitlab_config_access_point_id" {
  description = "Optional Access Point ID to mount GitLab config EFS with the correct POSIX user."
  type        = string
  default     = null
}

variable "gitlab_data_access_point_root_path" {
  description = "POSIX path that the GitLab data Access Point exposes as its root."
  type        = string
  default     = "/gitlab-data"
}

variable "gitlab_config_access_point_root_path" {
  description = "POSIX path that the GitLab config Access Point exposes as its root."
  type        = string
  default     = "/gitlab-config"
}

variable "gitlab_data_access_point_uid" {
  description = "UID that ECS tasks should use when mounting the GitLab data EFS Access Point (defaults to 998 when unset)."
  type        = number
  default     = null
}

variable "gitlab_data_access_point_gid" {
  description = "GID that ECS tasks should use when mounting the GitLab data EFS Access Point (defaults to 998 when unset)."
  type        = number
  default     = null
}

variable "gitlab_config_access_point_uid" {
  description = "UID that ECS tasks should use when mounting the GitLab config EFS Access Point (defaults to 0 when unset)."
  type        = number
  default     = null
}

variable "gitlab_config_access_point_gid" {
  description = "GID that ECS tasks should use when mounting the GitLab config EFS Access Point (defaults to 0 when unset)."
  type        = number
  default     = null
}

variable "gitlab_access_point_uid" {
  description = "Deprecated: use gitlab_data_access_point_uid or gitlab_config_access_point_uid."
  type        = number
  default     = null
}

variable "gitlab_access_point_gid" {
  description = "Deprecated: use gitlab_data_access_point_gid or gitlab_config_access_point_gid."
  type        = number
  default     = null
}

variable "gitlab_access_point_permissions" {
  description = "Ownership/permissions to apply when creating the GitLab EFS Access Point root."
  type        = string
  default     = "0755"
}

variable "gitlab_db_name" {
  description = "Logical database name used by GitLab Omnibus"
  type        = string
  default     = "gitlabhq_production"
}

variable "gitlab_db_ssm_params" {
  type        = map(string)
  description = "SSM params for GitLab DB connectivity (host/port/name/user/password)"
  default     = null
}

variable "gitlab_environment" {
  type    = map(string)
  default = null
}

variable "gitlab_health_check_grace_period_seconds" {
  description = "Grace period for GitLab ECS service load balancer health checks (seconds)"
  type        = number
  default     = 900
}

variable "gitlab_secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "gitlab_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to reach GitLab SSH (port 22); leave empty to disable."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "gitlab_ssh_port" {
  description = "Public SSH port for GitLab (NLB listener); defaults to 2222."
  type        = number
  default     = 2222
}

variable "gitlab_ssh_host" {
  description = "Hostname for GitLab SSH access (defaults to gitlab-ssh.<hosted_zone_name>)."
  type        = string
  default     = null
}

variable "gitlab_ssm_params" {
  type    = map(string)
  default = null
}

variable "gitlab_task_cpu" {
  description = "CPU units for GitLab task definition (default 4 vCPU)"
  type        = number
  default     = 4096
}

variable "gitlab_task_memory" {
  description = "Memory (MB) for GitLab task definition"
  type        = number
  default     = 16384
}

variable "grafana_db_name" {
  description = "Logical database name used by Grafana"
  type        = string
  default     = "grafana"
}

variable "grafana_athena_output_bucket_name" {
  description = "S3 bucket name for Grafana Athena query results"
  type        = string
  default     = null
}

variable "grafana_db_ssm_params" {
  description = "SSM params for Grafana DB connectivity (host/port/name/user/password)"
  type        = map(string)
  default     = null
}

variable "grafana_admin_username" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "grafana_root_url" {
  description = "Grafana root URL (defaults to https://<grafana host>/)"
  type        = string
  default     = null
}

variable "grafana_domain" {
  description = "Grafana server domain (defaults to grafana host)"
  type        = string
  default     = null
}

variable "grafana_serve_from_sub_path" {
  description = "Whether Grafana should serve from a sub-path"
  type        = bool
  default     = false
}

variable "grafana_environment" {
  description = "Environment variables for Grafana container"
  type        = map(string)
  default     = null
}

variable "grafana_filesystem_path" {
  description = "Base container path to mount persistent volume for Grafana (realm subdirectories are created under this path)"
  type        = string
  default     = "/var/lib/grafana"
}

variable "grafana_secrets" {
  description = "Secrets (name/valueFrom) for Grafana container"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "grafana_ssm_params" {
  description = "SSM params specific to Grafana"
  type        = map(string)
  default     = null
  validation {
    condition = var.grafana_ssm_params == null ? true : alltrue([
      for v in values(var.grafana_ssm_params) : can(regex("^arn:aws:ssm:", v)) || startswith(v, "/")
    ])
    error_message = "grafana_ssm_params の値は SSM パス（/xxx）または SSM ARN を指定してください。平文値を渡したい場合は grafana_environment を使ってください。"
  }
}

variable "image_architecture_cpu" {
  type    = string
  default = "X86_64"
}

variable "keycloak_admin_username" {
  description = "Keycloak admin username (SecureString in SSM when set; defaults to admin)"
  type        = string
  default     = "admin"
}

variable "keycloak_db_name" {
  description = "Logical database name used by Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_db_ssm_params" {
  description = "SSM params for Keycloak DB connectivity (host/port/name/user/password/url)"
  type        = map(string)
  default     = null
}

variable "keycloak_environment" {
  type = map(string)
  default = {
    "KC_PROXY" : "edge",
    "KC_PROXY_HEADERS" : "xforwarded",
    "KC_HTTP_ENABLED" : "true",
    "KC_HOSTNAME_STRICT" : "false",
    "KC_HOSTNAME_STRICT_HTTPS" : "false",
    "KC_METRICS_ENABLED" : "false",
    "KC_HEALTH_ENABLED" : "true",
    "KC_FEATURES" : "token-exchange"
  }
}

variable "keycloak_filesystem_path" {
  type    = string
  default = "/opt/keycloak/data"
}

variable "keycloak_secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "keycloak_ssm_params" {
  description = "SSM params specific to Keycloak (overrides defaults)"
  type        = map(string)
  default     = null
}

variable "sulu_environment" {
  type    = map(string)
  default = {}
}

variable "sulu_secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "n8n_db_name" {
  type    = string
  default = "n8napp"
}

variable "n8n_encryption_key" {
  description = "n8n encryption key(s). Prefer map(string) by realm; legacy string is also accepted and will be used for all realms."
  type        = any
  sensitive   = true
  default     = null
}

variable "n8n_db_ssm_params" {
  description = "SSM params for n8n DB connectivity (host/port/name)"
  type        = map(string)
  default     = null
}

variable "n8n_db_username" {
  type    = string
  default = "n8nuser"
}

variable "n8n_db_postgresdb_pool_size" {
  description = "n8n Postgres connection pool size (DB_POSTGRESDB_POOL_SIZE)"
  type        = number
  default     = 2
}

variable "n8n_db_postgresdb_connection_timeout" {
  description = "n8n Postgres connection timeout ms (DB_POSTGRESDB_CONNECTION_TIMEOUT)"
  type        = number
  default     = 20000
}

variable "n8n_db_postgresdb_idle_connection_timeout" {
  description = "n8n Postgres idle connection eviction timeout ms (DB_POSTGRESDB_IDLE_CONNECTION_TIMEOUT)"
  type        = number
  default     = 30000
}

variable "n8n_db_ping_interval_seconds" {
  description = "n8n DB ping interval seconds (DB_PING_INTERVAL_SECONDS)"
  type        = number
  default     = 2
}

variable "aiops_agent_environment" {
  type = map(map(string))
  default = {
    default = {
      "N8N_SMTP_HOST" : "email-smtp.ap-northeast-1.amazonaws.com",
      "N8N_SMTP_PORT" : "587",
      "N8N_SMTP_SSL" : "false",
      "N8N_DEBUG_LOG" : "false"
    }
  }
}

variable "aiops_s3_bucket_names" {
  description = "Optional map of AIOPS S3 bucket names by realm (realm => bucket_name)."
  type        = map(string)
  default     = {}
}

variable "aiops_s3_bucket_parameter_name_prefix" {
  description = "SSM parameter prefix for N8N_S3_BUCKET (defaults to /<name_prefix>/n8n/aiops/s3_bucket/)."
  type        = string
  default     = null
}

variable "aiops_s3_prefix" {
  description = "Default S3 prefix used by AIOps workflows (N8N_S3_PREFIX)."
  type        = string
  default     = "itsm/customer_request"
}

variable "aiops_s3_prefix_parameter_name" {
  description = "SSM parameter name for N8N_S3_PREFIX."
  type        = string
  default     = null
}

variable "aiops_gitlab_first_contact_done_label" {
  description = "Default GitLab label used when first contact is completed (N8N_GITLAB_FIRST_CONTACT_DONE_LABEL)."
  type        = string
  default     = "一次対応：完了"
}

variable "aiops_gitlab_escalation_label" {
  description = "Default GitLab label used when escalation is needed (N8N_GITLAB_ESCALATION_LABEL)."
  type        = string
  default     = "一次対応：エスカレーション"
}

variable "aiops_gitlab_first_contact_done_label_parameter_name" {
  description = "SSM parameter name for N8N_GITLAB_FIRST_CONTACT_DONE_LABEL."
  type        = string
  default     = null
}

variable "aiops_gitlab_escalation_label_parameter_name" {
  description = "SSM parameter name for N8N_GITLAB_ESCALATION_LABEL."
  type        = string
  default     = null
}

variable "n8n_filesystem_path" {
  type    = string
  default = "/home/node/.n8n"
}

variable "n8n_secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "n8n_shell_path" {
  type    = string
  default = "/bin/ash"
}

variable "aiops_ingest_rate_limit_rps" {
  type    = number
  default = 2
}

variable "aiops_ingest_burst_rps" {
  type    = number
  default = 5
}

variable "aiops_tenant_rate_limit_rps" {
  type    = number
  default = 2
}

variable "aiops_ingest_payload_max_bytes" {
  type    = number
  default = 1048576
}

variable "aiops_workflows_token" {
  description = "Override value for the workflow catalog token (if omitted, Terraform generates one)"
  type        = string
  default     = null
}

variable "aiops_workflows_token_parameter_name" {
  description = "SSM parameter name where the workflow catalog token is stored"
  type        = string
  default     = null
}

variable "n8n_api_key" {
  description = "Public API key for n8n (if provided, Terraform stores it in SSM)"
  type        = string
  default     = null
}

variable "n8n_api_key_parameter_name" {
  description = "SSM parameter name used to read/store the n8n API key"
  type        = string
  default     = null
}

variable "n8n_admin_email" {
  description = <<-DESC
    Admin user email used when logging into n8n to bootstrap the API key (e.g., "admin@example.com").
    If left null, the email configured in the environment (N8N_ADMIN_EMAIL) will be used instead.
  DESC
  type        = string
  default     = null
}

variable "n8n_admin_password" {
  description = <<-DESC
    Admin user password used to authenticate to n8n when generating the API key.
    Set this to the desired admin password.  When null or empty the bootstrap logic is skipped.
  DESC
  type        = string
  default     = null
}

variable "openai_model_api_key_parameter_name" {
  description = "SSM parameter name to store the OpenAI-compatible API key."
  type        = string
  default     = null
}

variable "enable_ssm_key_expiry_checker" {
  description = "Enable scheduled checker that alerts on near-expiry SecureString parameters under /<name_prefix>/"
  type        = bool
  default     = true
}

variable "ssm_key_expiry_sns_email" {
  description = "SNS email endpoint to receive expiry alerts (subscription requires manual confirmation)"
  type        = string
  default     = null
}

variable "ssm_key_expiry_max_age_days" {
  description = "Max age in days used to compute expires_at from LastModifiedDate when expires_at tag is missing"
  type        = number
  default     = 90
}

variable "ssm_key_expiry_warn_days" {
  description = "Warn when expires_at is within this many days"
  type        = number
  default     = 30
}

variable "ssm_key_expiry_schedule_expression" {
  description = "EventBridge schedule expression for expiry checker"
  type        = string
  default     = "rate(1 day)"
}

variable "ssm_key_expiry_manage_expires_at_tag" {
  description = "If true, checker Lambda writes/updates expires_at tag on SecureString parameters"
  type        = bool
  default     = true
}

variable "oase_db_name" {
  description = "Logical database name used by Exastro OASE"
  type        = string
  default     = "OASE_DB"
}

variable "odoo_db_name" {
  description = "Logical database name used by Odoo"
  type        = string
  default     = "odooapp"
}

variable "odoo_environment" {
  type    = map(string)
  default = null
}

variable "odoo_filesystem_path" {
  type    = string
  default = "/var/lib/odoo"
}

variable "odoo_secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "odoo_ssm_params" {
  description = "SSM params specific to Odoo DB/auth (overrides defaults)"
  type        = map(string)
  default     = null
}

variable "mysql_rds_allocated_storage" {
  description = "Allocated storage (GB) for MySQL RDS"
  type        = number
  default     = 20
}

variable "mysql_rds_backup_retention" {
  description = "Backup retention days for MySQL RDS"
  type        = number
  default     = 1
}

variable "mysql_rds_engine_version" {
  description = "MySQL engine version for MySQL RDS"
  type        = string
  default     = "8.0"
}

variable "mysql_rds_instance_class" {
  description = "RDS instance class for MySQL"
  type        = string
  default     = "db.t3.micro"
}

variable "pgadmin_email" {
  description = "pgAdmin default admin email (defaults to admin@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "pgadmin_default_sender" {
  description = "pgAdmin default sender address (defaults to no-reply@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "pgadmin_environment" {
  description = "Environment variables for pgAdmin container"
  type        = map(string)
  default     = null
}

variable "pgadmin_filesystem_path" {
  type    = string
  default = "/var/lib/pgadmin"
}

variable "pgadmin_secrets" {
  description = "Secrets (name/valueFrom) for pgAdmin container"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "pgadmin_ssm_params" {
  description = "SSM params specific to pgAdmin (e.g., default password)"
  type        = map(string)
  default     = null
  validation {
    condition = var.pgadmin_ssm_params == null ? true : alltrue([
      for v in values(var.pgadmin_ssm_params) : can(regex("^arn:aws:ssm:", v)) || startswith(v, "/")
    ])
    error_message = "pgadmin_ssm_params の値は SSM パス（/xxx）または SSM ARN を指定してください。平文値を渡したい場合は pgadmin_environment を使ってください。"
  }
}

variable "enable_aiops_cloudwatch_alarm_sns" {
  description = "Whether to publish CloudWatch alarms to an SNS topic with an HTTPS subscription to n8n."
  type        = bool
  default     = false
}

variable "aiops_cloudwatch_alarm_sns_webhook_url" {
  description = "HTTPS endpoint (n8n webhook) to receive CloudWatch alarm SNS notifications."
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_sulu_updown_alarm" {
  description = "Whether to create a CloudWatch alarm for Sulu up/down (ALB target group UnHealthyHostCount) and stopped state (DesiredTaskCount=0). In this stack, DesiredTaskCount is read from ECS/ContainerInsights (Container Insights). Requires enable_aiops_cloudwatch_alarm_sns."
  type        = bool
  default     = false
}

variable "service_control_api_base_url" {
  description = "Base URL for the service control API (if externally provided)"
  type        = string
  default     = null
}

variable "service_control_jwt_issuer" {
  description = "JWT issuer URL for service control API (Keycloak realm URL, e.g. https://keycloak.example.com/realms/main)"
  type        = string
  default     = null
}

variable "service_control_jwt_audiences" {
  description = "JWT audiences for service control API authorizer (Keycloak client IDs)"
  type        = list(string)
  default     = []
}

variable "service_control_ui_client_id" {
  description = "OIDC client ID for service control UI (public client; PKCE)"
  type        = string
  default     = "service-control-ui"
}

variable "service_control_oidc_client_id" {
  description = "OIDC client ID for service control API access from n8n (stored in SSM when set)"
  type        = string
  sensitive   = false
  default     = null
}

variable "service_control_oidc_client_secret" {
  description = "OIDC client secret for service control API access from n8n (stored in SSM when set)"
  type        = string
  sensitive   = true
  default     = null
}

variable "service_control_oidc_client_id_parameter_name" {
  description = "Existing SSM parameter name/ARN for service control OIDC client ID"
  type        = string
  default     = null
}

variable "service_control_oidc_client_secret_parameter_name" {
  description = "Existing SSM parameter name/ARN for service control OIDC client secret"
  type        = string
  default     = null
}

variable "enable_control_site_oidc_auth" {
  description = "Enable OIDC auth for the control site via CloudFront + Lambda@Edge"
  type        = bool
  default     = false
}

variable "control_site_auth_allowed_group" {
  description = "Keycloak group name allowed to access the control site"
  type        = string
  default     = "Admins"
}

variable "control_site_auth_callback_path" {
  description = "Callback path used by the control site OIDC flow"
  type        = string
  default     = "/__auth/callback"
}

variable "control_site_auth_edge_replica_cleanup_wait" {
  description = "Wait duration after CloudFront disassociation/deletion before deleting the Lambda@Edge function (e.g., 20m, 30m)"
  type        = string
  default     = "20m"
}

variable "tags" {
  type    = map(string)
  default = null
}

variable "waf_enable" {
  type    = bool
  default = true
}

variable "waf_geo_country_codes" {
  type = list(string)
  default = [
    "JP",
    "VN"
  ]
}

variable "waf_log_retention_in_days" {
  type    = number
  default = 30
}

variable "zulip_db_name" {
  type    = string
  default = "zulip"
}

variable "zulip_db_ssm_params" {
  description = "SSM params for Zulip DB connectivity (host/port/name)"
  type        = map(string)
  default     = null
}

variable "zulip_db_username" {
  type    = string
  default = "zulipuser"
}

variable "zulip_environment" {
  type = map(string)
  default = {
    SSL_CERTIFICATE_GENERATION = "self-signed"
    DISABLE_HTTPS              = "True"
    SETTING_RABBITMQ_USE_TLS   = "False"
    RABBITMQ_USE_TLS           = "False"
    ALB_OIDC_AUTO_CREATE_USERS = "True"
  }
}

variable "zulip_missing_dictionaries" {
  description = "Set postgresql.missing_dictionaries for Zulip (useful on managed PostgreSQL like RDS without hunspell dictionaries)"
  type        = bool
  default     = true
}

variable "zulip_trusted_proxy_cidrs" {
  description = "List of IP ranges that should be trusted as reverse proxies for Zulip (ALB private CIDRs)."
  type        = list(string)
  default     = null
}

variable "zulip_filesystem_path" {
  type    = string
  default = "/data"
}

variable "zulip_image_tag" {
  description = "Zulip image tag to pull/build"
  type        = string
  default     = null
}

variable "zulip_memcached_node_type" {
  description = "ElastiCache node type for Zulip Memcached"
  type        = string
  default     = "cache.t4g.micro"
}

variable "zulip_memcached_nodes" {
  description = "Number of cache nodes for Zulip Memcached cluster"
  type        = number
  default     = 1
}

variable "zulip_memcached_parameter_group" {
  description = "ElastiCache Memcached parameter group name"
  type        = string
  default     = "default.memcached1.6"
}

variable "zulip_mq_deployment_mode" {
  description = "Deployment mode for Amazon MQ broker"
  type        = string
  default     = "SINGLE_INSTANCE"
}

variable "zulip_mq_engine_version" {
  description = "Amazon MQ RabbitMQ engine version for Zulip"
  type        = string
  default     = "3.13"
}

variable "zulip_mq_instance_type" {
  description = "Amazon MQ host instance type for Zulip (RabbitMQ)"
  type        = string
  default     = "mq.t3.micro"
}

variable "zulip_mq_port" {
  description = "Listener port for Amazon MQ (RabbitMQ) broker"
  type        = number
  default     = 5672
}

variable "zulip_mq_username" {
  description = "Username for Amazon MQ (RabbitMQ) broker used by Zulip"
  type        = string
  default     = "zulip"
}

variable "zulip_redis_engine_version" {
  description = "ElastiCache Redis engine version for Zulip"
  type        = string
  default     = "7.1"
}

variable "zulip_redis_maintenance_window" {
  description = "Preferred maintenance window for Zulip Redis (UTC cron window)"
  type        = string
  default     = "sun:18:00-sun:19:00"
}

variable "zulip_redis_node_type" {
  description = "ElastiCache node type for Zulip Redis"
  type        = string
  default     = "cache.t4g.micro"
}

variable "zulip_redis_parameter_group" {
  description = "ElastiCache Redis parameter group name"
  type        = string
  default     = "default.redis7"
}

variable "zulip_secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "zulip_ssm_params" {
  type    = map(string)
  default = null
}
