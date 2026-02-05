output "vpc_id" {
  description = "ID of the newly created VPC"
  value       = module.stack.vpc_id
  sensitive   = true
}

output "internet_gateway_id" {
  description = "ID of the selected or created internet gateway"
  value       = module.stack.internet_gateway_id
  sensitive   = true
}

output "nat_gateway_id" {
  description = "ID of the selected or created NAT gateway"
  value       = module.stack.nat_gateway_id
  sensitive   = true
}

output "hosted_zone_id" {
  description = "Managed Route53 hosted zone ID"
  value       = module.stack.hosted_zone_id
  sensitive   = true
}

output "hosted_zone_name_servers" {
  description = "Name servers for the managed hosted zone"
  value       = module.stack.hosted_zone_name_servers
  sensitive   = true
}

output "hosted_zone_name" {
  description = "Managed Route53 hosted zone name (root domain)"
  value       = module.stack.hosted_zone_name
  sensitive   = true
}

output "db_credentials_ssm_parameters" {
  description = "SSM parameter names for DB credentials/connection (if created)"
  value       = module.stack.db_credentials_ssm_parameters
  sensitive   = true
}

output "local_image_dir" {
  description = "Local directory to store pulled Docker image tarballs (for scripts)"
  value       = var.local_image_dir
  sensitive   = true
}

output "aws_profile" {
  description = "Default AWS CLI profile for scripts"
  value       = var.aws_profile
  sensitive   = true
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "gitlab_realm_admin_tokens_yaml" {
  description = "GitLab realm group access tokens mapping (YAML: realm: token)."
  value       = var.gitlab_realm_admin_tokens_yaml
  sensitive   = true
}

output "gitlab_webhook_secrets_yaml" {
  description = "GitLab webhook secrets mapping for n8n (YAML: realm: secret)."
  value       = var.gitlab_webhook_secrets_yaml
  sensitive   = true
}

output "gitlab_realm_admin_tokens_json_parameter_name" {
  description = "SSM parameter name for GitLab realm group access tokens mapping (JSON) (if created)."
  value       = module.stack.gitlab_realm_admin_tokens_json_parameter_name
  sensitive   = true
}

output "name_prefix" {
  description = "Name prefix used for tagging and resource names"
  value       = var.name_prefix
}

output "realms" {
  description = "Realm names from var.realms"
  value       = var.realms
}

output "ecs_logs_per_container_services" {
  description = "Services configured to use per-container CloudWatch log groups."
  value       = module.stack.ecs_logs_per_container_services
}

output "ecs_log_destinations_by_realm" {
  description = "CloudWatch log groups by realm and service (service-level + container-level)."
  value       = module.stack.ecs_log_destinations_by_realm
}

output "enable_logs_to_s3" {
  description = "Service log shipping configuration for CloudWatch Logs to S3."
  value       = var.enable_logs_to_s3
}

output "multi_realm_services" {
  description = "Services that support multi-realm provisioning"
  value       = var.multi_realm_services
}

output "xray_services" {
  description = "ECS services configured for X-Ray tracing."
  value       = var.xray_services
}

output "xray_sampling_rate" {
  description = "X-Ray sampling rate (1.0 means sample all)."
  value       = var.xray_sampling_rate
}

output "xray_retention_days" {
  description = "Requested X-Ray retention days (AWS X-Ray currently retains 30 days)."
  value       = var.xray_retention_days
}

output "none_realm_services" {
  description = "Services that do not require realms"
  value       = var.none_realm_services
}

output "single_realm_services" {
  description = "Services that use a single shared realm"
  value       = var.single_realm_services
}

output "ecr_namespace" {
  description = "ECR namespace/prefix"
  value       = var.ecr_namespace
  sensitive   = true
}

output "ecr_repo_n8n" {
  description = "ECR repository name for n8n"
  value       = var.ecr_repo_n8n
  sensitive   = true
}

output "ecr_repo_zulip" {
  description = "ECR repository name for Zulip"
  value       = var.ecr_repo_zulip
  sensitive   = true
}

output "ecr_repo_sulu" {
  description = "ECR repository name for sulu"
  value       = var.ecr_repo_sulu
  sensitive   = true
}

output "ecr_repo_sulu_nginx" {
  description = "ECR repository name for the Sulu nginx companion image"
  value       = var.ecr_repo_sulu_nginx
  sensitive   = true
}

output "ecr_repo_gitlab" {
  description = "ECR repository name for GitLab Omnibus"
  value       = var.ecr_repo_gitlab
  sensitive   = true
}

output "ecr_repo_grafana" {
  description = "ECR repository name for Grafana"
  value       = var.ecr_repo_grafana
  sensitive   = true
}

output "ecr_repo_keycloak" {
  description = "ECR repository name for Keycloak"
  value       = var.ecr_repo_keycloak
  sensitive   = true
}

output "ecr_repo_exastro_it_automation_web_server" {
  description = "ECR repository name for Exastro IT Automation web server"
  value       = var.ecr_repo_exastro_it_automation_web_server
  sensitive   = true
}

output "ecr_repo_exastro_it_automation_api_admin" {
  description = "ECR repository name for Exastro IT Automation API admin"
  value       = var.ecr_repo_exastro_it_automation_api_admin
  sensitive   = true
}

output "ecr_repo_odoo" {
  description = "ECR repository name for Odoo"
  value       = var.ecr_repo_odoo
  sensitive   = true
}

output "ecr_repo_pgadmin" {
  description = "ECR repository name for pgAdmin"
  value       = var.ecr_repo_pgadmin
  sensitive   = true
}

output "ecr_repo_alpine" {
  description = "ECR repository name for shared Alpine base images"
  value       = var.ecr_repo_alpine
  sensitive   = true
}

output "ecr_repo_redis" {
  description = "ECR repository name for shared Redis image"
  value       = var.ecr_repo_redis
  sensitive   = true
}

output "ecr_repo_memcached" {
  description = "ECR repository name for shared Memcached image"
  value       = var.ecr_repo_memcached
  sensitive   = true
}

output "ecr_repo_rabbitmq" {
  description = "ECR repository name for shared RabbitMQ image"
  value       = var.ecr_repo_rabbitmq
  sensitive   = true
}

output "ecr_repo_mongo" {
  description = "ECR repository name for shared MongoDB image"
  value       = var.ecr_repo_mongo
  sensitive   = true
}

output "ecr_repo_python" {
  description = "ECR repository name for shared Python base images"
  value       = var.ecr_repo_python
  sensitive   = true
}

output "ecr_repo_qdrant" {
  description = "ECR repository name for Qdrant image (used by n8n sidecars)"
  value       = var.ecr_repo_qdrant
  sensitive   = true
}

output "ecr_repo_xray_daemon" {
  description = "ECR repository name for AWS X-Ray daemon image"
  value       = var.ecr_repo_xray_daemon
  sensitive   = true
}

output "ecr_repositories" {
  description = "ECR repositories (namespace/repo)"
  value = {
    n8n         = "${var.ecr_namespace}/${var.ecr_repo_n8n}"
    zulip       = "${var.ecr_namespace}/${var.ecr_repo_zulip}"
    sulu        = "${var.ecr_namespace}/${var.ecr_repo_sulu}"
    sulu_nginx  = "${var.ecr_namespace}/${var.ecr_repo_sulu_nginx}"
    gitlab      = "${var.ecr_namespace}/${var.ecr_repo_gitlab}"
    grafana     = "${var.ecr_namespace}/${var.ecr_repo_grafana}"
    odoo        = "${var.ecr_namespace}/${var.ecr_repo_odoo}"
    keycloak    = "${var.ecr_namespace}/${var.ecr_repo_keycloak}"
    pgadmin     = "${var.ecr_namespace}/${var.ecr_repo_pgadmin}"
    exastro_web = "${var.ecr_namespace}/${var.ecr_repo_exastro_it_automation_web_server}"
    exastro_api = "${var.ecr_namespace}/${var.ecr_repo_exastro_it_automation_api_admin}"
    alpine      = "${var.ecr_namespace}/${var.ecr_repo_alpine}"
    redis       = "${var.ecr_namespace}/${var.ecr_repo_redis}"
    memcached   = "${var.ecr_namespace}/${var.ecr_repo_memcached}"
    rabbitmq    = "${var.ecr_namespace}/${var.ecr_repo_rabbitmq}"
    mongo       = "${var.ecr_namespace}/${var.ecr_repo_mongo}"
    python      = "${var.ecr_namespace}/${var.ecr_repo_python}"
    qdrant      = "${var.ecr_namespace}/${var.ecr_repo_qdrant}"
    xray_daemon = "${var.ecr_namespace}/${var.ecr_repo_xray_daemon}"
  }
  sensitive = true
}

output "ecr_image_uris" {
  description = "ECR image URIs (latest tag) for pushing/pulling"
  value = {
    n8n         = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_n8n}:latest"
    zulip       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_zulip}:latest"
    sulu        = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_sulu}:latest"
    sulu_nginx  = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_sulu_nginx}:latest"
    gitlab      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_gitlab}:latest"
    grafana     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_grafana}:latest"
    odoo        = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_odoo}:latest"
    keycloak    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_keycloak}:latest"
    pgadmin     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_pgadmin}:latest"
    exastro_web = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_exastro_it_automation_web_server}:latest"
    exastro_api = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_exastro_it_automation_api_admin}:latest"
    alpine      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_alpine}:latest"
    redis       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_redis}:latest"
    memcached   = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_memcached}:latest"
    rabbitmq    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_rabbitmq}:latest"
    mongo       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_mongo}:latest"
    python      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_python}:latest"
    qdrant      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_qdrant}:latest"
    xray_daemon = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_namespace}/${var.ecr_repo_xray_daemon}:latest"
  }
  sensitive = true
}

output "n8n_image_tag" {
  description = "n8n image tag"
  value       = var.n8n_image_tag
  sensitive   = true
}

output "qdrant_image_tag" {
  description = "Qdrant image tag"
  value       = var.qdrant_image_tag
  sensitive   = true
}

output "gitlab_efs_mirror_state_machine_arn" {
  description = "Step Functions state machine ARN for GitLab->EFS mirror loop (if enabled)"
  value       = module.stack.gitlab_efs_mirror_state_machine_arn
  sensitive   = true
}

output "gitlab_efs_mirror_task_definition_arn" {
  description = "ECS task definition ARN used by the GitLab->EFS mirror loop (if enabled)"
  value       = module.stack.gitlab_efs_mirror_task_definition_arn
  sensitive   = true
}

output "gitlab_efs_indexer_state_machine_arn" {
  description = "Step Functions state machine ARN for GitLab EFS -> Qdrant indexer loop (if enabled)"
  value       = module.stack.gitlab_efs_indexer_state_machine_arn
  sensitive   = true
}

output "gitlab_efs_indexer_task_definition_arn" {
  description = "ECS task definition ARN used by the GitLab EFS -> Qdrant indexer loop (if enabled)"
  value       = module.stack.gitlab_efs_indexer_task_definition_arn
  sensitive   = true
}

output "gitlab_efs_indexer_collection_alias_map" {
  description = "Qdrant collection alias map by management domain used by the GitLab EFS indexer"
  value       = module.stack.gitlab_efs_indexer_collection_alias_map
  sensitive   = false
}

output "gitlab_omnibus_image_tag" {
  description = "GitLab Omnibus image tag"
  value       = var.gitlab_omnibus_image_tag
  sensitive   = true
}

output "zulip_image_tag" {
  description = "Zulip image tag"
  value       = var.zulip_image_tag
  sensitive   = true
}

locals {
  zulip_admin_email_effective = coalesce(
    var.zulip_admin_email,
    try("admin@${module.stack.hosted_zone_name}", null),
    null
  )
  sulu_admin_email_effective = coalesce(
    var.sulu_admin_email,
    try("admin@${module.stack.hosted_zone_name}", null),
    null
  )
  sulu_primary_realm_effective = length(var.realms) > 0 ? var.realms[0] : try(module.stack.default_realm, null)
  sulu_service_name_effective  = local.sulu_primary_realm_effective != null && local.sulu_primary_realm_effective != "" ? "${var.name_prefix}-sulu-${local.sulu_primary_realm_effective}" : "${var.name_prefix}-sulu"
  zulip_bot_email_effective = coalesce(
    var.zulip_bot_email,
    try("bot@${module.stack.hosted_zone_name}", null),
    null
  )
  zulip_bot_full_name_effective = coalesce(
    var.zulip_bot_full_name,
    "Zulip Bot"
  )
  zulip_bot_short_name_effective = coalesce(
    var.zulip_bot_short_name,
    "zulip"
  )
  service_names = {
    n8n      = "${var.name_prefix}-n8n"
    zulip    = "${var.name_prefix}-zulip"
    sulu     = local.sulu_service_name_effective
    keycloak = "${var.name_prefix}-keycloak"
    odoo     = "${var.name_prefix}-odoo"
    pgadmin  = "${var.name_prefix}-pgadmin"
    gitlab   = "${var.name_prefix}-gitlab"
    exastro  = "${var.name_prefix}-exastro"
  }
  service_control_web_monitoring_targets_default = {
    for service in ["keycloak", "zulip", "gitlab", "n8n", "sulu"] :
    service => try(module.stack.service_urls[service], null)
  }
  service_control_web_monitoring_targets_effective = var.service_control_web_monitoring_targets != null ? var.service_control_web_monitoring_targets : local.service_control_web_monitoring_targets_default
  service_control_web_monitoring_targets_by_realm = {
    for realm in var.realms :
    realm => local.service_control_web_monitoring_targets_effective
  }
}

output "zulip_admin_api_key" {
  description = "Zulip admin API key (use with care; stored in state)"
  value       = var.zulip_admin_api_key
  sensitive   = true
}

output "zulip_admin_api_key_parameter_names_by_realm" {
  description = "SSM parameter names for Zulip realm admin API keys (per realm) (if created)."
  value       = module.stack.zulip_admin_api_key_parameter_names_by_realm
  sensitive   = true
}

output "zulip_bot_email" {
  description = "Zulip Bot email address"
  value       = nonsensitive(local.zulip_bot_email_effective)
}

output "zulip_bot_full_name" {
  description = "Zulip Bot full name"
  value       = local.zulip_bot_full_name_effective
}

output "zulip_bot_short_name" {
  description = "Short name used when creating the Zulip bot"
  value       = local.zulip_bot_short_name_effective
}

output "zulip_url_input" {
  description = "Zulip URL provided via root variable (falls back to service_urls.zulip inside zulip_bot_setup)"
  value       = var.zulip_url
}

output "zulip_admin_email_input" {
  description = "Zulip admin email provided via root variable (falls back to admin@<hosted_zone>)"
  value       = nonsensitive(local.zulip_admin_email_effective)
}

output "sulu_admin_email_input" {
  description = "Sulu admin email provided via root variable (falls back to admin@<hosted_zone>)"
  value       = nonsensitive(local.sulu_admin_email_effective)
}

output "sulu_admin_password" {
  description = "Sulu admin password recorded in tfvars (use with care; stored in state)"
  value       = var.sulu_admin_password
  sensitive   = true
}

output "n8n_admin_email" {
  description = "n8n admin email recorded in tfvars (use with care; stored in state)"
  value       = nonsensitive(var.n8n_admin_email)
}

output "n8n_admin_password" {
  description = "n8n admin password recorded in tfvars (use with care; stored in state)"
  value       = var.n8n_admin_password
  sensitive   = true
}


output "zulip_bot_tokens_param" {
  description = "SSM parameter name used for the Zulip realm bot token mapping"
  value       = coalesce(nonsensitive(module.stack.zulip_bot_tokens_parameter_name), var.zulip_bot_tokens_param, "/${var.name_prefix}/zulip/bot_tokens")
}

output "aiops_zulip_api_base_url_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip API base URL by realm"
  value       = nonsensitive(module.stack.aiops_zulip_api_base_url_param_by_realm)
}

output "aiops_zulip_bot_email_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip bot email by realm"
  value       = nonsensitive(module.stack.aiops_zulip_bot_email_param_by_realm)
}

output "aiops_zulip_bot_token_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip bot token by realm"
  value       = nonsensitive(module.stack.aiops_zulip_bot_token_param_by_realm)
}

output "aiops_zulip_outgoing_token_param_by_realm" {
  description = "SSM parameter names for the AIOps Zulip outgoing token by realm"
  value       = nonsensitive(module.stack.aiops_zulip_outgoing_token_param_by_realm)
}

output "aiops_cloudwatch_webhook_secret_param_by_realm" {
  description = "SSM parameter names for the AIOps CloudWatch webhook secret by realm"
  value       = nonsensitive(module.stack.aiops_cloudwatch_webhook_secret_param_by_realm)
}

output "sulu_image_tag" {
  description = "Sulu (nginx) image tag"
  value       = var.sulu_image_tag
  sensitive   = true
}

output "keycloak_image_tag" {
  description = "Keycloak image tag"
  value       = var.keycloak_image_tag
  sensitive   = true
}

output "odoo_image_tag" {
  description = "Odoo image tag"
  value       = var.odoo_image_tag
  sensitive   = true
}

output "grafana_image_tag" {
  description = "Grafana image tag"
  value       = var.grafana_image_tag
  sensitive   = true
}

output "grafana_plugins" {
  description = "Grafana plugins to bake into the image"
  value       = var.grafana_plugins
  sensitive   = false
}

output "grafana_api_tokens_by_realm" {
  description = "Grafana API tokens by realm (for automation scripts)"
  value       = var.grafana_api_tokens_by_realm
  sensitive   = true
}

output "pgadmin_image_tag" {
  description = "pgAdmin image tag"
  value       = var.pgadmin_image_tag
  sensitive   = true
}

output "exastro_it_automation_web_server_image_tag" {
  description = "Exastro IT Automation web server image (repo:tag)"
  value       = var.exastro_it_automation_web_server_image_tag
  sensitive   = true
}

output "exastro_it_automation_api_admin_image_tag" {
  description = "Exastro IT Automation API admin image (repo:tag)"
  value       = var.exastro_it_automation_api_admin_image_tag
  sensitive   = true
}

output "image_architecture" {
  description = "Container platform/architecture"
  value       = var.image_architecture
  sensitive   = true
}

output "ecs_cluster" {
  description = "ECS cluster info (if created)"
  value = {
    name               = try(module.stack.ecs_cluster.name, null)
    arn                = try(module.stack.ecs_cluster.arn, null)
    execution_role_arn = try(module.stack.ecs_cluster.execution_role_arn, null)
    task_role_arn      = try(module.stack.ecs_cluster.task_role_arn, null)
  }
  sensitive = true
}

output "ecs_cluster_name" {
  description = "ECS cluster name (if created)"
  value       = nonsensitive(try(module.stack.ecs_cluster.name, null))
}

output "service_urls" {
  description = "Endpoints for user-facing services"
  value       = module.stack.service_urls
  sensitive   = true
}

output "gitlab_service_projects_path" {
  description = "Default GitLab service project path mapping by realm (realm => \"<realm>/service-management\")"
  value       = module.stack.gitlab_service_projects_path
}

output "gitlab_general_projects_path" {
  description = "Default GitLab general project path mapping by realm (realm => \"<realm>/general-management\")"
  value       = module.stack.gitlab_general_projects_path
}

output "gitlab_technical_projects_path" {
  description = "Default GitLab technical project path mapping by realm (realm => \"<realm>/technical-management\")"
  value       = module.stack.gitlab_technical_projects_path
}

output "GITLAB_SERVICE_PROJECTS_PATH" {
  description = "Alias of gitlab_service_projects_path for scripts (realm => \"<realm>/service-management\")"
  value       = module.stack.gitlab_service_projects_path
}

output "gitlab_projects_path_json_parameter_name" {
  description = "SSM parameter name for GitLab projects path mapping JSON (if created)"
  value       = module.stack.gitlab_projects_path_json_parameter_name
  sensitive   = true
}

output "gitlab_api_base_url" {
  description = "GitLab API base URL (GITLAB_API_BASE_URL), derived from service_urls.gitlab + /api/v4"
  value       = try(module.stack.service_urls.gitlab, null) != null ? "${trim(module.stack.service_urls.gitlab, "/")}/api/v4" : null
  sensitive   = true
}

output "grafana_athena_output_bucket" {
  description = "S3 bucket used for Grafana Athena query results"
  value       = module.stack.grafana_athena_output_bucket
  sensitive   = true
}

output "alb_access_logs_athena_database" {
  description = "Glue database name for ALB access logs (Athena)."
  value       = module.stack.alb_access_logs_athena_database
  sensitive   = true
}

output "alb_access_logs_athena_table" {
  description = "Glue table name for ALB access logs when realm sorter is disabled."
  value       = module.stack.alb_access_logs_athena_table
  sensitive   = true
}

output "alb_access_logs_athena_tables_by_realm" {
  description = "Glue table names for ALB access logs per realm when realm sorter is enabled."
  value       = module.stack.alb_access_logs_athena_tables_by_realm
  sensitive   = true
}

output "service_logs_athena_database" {
  description = "Glue database name for service logs (n8n/grafana)."
  value       = module.stack.service_logs_athena_database
  sensitive   = true
}

output "n8n_logs_athena_table" {
  description = "Glue table name for n8n logs (Athena)."
  value       = module.stack.n8n_logs_athena_table
  sensitive   = true
}

output "grafana_logs_athena_tables_by_realm" {
  description = "Glue table names for Grafana logs per realm."
  value       = module.stack.grafana_logs_athena_tables_by_realm
  sensitive   = true
}

output "service_control_metrics_athena_database" {
  description = "Glue database name for service control metrics (Athena)."
  value       = module.stack.service_control_metrics_athena_database
  sensitive   = true
}

output "service_control_metrics_athena_table" {
  description = "Glue table name for service control metrics (Athena)."
  value       = module.stack.service_control_metrics_athena_table
  sensitive   = true
}

output "grafana_realm_urls" {
  description = "Grafana URLs per realm"
  value       = module.stack.grafana_realm_urls
  sensitive   = true
}

output "n8n_realm_urls" {
  description = "n8n URLs per realm"
  value       = module.stack.n8n_realm_urls
  sensitive   = true
}

output "aiops_workflows_token" {
  description = "Workflow catalog token consumed by n8n workflows (N8N_WORKFLOWS_TOKEN)"
  value       = module.stack.aiops_workflows_token
  sensitive   = true
}

output "N8N_WORKFLOWS_TOKEN" {
  description = "Workflow catalog token consumed by n8n workflows (N8N_WORKFLOWS_TOKEN)"
  value       = module.stack.aiops_workflows_token
  sensitive   = true
}

output "aiops_n8n_activate" {
  description = "Default value for N8N_ACTIVATE used by deploy_workflows.sh"
  value       = var.aiops_n8n_activate
}

output "N8N_ACTIVATE" {
  description = "Default value for N8N_ACTIVATE used by deploy_workflows.sh"
  value       = var.aiops_n8n_activate
}

output "aiops_n8n_agent_realms" {
  description = "Realm list used to decide where to install AIOps Agent in n8n."
  value       = var.aiops_n8n_agent_realms
}

output "N8N_AGENT_REALMS" {
  description = "Realm list used to decide where to install AIOps Agent in n8n."
  value       = var.aiops_n8n_agent_realms
}

output "n8n_api_key" {
  description = "Public API key for n8n (used by workflow catalog endpoints)"
  value       = module.stack.n8n_api_key
  sensitive   = true
}

output "n8n_api_keys_by_realm" {
  description = "n8n API keys per realm (stored in tfvars)"
  value       = var.n8n_api_keys_by_realm
  sensitive   = true
}

output "n8n_encryption_key_param" {
  description = "SSM parameter name for the legacy (single) n8n encryption key"
  value       = module.stack.n8n_encryption_key_param
  sensitive   = true
}

output "n8n_encryption_key" {
  description = "n8n encryption key values by realm"
  value       = module.stack.n8n_encryption_key
  sensitive   = true
}

output "n8n_encryption_key_param_by_realm" {
  description = "SSM parameter names for the n8n encryption key by realm"
  value       = module.stack.n8n_encryption_key_param_by_realm
  sensitive   = true
}

output "n8n_encryption_key_single" {
  description = "Legacy (single) n8n encryption key value"
  value       = module.stack.n8n_encryption_key_single
  sensitive   = true
}

locals {
  aiops_agent_environment_default = try(lookup(var.aiops_agent_environment, "default", {}), {})
  aiops_agent_environment_primary = try(
    merge(
      local.aiops_agent_environment_default,
      lookup(var.aiops_agent_environment, module.stack.default_realm, {})
    ),
    local.aiops_agent_environment_default
  )
}

output "openai_credential_id" {
  description = "OpenAI credential ID used by n8n (OPENAI_CREDENTIAL_ID)"
  value       = lookup(local.aiops_agent_environment_primary, "OPENAI_CREDENTIAL_ID", null)
}

output "n8n_db_credential_id" {
  description = "n8n DB credential ID used by n8n (N8N_DB_CREDENTIAL_ID)"
  value       = lookup(local.aiops_agent_environment_primary, "N8N_DB_CREDENTIAL_ID", null)
}

output "n8n_aws_credential_id" {
  description = "n8n AWS credential ID used by n8n (N8N_AWS_CREDENTIAL_ID)"
  value       = lookup(local.aiops_agent_environment_primary, "N8N_AWS_CREDENTIAL_ID", null)
}

output "zulip_basic_credential_id" {
  description = "Zulip httpBasicAuth credential ID used by n8n (ZULIP_BASIC_CREDENTIAL_ID)"
  value       = lookup(local.aiops_agent_environment_primary, "ZULIP_BASIC_CREDENTIAL_ID", null)
}

output "N8N_ZULIP_BOT_EMAILS_YAML" {
  description = "YAML mapping for Zulip bot emails (N8N_ZULIP_BOT_EMAILS_YAML)"
  value       = try(var.zulip_mess_bot_emails_yaml, null)
  sensitive   = true
}

output "zulip_admin_api_keys_yaml" {
  description = "Zulip admin API key mapping per realm (YAML; stored in state)"
  value       = var.zulip_admin_api_keys_yaml
  sensitive   = true
}

output "zulip_mess_bot_emails_yaml" {
  description = "YAML mapping for Zulip mess bot emails (zulip_mess_bot_emails_yaml)"
  value       = try(var.zulip_mess_bot_emails_yaml, null)
  sensitive   = true
}

output "N8N_ZULIP_API_BASE_URLS_YAML" {
  description = "YAML mapping for Zulip API base URLs (N8N_ZULIP_API_BASE_URLS_YAML)"
  value       = try(var.zulip_api_mess_base_urls_yaml, null)
  sensitive   = true
}

output "zulip_api_mess_base_urls_yaml" {
  description = "YAML mapping for Zulip API base URLs for mess (zulip_api_mess_base_urls_yaml)"
  value       = try(var.zulip_api_mess_base_urls_yaml, null)
  sensitive   = true
}

output "N8N_ZULIP_BOT_TOKENS_YAML" {
  description = "YAML mapping for Zulip bot tokens (N8N_ZULIP_BOT_TOKENS_YAML)"
  value       = try(var.zulip_mess_bot_tokens_yaml, null)
  sensitive   = true
}

output "zulip_mess_bot_tokens_yaml" {
  description = "YAML mapping for Zulip mess bot tokens (zulip_mess_bot_tokens_yaml)"
  value       = try(var.zulip_mess_bot_tokens_yaml, null)
  sensitive   = true
}

output "N8N_ZULIP_OUTGOING_TOKENS_YAML" {
  description = "YAML mapping for Zulip outgoing webhook tokens (N8N_ZULIP_OUTGOING_TOKENS_YAML)"
  value       = try(var.zulip_outgoing_tokens_yaml, null)
  sensitive   = true
}

output "N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML" {
  description = "YAML mapping for Zulip outgoing webhook bot emails (N8N_ZULIP_OUTGOING_BOT_EMAILS_YAML)"
  value       = try(var.zulip_outgoing_bot_emails_yaml, null)
  sensitive   = true
}

output "zulip_outgoing_tokens_yaml" {
  description = "YAML mapping for Zulip outgoing webhook tokens (zulip_outgoing_tokens_yaml)"
  value       = try(var.zulip_outgoing_tokens_yaml, null)
  sensitive   = true
}

output "zulip_outgoing_bot_emails_yaml" {
  description = "YAML mapping for Zulip outgoing webhook bot emails (zulip_outgoing_bot_emails_yaml)"
  value       = try(var.zulip_outgoing_bot_emails_yaml, null)
  sensitive   = true
}

output "openai_model_api_key_param" {
  description = "SSM parameter name for the OpenAI-compatible API key"
  value       = module.stack.openai_model_api_key_param
  sensitive   = true
}

output "openai_model_api_key_param_by_realm" {
  description = "SSM parameter names for the OpenAI-compatible API key by realm"
  value       = module.stack.openai_model_api_key_param_by_realm
  sensitive   = true
}

output "openai_model_param_by_realm" {
  description = "SSM parameter names for the OpenAI-compatible model by realm"
  value       = module.stack.openai_model_param_by_realm
}

output "openai_base_url_param_by_realm" {
  description = "SSM parameter names for the OpenAI-compatible base URL by realm"
  value       = module.stack.openai_base_url_param_by_realm
}

output "aiops_s3_prefix_param" {
  description = "SSM parameter name for N8N_S3_PREFIX"
  value       = module.stack.aiops_s3_prefix_param
}

output "aiops_s3_bucket_names_by_realm" {
  description = "AIOPS S3 bucket names by realm"
  value       = module.stack.aiops_s3_bucket_names_by_realm
}

output "aiops_s3_bucket_param_by_realm" {
  description = "SSM parameter names for N8N_S3_BUCKET by realm"
  value       = module.stack.aiops_s3_bucket_param_by_realm
}

output "aiops_gitlab_first_contact_done_label_param" {
  description = "SSM parameter name for N8N_GITLAB_FIRST_CONTACT_DONE_LABEL"
  value       = module.stack.aiops_gitlab_first_contact_done_label_param
}

output "aiops_gitlab_escalation_label_param" {
  description = "SSM parameter name for N8N_GITLAB_ESCALATION_LABEL"
  value       = module.stack.aiops_gitlab_escalation_label_param
}

output "aiops_ingest_rate_limit_rps" {
  description = "Default AIOPS ingest rate limit (requests per second)."
  value       = var.aiops_ingest_rate_limit_rps
}

output "aiops_ingest_burst_rps" {
  description = "Default AIOPS ingest burst limit (requests per second)."
  value       = var.aiops_ingest_burst_rps
}

output "aiops_tenant_rate_limit_rps" {
  description = "Default AIOPS tenant rate limit (requests per second)."
  value       = var.aiops_tenant_rate_limit_rps
}

output "aiops_ingest_payload_max_bytes" {
  description = "Default AIOPS ingest payload size limit in bytes."
  value       = var.aiops_ingest_payload_max_bytes
}

output "keycloak_realm_master_email_settings" {
  description = "Master realm email settings applied to Keycloak"
  value       = module.stack.keycloak_realm_master_email_settings
}

output "keycloak_realm_master_localization" {
  description = "Master realm localization settings applied to Keycloak"
  value       = module.stack.keycloak_realm_master_localization
}

output "keycloak_admin_email" {
  description = "Keycloak admin email (if provided)"
  value       = var.keycloak_admin_email
}

output "exastro_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for Exastro"
  value       = var.exastro_oidc_idps_yaml
  sensitive   = true
}

output "sulu_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for Sulu"
  value       = var.sulu_oidc_idps_yaml
  sensitive   = true
}

output "keycloak_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for Keycloak"
  value       = var.keycloak_oidc_idps_yaml
  sensitive   = true
}

output "odoo_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for Odoo"
  value       = var.odoo_oidc_idps_yaml
  sensitive   = true
}

output "pgadmin_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for pgAdmin"
  value       = var.pgadmin_oidc_idps_yaml
  sensitive   = true
}

output "gitlab_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for GitLab"
  value       = var.gitlab_oidc_idps_yaml
  sensitive   = true
}

output "grafana_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for Grafana"
  value       = var.grafana_oidc_idps_yaml
  sensitive   = true
}

output "zulip_oidc_idps_yaml" {
  description = "OIDC IdP configuration YAML for Zulip"
  value       = var.zulip_oidc_idps_yaml
  sensitive   = true
}

output "default_realm" {
  description = "Effective Keycloak realm used by the stack"
  value       = module.stack.default_realm
}

output "gitlab_admin_token_lifetime_days" {
  description = "GitLab admin personal access token lifetime in days"
  value       = var.gitlab_admin_token_lifetime_days
}

output "service_names" {
  description = "ECS service names derived from name_prefix"
  value       = local.service_names
}

output "zulip_service_name" {
  description = "Zulip ECS service name"
  value       = local.service_names.zulip
}

output "n8n_service_name" {
  description = "n8n ECS service name"
  value       = local.service_names.n8n
}

output "sulu_service_name" {
  description = "sulu ECS service name"
  value       = local.service_names.sulu
}

output "sulu_service_names" {
  description = "Sulu ECS service names by realm"
  value = {
    for realm in(length(var.realms) > 0 ? var.realms : [try(module.stack.default_realm, null)]) :
    realm => "${var.name_prefix}-sulu-${realm}"
    if realm != null && realm != ""
  }
}

output "keycloak_service_name" {
  description = "Keycloak ECS service name"
  value       = local.service_names.keycloak
}

output "odoo_service_name" {
  description = "Odoo ECS service name"
  value       = local.service_names.odoo
}

output "pgadmin_service_name" {
  description = "pgAdmin ECS service name"
  value       = local.service_names.pgadmin
}

output "gitlab_service_name" {
  description = "GitLab ECS service name"
  value       = local.service_names.gitlab
}

output "exastro_service_name" {
  description = "Unified Exastro ECS service name (web+api)"
  value       = local.service_names.exastro
}

output "zulip_bot_setup" {
  description = "Helper values for provisioning the Zulip bot and storing its APIキー"
  value = {
    zulip_url                 = coalesce(var.zulip_url, try(module.stack.service_urls.zulip, null))
    zulip_admin_email         = coalesce(local.zulip_admin_email_effective, "admin@smic-aiops.jp")
    zulip_admin_api_key_param = module.stack.zulip_admin_api_key_parameter_name
    zulip_bot_short_name      = local.zulip_bot_short_name_effective
    zulip_bot_email           = coalesce(local.zulip_bot_email_effective, "bot@smic-aiops.jp")
    zulip_bot_full_name       = local.zulip_bot_full_name_effective
  }
  sensitive = true
}

output "enabled_services" {
  description = "ECS services enabled for deployment"
  value       = module.stack.enabled_services
  sensitive   = true
}

output "service_control_api_base_url" {
  description = "Base URL for the service control API (n8n/zulip/sulu/keycloak/odoo/pgadmin/gitlab)"
  value       = module.stack.service_control_api_base_url
  sensitive   = true
}

output "gitlab_admin_token_parameter_name" {
  description = "SSM parameter name for the GitLab admin token (if created)"
  value       = module.stack.gitlab_admin_token_parameter_name
  sensitive   = true
}

output "gitlab_admin_token" {
  description = "GitLab admin personal access token (use with care; stored in state)"
  value       = var.gitlab_admin_token
  sensitive   = true
}

output "itsm_force_update" {
  description = "Whether ITSM bootstrap scripts should overwrite existing templates/labels by default"
  value       = var.itsm_force_update
}

output "itsm_force_update_included_realms" {
  description = "Realm names that should be overwritten when ITSM_FORCE_UPDATE is true"
  value       = var.itsm_force_update_included_realms
}

output "itsm_monitoring_context" {
  description = "Non-secret monitoring context derived from monitoring_yaml (realm => config)."
  value       = module.stack.itsm_monitoring_context
  sensitive   = false
}

output "service_control_web_monitoring_targets" {
  description = "Web monitoring targets for service control (service => url)"
  value       = local.service_control_web_monitoring_targets_effective
  sensitive   = true
}

output "service_control_web_monitoring_context" {
  description = "Web monitoring context for service control (realm => service => url)"
  value = {
    targets = local.service_control_web_monitoring_targets_by_realm
  }
  sensitive = true
}

output "n8n_filesystem_id" {
  description = "EFS ID used for n8n persistent storage (if enabled)"
  value       = module.stack.n8n_filesystem_id
  sensitive   = true
}

output "zulip_filesystem_id" {
  description = "EFS ID used for Zulip persistent storage (if enabled)"
  value       = module.stack.zulip_filesystem_id
  sensitive   = true
}

output "sulu_filesystem_id" {
  description = "EFS ID used for sulu persistent storage (if enabled)"
  value       = module.stack.sulu_filesystem_id
  sensitive   = true
}

output "exastro_filesystem_id" {
  description = "EFS ID used for Exastro IT Automation persistent storage (if enabled)"
  value       = module.stack.exastro_filesystem_id
  sensitive   = true
}


output "grafana_filesystem_id" {
  description = "EFS ID used for Grafana persistent storage (if enabled)"
  value       = module.stack.grafana_filesystem_id
  sensitive   = true
}

output "rds" {
  description = "RDS instance details (if created)"
  value       = module.stack.rds
  sensitive   = true
}

output "rds_postgresql" {
  description = "PostgreSQL RDS connection details (if created)"
  value       = module.stack.rds_postgresql
  sensitive   = true
}

output "pg_db_password" {
  description = "Effective PostgreSQL master password (if created)"
  value       = module.stack.pg_db_password
  sensitive   = true
}

output "rds_mysql" {
  description = "MySQL RDS connection details (if created)"
  value       = module.stack.rds_mysql
  sensitive   = true
}

output "mysql_db_password" {
  description = "Effective MySQL database password (if created)"
  value       = module.stack.mysql_db_password
  sensitive   = true
}

output "sulu_database_url" {
  description = "Effective Sulu DATABASE_URL (if created; includes credentials)"
  value       = module.stack.sulu_database_url
  sensitive   = true
}

output "aiops_cloudwatch_webhook_secret_by_realm" {
  description = "CloudWatch webhook secret mapping by realm (for /notify; includes default)"
  value       = module.stack.aiops_cloudwatch_webhook_secret_by_realm
  sensitive   = true
}

output "keycloak_admin_credentials" {
  description = "Initial Keycloak admin username/password and their SSM parameter names (returns null if Keycloak is disabled)"
  value       = module.stack.keycloak_admin_credentials
  sensitive   = true
}

output "grafana_admin_credentials" {
  description = "Initial Grafana admin username/password and their SSM parameter names (returns null if Grafana is disabled)"
  value       = module.stack.grafana_admin_credentials
  sensitive   = true
}

output "initial_credentials" {
  description = "Initial admin credentials (SSM parameter names) for selected services"
  value       = module.stack.initial_credentials
  sensitive   = true
}

output "service_admin_info" {
  description = "Initial admin URLs and credential pointers per service (password values are not exposed; console links point to SSM SecureString entries)"
  value       = module.stack.service_admin_info
  sensitive   = true
}

output "ses_smtp_username" {
  description = "Auto-created SES SMTP username (if SES SMTP auto is enabled)"
  value       = module.stack.ses_smtp_username
  sensitive   = true
}

output "ses_smtp_password" {
  description = "Auto-created SES SMTP password (if SES SMTP auto is enabled)"
  value       = module.stack.ses_smtp_password
  sensitive   = true
}

output "ses_smtp_endpoint" {
  description = "SES SMTP endpoint for the configured region"
  value       = module.stack.ses_smtp_endpoint
}

output "ses_smtp_starttls_port" {
  description = "SES SMTP STARTTLS (TLS upgrade) port"
  value       = module.stack.ses_smtp_starttls_port
}

output "ses_smtp_ssl_port" {
  description = "SES SMTP implicit TLS port"
  value       = module.stack.ses_smtp_ssl_port
}

# output "zulip_dependencies" {
#   description = "Zulip dependency endpoints and SSM parameter names"
#   value       = module.stack.zulip_dependencies
# }
