locals {
  backup_vault_name = "${local.name_prefix}-backup-vault"
  backup_plan_name  = "${local.name_prefix}-efs-backup-plan"
  backup_role_name  = "${local.name_prefix}-backup-role"
  backup_resource_arns = var.enable_efs_backup ? compact([
    local.n8n_filesystem_id_effective != null ? "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${local.n8n_filesystem_id_effective}" : null,
    local.pgadmin_filesystem_id_effective != null ? "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${local.pgadmin_filesystem_id_effective}" : null,
    local.keycloak_filesystem_id_effective != null ? "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${local.keycloak_filesystem_id_effective}" : null,
    local.odoo_filesystem_id_effective != null ? "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${local.odoo_filesystem_id_effective}" : null,
    local.gitlab_data_filesystem_id_effective != null ? "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${local.gitlab_data_filesystem_id_effective}" : null,
    local.gitlab_config_filesystem_id_effective != null ? "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${local.gitlab_config_filesystem_id_effective}" : null,
    local.grafana_filesystem_id_effective != null ? "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${local.grafana_filesystem_id_effective}" : null
  ]) : []
}

resource "aws_backup_vault" "efs" {
  count         = var.enable_efs_backup ? 1 : 0
  name          = local.backup_vault_name
  force_destroy = true

  tags = merge(local.tags, { Name = local.backup_vault_name })
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  count              = var.enable_efs_backup ? 1 : 0
  name               = local.backup_role_name
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json

  tags = merge(local.tags, { Name = local.backup_role_name })
}

resource "aws_iam_role_policy_attachment" "backup" {
  count      = var.enable_efs_backup ? 1 : 0
  role       = var.enable_efs_backup ? aws_iam_role.backup[0].name : null
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  count      = var.enable_efs_backup ? 1 : 0
  role       = var.enable_efs_backup ? aws_iam_role.backup[0].name : null
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "efs" {
  count = var.enable_efs_backup ? 1 : 0
  name  = local.backup_plan_name

  rule {
    rule_name         = "${local.name_prefix}-daily"
    target_vault_name = local.backup_vault_name
    schedule          = "cron(0 18 * * ? *)" # 03:00 JST

    lifecycle {
      delete_after = var.efs_backup_delete_after_days
    }
  }

  tags = merge(local.tags, { Name = local.backup_plan_name })
}

resource "aws_backup_selection" "efs" {
  count        = var.enable_efs_backup ? 1 : 0
  iam_role_arn = var.enable_efs_backup ? aws_iam_role.backup[0].arn : null
  name         = "${local.name_prefix}-efs-selection"
  plan_id      = var.enable_efs_backup ? aws_backup_plan.efs[0].id : null
  resources    = local.backup_resource_arns
}
