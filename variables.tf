# General infrastructure settings

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-northeast-1"
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

variable "tags" {
  description = "Additional tags applied to AWS resources"
  type        = map(string)
  default     = null
}

variable "hosted_zone_name" {
  description = "Hosted zone name to manage"
  type        = string
  default     = "smic-aiops.jp"
}

variable "name_prefix" {
  description = "Prefix used for naming resources (defaults to prod-aiops); also used when constructing default SSM parameter paths"
  type        = string
  default     = "prod-aiops"
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC"
  type        = string
  default     = "172.24.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnets with name, cidr, and az"
  type = list(object({
    name = string
    cidr = string
    az   = string
  }))
  default = [
    {
      name = "prod-aiops-public-1a"
      cidr = "172.24.0.0/20"
      az   = "ap-northeast-1a"
    },
    {
      name = "prod-aiops-public-1d"
      cidr = "172.24.16.0/20"
      az   = "ap-northeast-1d"
    }
  ]
}

variable "private_subnets" {
  description = "List of private subnets with name, cidr, and az"
  type = list(object({
    name = string
    cidr = string
    az   = string
  }))
  default = [
    {
      name = "prod-aiops-private-1a"
      cidr = "172.24.32.0/20"
      az   = "ap-northeast-1a"
    },
    {
      name = "prod-aiops-private-1d"
      cidr = "172.24.48.0/20"
      az   = "ap-northeast-1d"
    }
  ]
}

variable "n8n_filesystem_id" {
  description = "Existing EFS ID to mount for n8n (prevents creating/replacing the managed EFS)"
  type        = string
  default     = null
}

variable "keycloak_base_url" {
  description = "Base URL for Keycloak admin endpoint (defaults to https://keycloak.<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "default_realm" {
  description = "Keycloak realm used for service logins when Keycloak is deployed via this repo (defaults to name_prefix)"
  type        = string
  default     = "master"
}

variable "enable_zulip_alb_oidc" {
  description = "Whether to protect Zulip behind ALB OIDC authentication (Keycloak)"
  type        = bool
  default     = false
}

variable "realms" {
  description = "List of realm names used by scripts/tools (optional; does not affect infra unless explicitly wired)"
  type        = list(string)
  default     = ["master"]
}

variable "multi_realm_services" {
  description = "Services that support multi-realm provisioning (tfvars-only list; used by scripts/tools)"
  type        = list(string)
  default     = ["sulu", "odoo", "gitlab", "zulip", "exastro", "grafana"]
}

variable "none_realm_services" {
  description = "Services that do not require realms (tfvars-only list; used by scripts/tools)"
  type        = list(string)
  default     = ["n8n", "keycloak"]
}

variable "single_realm_services" {
  description = "Services that use a single shared realm (tfvars-only list; used by scripts/tools)"
  type        = list(string)
  default     = ["service-control", "service-control-ui", "pgadmin"]
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

variable "existing_vpc_id" {
  description = "If set, use this existing VPC instead of creating a new one"
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

variable "s3_endpoint_route_table_ids" {
  description = "Route table IDs to associate with the S3 gateway endpoint (defaults to managed private route tables)"
  type        = list(string)
  default     = null
}

variable "manage_existing_efs" {
  description = "Allow managing existing EFS with the expected Name tag (requires terraform import first)"
  type        = bool
  default     = true
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

variable "rds_backup_retention" {
  description = "Backup retention days for PostgreSQL RDS"
  type        = number
  default     = 1
}

variable "rds_max_locks_per_transaction" {
  description = "PostgreSQL max_locks_per_transaction for the RDS parameter group"
  type        = number
  default     = 512
}

variable "rds_log_connections" {
  description = "When true, enable PostgreSQL log_connections in the RDS parameter group"
  type        = bool
  default     = true
}

variable "rds_log_disconnections" {
  description = "When true, enable PostgreSQL log_disconnections in the RDS parameter group"
  type        = bool
  default     = true
}

variable "rds_performance_insights_enabled" {
  description = "When true, enable Performance Insights for PostgreSQL RDS"
  type        = bool
  default     = true
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

variable "n8n_db_postgresdb_pool_size" {
  description = "n8n Postgres connection pool size (DB_POSTGRESDB_POOL_SIZE)"
  type        = number
  default     = 2
}

variable "n8n_db_postgresdb_connection_timeout" {
  description = "n8n Postgres connection timeout ms (DB_POSTGRESDB_CONNECTION_TIMEOUT)"
  type        = number
  default     = 60000
}

variable "n8n_db_postgresdb_idle_connection_timeout" {
  description = "n8n Postgres idle connection eviction timeout ms (DB_POSTGRESDB_IDLE_CONNECTION_TIMEOUT)"
  type        = number
  default     = 60000
}

variable "n8n_db_ping_interval_seconds" {
  description = "n8n DB ping interval seconds (DB_PING_INTERVAL_SECONDS)"
  type        = number
  default     = 2
}

variable "pg_db_password" {
  description = "Master password for the PostgreSQL instance"
  type        = string
  sensitive   = true
  default     = null
}

variable "image_architecture" {
  description = "Container platform/architecture (e.g., linux/amd64, linux/arm64)"
  type        = string
  default     = "linux/amd64"
}

variable "local_image_dir" {
  description = "Local directory to store pulled Docker image tarballs (used by scripts)"
  type        = string
  default     = "./images"
}

variable "aws_profile" {
  description = "Default AWS CLI profile to use in scripts"
  type        = string
  default     = "Admin-AIOps"
}

variable "ecr_namespace" {
  description = "ECR repository namespace/prefix"
  type        = string
  default     = "aiops"
}

variable "ecr_repo_alpine" {
  description = "ECR repository name for shared Alpine base images (used by init/utility containers)"
  type        = string
  default     = "alpine"
}

variable "ecr_repo_redis" {
  description = "ECR repository name for shared Redis image"
  type        = string
  default     = "redis"
}

variable "ecr_repo_memcached" {
  description = "ECR repository name for shared Memcached image"
  type        = string
  default     = "memcached"
}

variable "ecr_repo_rabbitmq" {
  description = "ECR repository name for shared RabbitMQ image"
  type        = string
  default     = "rabbitmq"
}

variable "ecr_repo_mongo" {
  description = "ECR repository name for shared MongoDB image"
  type        = string
  default     = "mongo"
}

variable "ecr_repo_python" {
  description = "ECR repository name for shared Python base images"
  type        = string
  default     = "python"
}

variable "ecr_repo_qdrant" {
  description = "ECR repository name for Qdrant image (used by n8n sidecars)"
  type        = string
  default     = "qdrant"
}

variable "ecr_repo_xray_daemon" {
  description = "ECR repository name for AWS X-Ray daemon image"
  type        = string
  default     = "xray-daemon"
}

variable "create_ssm_parameters" {
  description = "Whether modules/stack should create/update SSM parameters (set false when managed by external scripts)"
  type        = bool
  default     = true
}

variable "aiops_workflows_token_parameter_name" {
  description = "SSM path to store the workflow catalog token for n8n (defaults to /<name_prefix>/aiops/workflows/token)"
  type        = string
  default     = null
}

variable "aiops_n8n_activate" {
  description = "Default value for N8N_ACTIVATE when running deploy_workflows.sh"
  type        = bool
  default     = true
}

variable "aiops_n8n_agent_realms" {
  description = "Realm list used to decide where to install AIOps Agent in n8n (empty means no targeting)."
  type        = list(string)
  default     = []
}

variable "n8n_api_key_parameter_name" {
  description = "SSM path to read/store the n8n API key used by workflow catalog endpoints (defaults to /<name_prefix>/n8n/api_key)"
  type        = string
  default     = null
}

variable "n8n_api_key" {
  description = "Override the n8n API key (if set, Terraform will not read it from SSM)"
  type        = string
  sensitive   = true
  default     = null
}

variable "n8n_api_keys_by_realm" {
  description = "Override n8n API keys per realm (stored in tfvars for script use)"
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "n8n_admin_email" {
  description = <<EOF
    Admin user email used when bootstrapping the n8n API key (e.g., "admin@example.com").
    If left null, the email configured in the environment (N8N_ADMIN_EMAIL) will be used instead.
  EOF
  type        = string
  default     = null
}

variable "n8n_admin_password" {
  description = <<EOF
    Admin password used when bootstrapping the n8n API key via scripts.
    When null, the API key bootstrap and SSM lookup skip so the pipeline can start without that secret.
  EOF
  type        = string
  sensitive   = true
  default     = null
}

variable "n8n_encryption_key" {
  description = "n8n encryption key(s). Prefer map(string) by realm; legacy string is also accepted and will be used for all realms."
  type        = any
  sensitive   = true
  default     = null
}

variable "aiops_agent_environment" {
  description = "Additional environment variables for n8n, per realm (realm => map(env_key => value))."
  type        = map(map(string))
  default     = {}
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

variable "aiops_ingest_rate_limit_rps" {
  description = "Default AIOPS ingest rate limit (requests per second)."
  type        = number
  default     = 2
}

variable "aiops_ingest_burst_rps" {
  description = "Default AIOPS ingest burst limit (requests per second)."
  type        = number
  default     = 5
}

variable "aiops_tenant_rate_limit_rps" {
  description = "Default AIOPS tenant rate limit (requests per second)."
  type        = number
  default     = 2
}

variable "aiops_ingest_payload_max_bytes" {
  description = "Default AIOPS ingest payload size limit in bytes."
  type        = number
  default     = 1048576
}

variable "openai_model_api_key_parameter_name" {
  description = "SSM parameter name to store the OpenAI-compatible API key (defaults to /<name_prefix>/n8n/aiops/openai/api_key)."
  type        = string
  default     = null
}

variable "enable_aiops_cloudwatch_alarm_sns" {
  description = "Whether to publish CloudWatch alarms to an SNS topic with a Lambda forwarder that verifies SNS signatures and forwards to n8n."
  type        = bool
  default     = true
}

variable "enable_sulu_updown_alarm" {
  description = "Whether to create a CloudWatch alarm for Sulu up/down (ALB target group UnHealthyHostCount) and stopped state (DesiredTaskCount=0). In this stack, DesiredTaskCount is read from ECS/ContainerInsights (Container Insights). Requires enable_aiops_cloudwatch_alarm_sns."
  type        = bool
  default     = true
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

variable "service_control_web_monitoring_targets" {
  description = "Web monitoring targets for service control (service_id => url). Defaults to keycloak/zulip/gitlab/n8n/sulu service URLs when null."
  type        = map(string)
  default     = null
}

variable "monitoring_yaml" {
  description = "Non-secret monitoring config (YAML/JSON string). Used for ITSM docs + n8n env injection (e.g., Grafana event inbox dashboard/panel IDs)."
  type        = string
  default     = null
}

variable "service_control_api_base_url" {
  description = "Base URL for the service control API (if externally provided)"
  type        = string
  default     = null
}

variable "service_control_jwt_issuer" {
  description = "JWT issuer URL for service control API (Keycloak realm URL)"
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

variable "root_redirect_target_url" {
  description = "Target URL for apex/www domain redirects (set null to disable redirect buckets)"
  type        = string
  default     = "https://github.com/smic-aiops/aiops-agent/blob/main/docs/usage-guide.md"
}

variable "control_subdomain" {
  description = "Subdomain for the business-site control UI (e.g., control)"
  type        = string
  default     = "control"
}

variable "service_subdomain_map" {
  description = <<EOF
Overrides for service subdomain prefixes. Keys match the internal service IDs
(e.g., n8n, zulip, gitlab); values are the label prepended to the shared root
hosted zone.
EOF
  type        = map(string)
  default = {
    n8n         = "n8n"
    qdrant      = "qdrant"
    zulip       = "zulip"
    exastro_web = "ita-web"
    exastro_api = "ita-api"
    sulu        = "sulu"
    pgadmin     = "pgadmin"
    keycloak    = "keycloak"
    odoo        = "odoo"
    gitlab      = "gitlab"
  }
}

variable "ses_domain" {
  description = "SES domain identity (defaults to hosted_zone_name_input)"
  type        = string
  default     = null
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
  default     = true
}

variable "service_control_metrics_stream_services" {
  description = "ECS service keys to export CloudWatch Metric Streams to S3 (e.g., n8n, zulip, gitlab). Use \"synthetics\" to include CloudWatch Synthetics metrics."
  type        = map(bool)
  default = {
    n8n        = false
    zulip      = false
    gitlab     = false
    sulu       = true
    exastro    = false
    keycloak   = false
    odoo       = false
    pgadmin    = false
    synthetics = true
  }
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
  default     = "json"

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
    ,
    {
      namespace = "CloudWatchSynthetics"
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
  default     = true
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
  description = "Enable EFS backup configuration when true"
  type        = bool
  default     = false
}

variable "efs_backup_delete_after_days" {
  description = "EFS backup retention (days) for AWS Backup lifecycle"
  type        = number
  default     = 2
}

# Keycloak management

variable "create_keycloak" {
  description = "Whether to create Keycloak service resources"
  type        = bool
  default     = true
}

variable "keycloak_admin_username" {
  description = "Keycloak admin username (used by Terraform to manage clients)"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password (used by Terraform to manage clients)"
  type        = string
  sensitive   = false
  default     = null
}

variable "keycloak_admin_email" {
  description = "Keycloak admin email (defaults to admin@<hosted_zone_name>)"
  type        = string
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

variable "enable_keycloak_autostop" {
  description = "Whether to enable Keycloak idle auto-stop (AppAutoScaling + CloudWatch alarm)"
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

variable "keycloak_task_cpu" {
  description = "Override CPU units for Keycloak task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 256
}

variable "keycloak_task_memory" {
  description = "Override memory (MB) for Keycloak task definition (null to use ecs_task_memory)"
  type        = number
  default     = 1024
}

variable "ecr_repo_keycloak" {
  description = "ECR repository name for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_image_tag" {
  description = "Keycloak image tag to use for pulls/builds"
  type        = string
  default     = "26.4.7"
}

variable "keycloak_smtp_username" {
  description = "SES SMTP username for Keycloak"
  type        = string
  sensitive   = false
  default     = null
}

variable "keycloak_smtp_password" {
  description = "SES SMTP password for Keycloak"
  type        = string
  sensitive   = false
  default     = null
}

# OIDC IdP YAML overrides (populated by scripts/itsm/keycloak/refresh_keycloak_realm.sh)

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

variable "grafana_filesystem_id" {
  description = "Existing EFS ID to mount for Grafana data (/var/lib/grafana)"
  type        = string
  default     = null
}

variable "grafana_efs_availability_zone" {
  description = "AZ for Grafana One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "zulip_oidc_idps_yaml" {
  description = "Optional override for Zulip Keycloak IdP YAML when managing SSO credentials externally"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_oidc_client_secret_parameter_name" {
  description = "Deprecated (Zulip app-internal OIDC removed); kept for compatibility"
  type        = string
  default     = null
}

variable "zulip_oidc_client_secret" {
  description = "Deprecated (Zulip app-internal OIDC removed); kept for compatibility"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_oidc_full_name_validated" {
  description = "Deprecated (Zulip app-internal OIDC removed); kept for compatibility"
  type        = bool
  default     = true
}

variable "zulip_oidc_pkce_enabled" {
  description = "Deprecated (Zulip app-internal OIDC removed); kept for compatibility"
  type        = bool
  default     = true
}

variable "zulip_oidc_pkce_code_challenge_method" {
  description = "Deprecated (Zulip app-internal OIDC removed); kept for compatibility"
  type        = string
  default     = "S256"
}

# n8n service configuration

variable "create_n8n" {
  description = "Whether to create n8n service resources"
  type        = bool
  default     = true
}

variable "enable_n8n_autostop" {
  description = "Whether to enable n8n idle auto-stop (AppAutoScaling + CloudWatch alarm); service_control のスケジュール中はアラームを無効化するため競合しません。"
  type        = bool
  default     = true
}

variable "n8n_desired_count" {
  description = "Default desired count for n8n ECS service"
  type        = number
  default     = 1
}

variable "n8n_task_cpu" {
  description = "Override CPU units for n8n task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 1024
}

variable "n8n_task_memory" {
  description = "Override memory (MB) for n8n task definition (null to use ecs_task_memory)"
  type        = number
  default     = 2048
}

variable "ecr_repo_n8n" {
  description = "ECR repository name for n8n"
  type        = string
  default     = "n8n"
}

variable "n8n_image_tag" {
  description = "n8n image tag to use for pulls/builds"
  type        = string
  default     = "1.122.4"
}

variable "enable_n8n_qdrant" {
  description = "Whether to run Qdrant sidecar containers per n8n realm (EFS-backed, isolated by realm directory)"
  type        = bool
  default     = true
}

variable "qdrant_image_tag" {
  description = "Qdrant image tag to use for pulls/builds"
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

variable "n8n_smtp_username" {
  description = "SES SMTP username for n8n"
  type        = string
  sensitive   = false
  default     = null
}

variable "n8n_smtp_password" {
  description = "SES SMTP password for n8n"
  type        = string
  sensitive   = false
  default     = null
}

variable "n8n_smtp_sender" {
  description = "n8n SMTP sender address (defaults to no-reply@<hosted_zone_name>)"
  type        = string
  default     = null
}

# Zulip service configuration

variable "create_zulip" {
  description = "Whether to create Zulip service resources"
  type        = bool
  default     = true
}


variable "enable_zulip_autostop" {
  description = "Whether to enable Zulip idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "zulip_admin_api_key" {
  description = "Zulip admin API key (terraform.tfvars に設定し、apply 時に SSM へ格納する)"
  type        = string
  sensitive   = false
  default     = "DummmyKey-xxxxxxxxxxxxxxxxxxxxxxx"
}

variable "zulip_admin_api_keys_yaml" {
  description = "Zulip レルムごとの管理者 API キーマッピング（YAML: realm: api_key）"
  type        = string
  sensitive   = true
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


variable "zulip_admin_email" {
  description = "Zulip 管理者メールアドレス（未指定なら hosted_zone_name を使って推測）"
  type        = string
  default     = null
}


variable "zulip_bot_email" {
  description = "Zulip Bot のメールアドレス"
  type        = string
  default     = null
}


variable "zulip_bot_full_name" {
  description = "Zulip Bot のフルネーム"
  type        = string
  default     = null
}

variable "zulip_url" {
  description = "Zulip ベース URL（未指定なら service_urls.zulip を使用）"
  type        = string
  default     = null
}


variable "zulip_mess_bot_tokens_yaml" {
  description = "Zulip レルムごとの mess 用 Bot API キーマッピング（YAML: realm: token）"
  type        = string
  default     = null
}

variable "zulip_mess_bot_emails_yaml" {
  description = "Zulip レルムごとの mess 用 Bot メールアドレス（YAML: realm: email）"
  type        = string
  default     = null
}

variable "zulip_bot_generic_emails_yaml" {
  description = "（互換用）Zulip レルムごとの Generic Bot メールアドレス（YAML: realm: email）"
  type        = string
  default     = null
}

variable "zulip_api_mess_base_urls_yaml" {
  description = "Zulip レルムごとの mess 用 API Base URL（YAML: realm: url）"
  type        = string
  default     = null
}

variable "zulip_outgoing_tokens_yaml" {
  description = "Zulip Outgoing Webhook のトークンマップ（YAML: realm: token）"
  type        = string
  default     = null
}

variable "zulip_outgoing_bot_emails_yaml" {
  description = "Zulip Outgoing Webhook bot のメールアドレスマップ（YAML: realm: email）"
  type        = string
  default     = null
}

variable "zulip_bot_tokens_param" {
  description = "Zulip Bot API キーマッピングを保存する SSM パラメータ名（未指定なら /<name_prefix>/zulip/bot_tokens）"
  type        = string
  default     = null
}


variable "zulip_bot_short_name" {
  description = "Zulip Bot を作成する際に使う short_name"
  type        = string
  default     = "zulip"
}

variable "zulip_desired_count" {
  description = "Default desired count for Zulip ECS service"
  type        = number
  default     = 1
}

variable "zulip_task_cpu" {
  description = "Override CPU units for Zulip task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 1024
}

variable "zulip_task_memory" {
  description = "Override memory (MB) for Zulip task definition (null to use ecs_task_memory)"
  type        = number
  default     = 4096
}

variable "zulip_mq_port" {
  description = "Listener port for Amazon MQ (RabbitMQ) broker used by Zulip"
  type        = number
  default     = 5672
}

variable "ecr_repo_zulip" {
  description = "ECR repository name for Zulip"
  type        = string
  default     = "zulip"
}




variable "zulip_image_tag" {
  description = "Zulip image tag to pull/build"
  type        = string
  default     = "11.4-0"
}

variable "zulip_environment" {
  description = "Additional environment variables for the Zulip task definition"
  type        = map(string)
  default = {
    SSL_CERTIFICATE_GENERATION = "self-signed"
    DISABLE_HTTPS              = "True"
    SETTING_RABBITMQ_USE_TLS   = "False"
    RABBITMQ_USE_TLS           = "False"
    ALB_OIDC_AUTO_CREATE_USERS = "True"
  }
}

variable "zulip_missing_dictionaries" {
  description = "Set postgresql.missing_dictionaries for Zulip when running on managed PostgreSQL without hunspell dictionaries"
  type        = bool
  default     = true
}

variable "zulip_smtp_username" {
  description = "SES SMTP username for Zulip"
  type        = string
  sensitive   = false
  default     = null
}

variable "zulip_smtp_password" {
  description = "SES SMTP password for Zulip"
  type        = string
  sensitive   = false
  default     = null
}

# Sulu service control

variable "create_sulu" {
  description = "Whether to create sulu service resources"
  type        = bool
  default     = true
}

variable "create_sulu_efs" {
  description = "Whether to create an EFS for sulu (tfvars-only flag)"
  type        = bool
  default     = true
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

variable "sulu_task_cpu" {
  description = "Override CPU units for sulu task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 512
}

variable "sulu_task_memory" {
  description = "Override memory (MB) for sulu task definition (null to use ecs_task_memory)"
  type        = number
  default     = 1024
}

variable "ecr_repo_sulu" {
  description = "ECR repository name for sulu"
  type        = string
  default     = "sulu"
}

variable "ecr_repo_sulu_nginx" {
  description = "ECR repository name for the Sulu nginx companion image"
  type        = string
  default     = "sulu-nginx"
}

variable "sulu_image_tag" {
  description = "Sulu base image tag used for docker/sulu builds (default mirrors the GitHub 3.0.0 release)"
  type        = string
  default     = "3.0.3"
}

variable "sulu_db_name" {
  description = "Logical PostgreSQL database name used by sulu"
  type        = string
  default     = "sulu"
}

variable "sulu_db_username" {
  description = "Optional PostgreSQL username for sulu (falls back to the master user if null)"
  type        = string
  default     = null
}

variable "sulu_share_dir" {
  description = "Filesystem location used as Sulu's share directory (must align with public/uploads/media)"
  type        = string
  default     = "/var/www/html/public/uploads/media"
}

variable "sulu_filesystem_id" {
  description = "Existing EFS ID to mount for sulu uploads/share data"
  type        = string
  default     = null
}

variable "sulu_filesystem_path" {
  description = "Container path where the shared EFS is mounted"
  type        = string
  default     = "/efs"
}

variable "sulu_efs_availability_zone" {
  description = "AZ for One Zone EFS (defaults to first private subnet AZ)"
  type        = string
  default     = null
}

variable "sulu_app_secret" {
  description = "Override APP_SECRET for the sulu task"
  type        = string
  sensitive   = false
  default     = null
}

variable "sulu_mailer_dsn" {
  description = "Override MAILER_DSN for the sulu task (SES-based value is generated when unset)"
  type        = string
  sensitive   = false
  default     = null
}

variable "sulu_admin_email" {
  description = "Sulu admin email (defaults to admin@<hosted_zone_name>)"
  type        = string
  default     = null
}

variable "sulu_admin_password" {
  description = "Sulu admin password (recorded in tfvars; not consumed by Terraform resources)"
  type        = string
  sensitive   = true
  default     = null
}

variable "sulu_sso_default_role_key" {
  description = "Default role key assigned to Keycloak-authenticated Sulu users"
  type        = string
  default     = "ROLE_USER"
}

# Exastro IT Automation stack

variable "create_exastro" {
  description = "Whether to create Exastro web + API admin resources (tfvars-only flag)"
  type        = bool
  default     = true
}

variable "enable_exastro" {
  description = "Flag to enable Exastro web + API services (used by tfvars only)"
  type        = bool
  default     = false
}

variable "enable_exastro_autostop" {
  description = "Whether to enable Exastro idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "enable_exastro_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into Exastro web + API task definitions"
  type        = bool
  default     = false
}

variable "exastro_desired_count" {
  description = "Default desired count for Exastro IT Automation web + API ECS services"
  type        = number
  default     = 0
}

variable "exastro_task_cpu" {
  description = "Override CPU units for Exastro task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 512
}

variable "exastro_task_memory" {
  description = "Override memory (MB) for Exastro task definition (null to use ecs_task_memory)"
  type        = number
  default     = 1024
}

variable "ecr_repo_exastro_it_automation_web_server" {
  description = "ECR repository name for Exastro IT Automation web server"
  type        = string
  default     = "exastro-it-automation-web-server"
}

variable "exastro_it_automation_web_server_image_tag" {
  description = "Exastro IT Automation web server image (repo:tag)"
  type        = string
  default     = "exastro/exastro-it-automation-web-server:2.7.0"
}

variable "ecr_repo_exastro_it_automation_api_admin" {
  description = "ECR repository name for Exastro IT Automation API admin"
  type        = string
  default     = "exastro-it-automation-api-admin"
}

variable "exastro_it_automation_api_admin_image_tag" {
  description = "Exastro IT Automation API admin image (repo:tag)"
  type        = string
  default     = "exastro/exastro-it-automation-api-admin:2.7.0"
}

# GitLab service

variable "create_gitlab" {
  description = "Whether to create GitLab Omnibus service resources"
  type        = bool
  default     = true
}

variable "enable_gitlab_autostop" {
  description = "Whether to enable GitLab idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "enable_gitlab_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into GitLab task definition"
  type        = bool
  default     = false
}

variable "gitlab_desired_count" {
  description = "Default desired count for GitLab ECS service"
  type        = number
  default     = 1
}

variable "gitlab_task_cpu" {
  description = "CPU units for GitLab task definition (default 4 vCPU)"
  type        = number
  default     = 2048
}

variable "gitlab_task_memory" {
  description = "Memory (MB) for GitLab task definition"
  type        = number
  default     = 8192
}

variable "ecr_repo_gitlab" {
  description = "ECR repository name for GitLab Omnibus"
  type        = string
  default     = "gitlab-omnibus"
}

variable "gitlab_omnibus_image_tag" {
  description = "GitLab Omnibus image tag to pull/build"
  type        = string
  default     = "17.11.7-ce.0"
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

variable "gitlab_smtp_username" {
  description = "SES SMTP username for GitLab"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_smtp_password" {
  description = "SES SMTP password for GitLab"
  type        = string
  sensitive   = false
  default     = null
}

variable "gitlab_admin_token_lifetime_days" {
  description = "GitLab admin personal access token lifetime in days (defaults to GitLab maximum when not customized)."
  type        = number
  default     = 364
}

variable "gitlab_admin_token" {
  description = "GitLab admin personal access token (used by scripts; do not commit)"
  type        = string
  sensitive   = true
  default     = null
}

variable "gitlab_realm_admin_tokens_yaml" {
  description = "GitLab realm group access tokens mapping (YAML: realm: token)."
  type        = string
  sensitive   = true
  default     = null
}

variable "gitlab_webhook_secrets_yaml" {
  description = "GitLab webhook secrets mapping for n8n (YAML: realm: secret)."
  type        = string
  sensitive   = true
  default     = null
}

variable "itsm_force_update" {
  description = "Whether ITSM bootstrap scripts should overwrite existing templates/labels by default"
  type        = bool
  default     = true
}

variable "itsm_force_update_included_realms" {
  description = "Realm names that should be overwritten when ITSM_FORCE_UPDATE is true"
  type        = list(string)
  default     = []
}

# Odoo service

variable "create_odoo" {
  description = "Whether to create Odoo service resources"
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
  default     = false
}

variable "odoo_desired_count" {
  description = "Default desired count for Odoo ECS service"
  type        = number
  default     = 0
}

variable "odoo_task_cpu" {
  description = "Override CPU units for Odoo task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 2048
}

variable "odoo_task_memory" {
  description = "Override memory (MB) for Odoo task definition (null to use ecs_task_memory)"
  type        = number
  default     = 4096
}

variable "ecr_repo_odoo" {
  description = "ECR repository name for Odoo"
  type        = string
  default     = "odoo"
}

variable "odoo_image_tag" {
  description = "Odoo image tag to use for pulls/builds"
  type        = string
  default     = "17.0"
}

variable "odoo_smtp_username" {
  description = "SES SMTP username for Odoo"
  type        = string
  sensitive   = false
  default     = null
}

variable "odoo_smtp_password" {
  description = "SES SMTP password for Odoo"
  type        = string
  sensitive   = false
  default     = null
}

# pgAdmin service

variable "create_pgadmin" {
  description = "Whether to create pgAdmin service resources"
  type        = bool
  default     = true
}

variable "enable_pgadmin_autostop" {
  description = "Whether to enable pgAdmin idle auto-stop (AppAutoScaling + CloudWatch alarm)"
  type        = bool
  default     = true
}

variable "enable_pgadmin_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into pgAdmin task definition"
  type        = bool
  default     = false
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

variable "pgadmin_desired_count" {
  description = "Default desired count for pgAdmin ECS service"
  type        = number
  default     = 0
}

variable "pgadmin_task_cpu" {
  description = "Override CPU units for pgAdmin task definition (null to use ecs_task_cpu)"
  type        = number
  default     = 512
}

variable "pgadmin_task_memory" {
  description = "Override memory (MB) for pgAdmin task definition (null to use ecs_task_memory)"
  type        = number
  default     = 1024
}

variable "ecr_repo_pgadmin" {
  description = "ECR repository name for pgAdmin"
  type        = string
  default     = "pgadmin"
}

variable "pgadmin_image_tag" {
  description = "Image tag for pgAdmin"
  type        = string
  default     = "9.10.0"
}

variable "pgadmin_smtp_username" {
  description = "SES SMTP username for pgAdmin"
  type        = string
  sensitive   = false
  default     = null
}

variable "pgadmin_smtp_password" {
  description = "SES SMTP password for pgAdmin"
  type        = string
  sensitive   = false
  default     = null
}

variable "create_mysql_rds" {
  description = "Whether to create a dedicated MySQL RDS instance (tfvars-only flag)"
  type        = bool
  default     = false
}

variable "mysql_rds_skip_final_snapshot" {
  description = "When true, skip creating a final snapshot on MySQL RDS deletion"
  type        = bool
  default     = true
}


# Grafana

variable "create_grafana" {
  description = "Whether to add Grafana sidecar to the GitLab task"
  type        = bool
  default     = true
}

variable "ecs_task_additional_trust_principal_arns" {
  description = "Additional AWS principal ARNs allowed to sts:AssumeRole the ECS task role (useful for debugging)."
  type        = list(string)
  default     = []
}

variable "enable_grafana_keycloak" {
  description = "Whether to inject Keycloak OIDC settings into Grafana"
  type        = bool
  default     = false
}

variable "create_grafana_efs" {
  description = "Whether to create an EFS (One Zone) for Grafana persistent files"
  type        = bool
  default     = true
}

variable "ecr_repo_grafana" {
  description = "ECR repository name for Grafana"
  type        = string
  default     = "grafana"
}

variable "grafana_athena_output_bucket_name" {
  description = "S3 bucket name for Grafana Athena query results"
  type        = string
  default     = null
}

variable "grafana_db_name" {
  description = "Logical database name used by Grafana"
  type        = string
  default     = "grafana"
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

variable "grafana_api_tokens_by_realm" {
  description = "Grafana API tokens by realm (used for automation scripts)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "grafana_image_tag" {
  description = "Grafana image tag to use for pulls/builds"
  type        = string
  default     = "12.3.1"
}

variable "grafana_plugins" {
  description = "Grafana plugins to bake into the image (list of plugin IDs, optional @version)"
  type        = list(string)
  default = [
    "kniepdennis-neo4j-datasource@1.3.2",
    "grafana-postgresql-datasource@5.0.0",
    "grafana-falconlogscale-datasource@1.8.6",
    "yesoreyeram-infinity-datasource@3.7.0",
    "marcusolsson-json-datasource@1.3.25",
    "grafana-athena-datasource@3.1.8",
    "grafana-googlesheets-datasource@2.3.0",
    "grafana-snowflake-datasource@1.14.9",
    "grafana-jira-datasource@2.3.5",
    "grafana-salesforce-datasource@1.7.15",
    "grafana-sumologic-datasource@1.6.11",
    "grafana-redshift-datasource@2.3.2",
    "grafana-bigquery-datasource@3.0.4",
    "grafana-servicenow-datasource@2.13.7",
    "marcusolsson-csv-datasource@0.7.4",
    "grafana-amazonprometheus-datasource@2.3.0",
    "trino-datasource@1.0.11",
    "grafana-timestream-datasource@2.12.5",
    "grafana-opensearch-datasource@2.32.2",
    "grafana-x-ray-datasource@2.16.4",
    "grafana-dynamodb-datasource@2.1.9",
    "grafana-datadog-datasource@3.16.3",
    "grafana-sentry-datasource@2.2.3",
    "grafana-github-datasource@2.4.1",
    "grafana-aurora-datasource@0.5.1",
    "grafadruid-druid-datasource@1.7.0",
    "gabrielthomasjacobs-zendesk-datasource@1.1.2",
    "stackdriver@5.0.0",
    "grafana-gitlab-datasource@2.3.16",
    "grafana-azuredevops-datasource@0.10.6",
    "grafana-clickhouse-datasource@4.12.0",
    "grafana-azure-monitor-datasource@5.0.0",
    "grafana-newrelic-datasource@4.6.14",
  ]
}

# ECS task sizing defaults

variable "ecs_task_cpu" {
  type    = number
  default = 512
}

variable "ecs_task_memory" {
  type    = number
  default = 1024
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
  description = "S3 prefix for ALB access logs (defaults to alb/realm=<default_realm>)."
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
  default     = true
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
  default     = true
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
  default = [
    { service = "sulu", enabled = true }
  ]

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
  default     = true
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
