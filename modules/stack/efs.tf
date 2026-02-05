locals {
  n8n_efs_name         = "${local.name_prefix}-n8n-efs"
  n8n_efs_sg           = "${local.name_prefix}-n8n-efs-sg"
  n8n_efs_az           = coalesce(var.n8n_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
  sulu_efs_name        = "${local.name_prefix}-sulu-efs"
  sulu_efs_sg          = "${local.name_prefix}-sulu-efs-sg"
  sulu_efs_az          = coalesce(var.sulu_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
  zulip_efs_name       = "${local.name_prefix}-zulip-efs"
  zulip_efs_sg         = "${local.name_prefix}-zulip-efs-sg"
  zulip_efs_az         = coalesce(var.zulip_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
  pgadmin_efs_name     = "${local.name_prefix}-pgadmin-efs"
  pgadmin_efs_sg       = "${local.name_prefix}-pgadmin-efs-sg"
  pgadmin_efs_az       = coalesce(var.pgadmin_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
  exastro_efs_name     = "${local.name_prefix}-exastro-efs"
  exastro_efs_sg       = "${local.name_prefix}-exastro-efs-sg"
  exastro_efs_az       = coalesce(var.exastro_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
  keycloak_efs_name    = "${local.name_prefix}-keycloak-efs"
  keycloak_efs_sg      = "${local.name_prefix}-keycloak-efs-sg"
  keycloak_efs_az      = coalesce(var.keycloak_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
  odoo_efs_name        = "${local.name_prefix}-odoo-efs"
  odoo_efs_sg          = "${local.name_prefix}-odoo-efs-sg"
  odoo_efs_az          = coalesce(var.odoo_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
  gitlab_data_efs_name = "${local.name_prefix}-gitlab-data-efs"
  gitlab_data_efs_sg   = "${local.name_prefix}-gitlab-data-efs-sg"
  gitlab_data_efs_az = coalesce(
    var.gitlab_data_efs_availability_zone,
    try(local.private_subnets_map[local.service_subnet_keys[0]].az, null),
    try(local.private_subnets[0].az, null),
    "${var.region}a",
  )
  gitlab_config_efs_name = "${local.name_prefix}-gitlab-config-efs"
  gitlab_config_efs_sg   = "${local.name_prefix}-gitlab-config-efs-sg"
  gitlab_config_efs_az = coalesce(
    var.gitlab_config_efs_availability_zone,
    try(local.private_subnets_map[local.service_subnet_keys[0]].az, null),
    try(local.private_subnets[0].az, null),
    "${var.region}a",
  )
}

data "aws_resourcegroupstaggingapi_resources" "n8n_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.n8n_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "sulu_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.sulu_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "zulip_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.zulip_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "pgadmin_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.pgadmin_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "exastro_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.exastro_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "keycloak_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.keycloak_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "odoo_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.odoo_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "gitlab_data_efs" {
  count                 = var.gitlab_data_filesystem_id == null ? 1 : 0
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.gitlab_data_efs_name]
  }
}

data "aws_resourcegroupstaggingapi_resources" "gitlab_config_efs" {
  count                 = var.gitlab_config_filesystem_id == null ? 1 : 0
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.gitlab_config_efs_name]
  }
}

locals {
  n8n_existing_efs_id           = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.n8n_efs.resource_tag_mapping_list[0].resource_arn), null)
  sulu_existing_efs_id          = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.sulu_efs.resource_tag_mapping_list[0].resource_arn), null)
  zulip_existing_efs_id         = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.zulip_efs.resource_tag_mapping_list[0].resource_arn), null)
  pgadmin_existing_efs_id       = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.pgadmin_efs.resource_tag_mapping_list[0].resource_arn), null)
  exastro_existing_efs_id       = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.exastro_efs.resource_tag_mapping_list[0].resource_arn), null)
  keycloak_existing_efs_id      = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.keycloak_efs.resource_tag_mapping_list[0].resource_arn), null)
  odoo_existing_efs_id          = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.odoo_efs.resource_tag_mapping_list[0].resource_arn), null)
  gitlab_data_existing_efs_id   = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.gitlab_data_efs[0].resource_tag_mapping_list[0].resource_arn), null)
  gitlab_config_existing_efs_id = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.gitlab_config_efs[0].resource_tag_mapping_list[0].resource_arn), null)

  n8n_existing_efs_count         = length(data.aws_resourcegroupstaggingapi_resources.n8n_efs.resource_tag_mapping_list)
  sulu_existing_efs_count        = length(data.aws_resourcegroupstaggingapi_resources.sulu_efs.resource_tag_mapping_list)
  zulip_existing_efs_count       = length(data.aws_resourcegroupstaggingapi_resources.zulip_efs.resource_tag_mapping_list)
  pgadmin_existing_efs_count     = length(data.aws_resourcegroupstaggingapi_resources.pgadmin_efs.resource_tag_mapping_list)
  exastro_existing_efs_count     = length(data.aws_resourcegroupstaggingapi_resources.exastro_efs.resource_tag_mapping_list)
  keycloak_existing_efs_count    = length(data.aws_resourcegroupstaggingapi_resources.keycloak_efs.resource_tag_mapping_list)
  odoo_existing_efs_count        = length(data.aws_resourcegroupstaggingapi_resources.odoo_efs.resource_tag_mapping_list)
  gitlab_data_existing_efs_count = length(try(data.aws_resourcegroupstaggingapi_resources.gitlab_data_efs[0].resource_tag_mapping_list, []))
  gitlab_config_existing_efs_count = length(
    try(data.aws_resourcegroupstaggingapi_resources.gitlab_config_efs[0].resource_tag_mapping_list, [])
  )
}

locals {
  # Keep EFS resources managed unless an explicit filesystem_id is provided.
  create_n8n_efs_effective           = (var.create_n8n_efs || (var.create_ecs && var.create_n8n)) && var.n8n_filesystem_id == null && (var.manage_existing_efs || local.n8n_existing_efs_count == 0)
  create_sulu_efs_effective          = (var.create_sulu_efs || (var.create_ecs && var.create_sulu)) && var.sulu_filesystem_id == null && (var.manage_existing_efs || local.sulu_existing_efs_count == 0)
  create_zulip_efs_effective         = (var.create_zulip_efs || (var.create_ecs && var.create_zulip)) && var.zulip_filesystem_id == null && (var.manage_existing_efs || local.zulip_existing_efs_count == 0)
  create_pgadmin_efs_effective       = (var.create_pgadmin_efs || (var.create_ecs && var.create_pgadmin)) && var.pgadmin_filesystem_id == null && (var.manage_existing_efs || local.pgadmin_existing_efs_count == 0)
  create_exastro_efs_effective       = (var.create_exastro_efs || (var.create_ecs && local.exastro_service_enabled)) && var.exastro_filesystem_id == null && (var.manage_existing_efs || local.exastro_existing_efs_count == 0)
  create_keycloak_efs_effective      = (var.create_keycloak_efs || (var.create_ecs && var.create_keycloak)) && trimspace(var.keycloak_filesystem_id != null ? var.keycloak_filesystem_id : "") == "" && (var.manage_existing_efs || local.keycloak_existing_efs_count == 0)
  create_odoo_efs_effective          = (var.create_odoo_efs || (var.create_ecs && var.create_odoo)) && var.odoo_filesystem_id == null && (var.manage_existing_efs || local.odoo_existing_efs_count == 0)
  create_gitlab_data_efs_effective   = (var.create_gitlab_data_efs || (var.create_ecs && var.create_gitlab)) && var.gitlab_data_filesystem_id == null && (var.manage_existing_efs || local.gitlab_data_existing_efs_count == 0)
  create_gitlab_config_efs_effective = (var.create_gitlab_config_efs || (var.create_ecs && var.create_gitlab)) && var.gitlab_config_filesystem_id == null && (var.manage_existing_efs || local.gitlab_config_existing_efs_count == 0)
}

resource "aws_security_group" "n8n_efs" {
  count = local.create_n8n_efs_effective && var.n8n_filesystem_id == null ? 1 : 0

  name        = local.n8n_efs_sg
  description = "EFS access for n8n"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.n8n_efs_sg })
}

resource "aws_security_group" "sulu_efs" {
  count = local.create_sulu_efs_effective && var.sulu_filesystem_id == null ? 1 : 0

  name        = local.sulu_efs_sg
  description = "EFS access for sulu"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.sulu_efs_sg })
}

resource "aws_security_group" "zulip_efs" {
  count = local.create_zulip_efs_effective && var.zulip_filesystem_id == null ? 1 : 0

  name        = local.zulip_efs_sg
  description = "EFS access for Zulip"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.zulip_efs_sg })
}

resource "aws_security_group" "exastro_efs" {
  count = local.create_exastro_efs_effective && var.exastro_filesystem_id == null ? 1 : 0

  name        = local.exastro_efs_sg
  description = "EFS access for Exastro ITA"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.exastro_efs_sg })
}

resource "aws_security_group" "keycloak_efs" {
  count = local.create_keycloak_efs_effective && var.keycloak_filesystem_id == null ? 1 : 0

  name        = local.keycloak_efs_sg
  description = "EFS access for Keycloak"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.keycloak_efs_sg })
}

resource "aws_security_group" "odoo_efs" {
  count = local.create_odoo_efs_effective && var.odoo_filesystem_id == null ? 1 : 0

  name        = local.odoo_efs_sg
  description = "EFS access for Odoo"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.odoo_efs_sg })
}

resource "aws_security_group" "pgadmin_efs" {
  count = local.create_pgadmin_efs_effective && var.pgadmin_filesystem_id == null ? 1 : 0

  name        = local.pgadmin_efs_sg
  description = "EFS access for pgAdmin"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.pgadmin_efs_sg })
}

resource "aws_security_group" "gitlab_data_efs" {
  count = local.manage_gitlab_data_mount_targets ? 1 : 0

  name        = local.gitlab_data_efs_sg
  description = "EFS access for GitLab data"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.gitlab_data_efs_sg })
}

resource "aws_security_group" "gitlab_config_efs" {
  count = local.manage_gitlab_config_mount_targets ? 1 : 0

  name        = local.gitlab_config_efs_sg
  description = "EFS access for GitLab config"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.gitlab_config_efs_sg })
}

resource "aws_efs_file_system" "n8n" {
  # Always keep the managed EFS when not explicitly pointing to an external ID
  count = local.create_n8n_efs_effective && var.n8n_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.n8n_efs_az

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.n8n_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.n8n_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.n8n_efs_name })
}

locals {
  n8n_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "n8n" {
  count = local.create_n8n_efs_effective ? 1 : 0

  file_system_id  = local.n8n_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.n8n_efs_subnet.name]
  security_groups = [aws_security_group.n8n_efs[0].id]
}

locals {
  n8n_filesystem_id_effective = (
    var.n8n_filesystem_id != null && var.n8n_filesystem_id != "" ? var.n8n_filesystem_id :
    local.n8n_existing_efs_id != null && local.n8n_existing_efs_id != "" ? local.n8n_existing_efs_id :
    local.create_n8n_efs_effective ? try(aws_efs_file_system.n8n[0].id, null) : null
  )
}

resource "aws_efs_file_system" "sulu" {
  count = local.create_sulu_efs_effective && var.sulu_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.sulu_efs_az

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.sulu_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.sulu_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.sulu_efs_name })
}

locals {
  sulu_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "sulu" {
  count = local.create_sulu_efs_effective ? 1 : 0

  file_system_id  = local.sulu_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.sulu_efs_subnet.name]
  security_groups = [aws_security_group.sulu_efs[0].id]
}

locals {
  sulu_filesystem_id_effective = (
    var.sulu_filesystem_id != null && var.sulu_filesystem_id != "" ? var.sulu_filesystem_id :
    local.sulu_existing_efs_id != null && local.sulu_existing_efs_id != "" ? local.sulu_existing_efs_id :
    local.create_sulu_efs_effective ? try(aws_efs_file_system.sulu[0].id, null) : null
  )
}

resource "aws_efs_file_system" "zulip" {
  # Always keep the managed EFS when not explicitly pointing to an external ID
  count = local.create_zulip_efs_effective && var.zulip_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.zulip_efs_az

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.zulip_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.zulip_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.zulip_efs_name })
}

resource "aws_efs_file_system" "keycloak" {
  # Always keep the managed EFS when not explicitly pointing to an external ID
  count = local.create_keycloak_efs_effective && var.keycloak_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.keycloak_efs_az

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.keycloak_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.keycloak_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.keycloak_efs_name })
}

resource "aws_efs_file_system" "odoo" {
  count = local.create_odoo_efs_effective && var.odoo_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.odoo_efs_az

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.odoo_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.odoo_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.odoo_efs_name })
}

resource "aws_efs_file_system" "pgadmin" {
  # Always keep the managed EFS when not explicitly pointing to an external ID
  count = local.create_pgadmin_efs_effective && var.pgadmin_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.pgadmin_efs_az

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.pgadmin_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.pgadmin_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.pgadmin_efs_name })
}

resource "aws_efs_file_system" "exastro" {
  # Always keep the managed EFS when not explicitly pointing to an external ID
  count = local.create_exastro_efs_effective && var.exastro_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.exastro_efs_az

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.exastro_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.exastro_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.exastro_efs_name })
}

resource "aws_efs_file_system" "gitlab_data" {
  count = local.create_gitlab_data_efs_effective && var.gitlab_data_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.gitlab_data_efs_az
  throughput_mode        = "elastic"

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.gitlab_data_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.gitlab_data_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.gitlab_data_efs_name })
}

resource "aws_efs_file_system" "gitlab_config" {
  count = local.create_gitlab_config_efs_effective && var.gitlab_config_filesystem_id == null ? 1 : 0

  performance_mode       = "generalPurpose"
  encrypted              = true
  availability_zone_name = local.gitlab_config_efs_az
  throughput_mode        = "elastic"

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.gitlab_config_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.gitlab_config_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.gitlab_config_efs_name })
}

locals {
  zulip_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "zulip" {
  count = local.create_zulip_efs_effective ? 1 : 0

  file_system_id  = local.zulip_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.zulip_efs_subnet.name]
  security_groups = [aws_security_group.zulip_efs[0].id]
}

locals {
  zulip_filesystem_id_effective = (
    var.zulip_filesystem_id != null && var.zulip_filesystem_id != "" ? var.zulip_filesystem_id :
    local.zulip_existing_efs_id != null && local.zulip_existing_efs_id != "" ? local.zulip_existing_efs_id :
    local.create_zulip_efs_effective ? try(aws_efs_file_system.zulip[0].id, null) : null
  )
}

locals {
  exastro_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "exastro" {
  count = local.create_exastro_efs_effective ? 1 : 0

  file_system_id  = local.exastro_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.exastro_efs_subnet.name]
  security_groups = [aws_security_group.exastro_efs[0].id]
}

locals {
  exastro_filesystem_id_effective = (
    var.exastro_filesystem_id != null && var.exastro_filesystem_id != "" ? var.exastro_filesystem_id :
    local.exastro_existing_efs_id != null && local.exastro_existing_efs_id != "" ? local.exastro_existing_efs_id :
    local.create_exastro_efs_effective ? try(aws_efs_file_system.exastro[0].id, null) : null
  )
}

locals {
  keycloak_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "keycloak" {
  count = local.create_keycloak_efs_effective ? 1 : 0

  file_system_id  = local.keycloak_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.keycloak_efs_subnet.name]
  security_groups = [aws_security_group.keycloak_efs[0].id]
}

locals {
  keycloak_filesystem_id_effective = (
    var.keycloak_filesystem_id != null && var.keycloak_filesystem_id != "" ? var.keycloak_filesystem_id :
    local.keycloak_existing_efs_id != null && local.keycloak_existing_efs_id != "" ? local.keycloak_existing_efs_id :
    local.create_keycloak_efs_effective ? try(aws_efs_file_system.keycloak[0].id, null) : null
  )
}

locals {
  odoo_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "odoo" {
  count = local.create_odoo_efs_effective ? 1 : 0

  file_system_id  = local.odoo_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.odoo_efs_subnet.name]
  security_groups = [aws_security_group.odoo_efs[0].id]
}

locals {
  odoo_filesystem_id_effective = (
    var.odoo_filesystem_id != null && var.odoo_filesystem_id != "" ? var.odoo_filesystem_id :
    local.odoo_existing_efs_id != null && local.odoo_existing_efs_id != "" ? local.odoo_existing_efs_id :
    local.create_odoo_efs_effective ? try(aws_efs_file_system.odoo[0].id, null) : null
  )
}

locals {
  pgadmin_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "pgadmin" {
  count = local.create_pgadmin_efs_effective ? 1 : 0

  file_system_id  = local.pgadmin_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.pgadmin_efs_subnet.name]
  security_groups = [aws_security_group.pgadmin_efs[0].id]
}

locals {
  pgadmin_filesystem_id_effective = (
    var.pgadmin_filesystem_id != null && var.pgadmin_filesystem_id != "" ? var.pgadmin_filesystem_id :
    local.pgadmin_existing_efs_id != null && local.pgadmin_existing_efs_id != "" ? local.pgadmin_existing_efs_id :
    local.create_pgadmin_efs_effective ? try(aws_efs_file_system.pgadmin[0].id, null) : null
  )
}

locals {
  manage_gitlab_data_mount_targets = var.create_gitlab && (
    local.create_gitlab_data_efs_effective ||
    (var.gitlab_data_filesystem_id != null && var.gitlab_data_filesystem_id != "")
  )
  manage_gitlab_config_mount_targets = var.create_gitlab && (
    local.create_gitlab_config_efs_effective ||
    (var.gitlab_config_filesystem_id != null && var.gitlab_config_filesystem_id != "")
  )
  gitlab_data_efs_subnet_ids = {
    for k, v in local.private_subnet_ids :
    k => v if try(local.private_subnets_map[k].az, null) == local.gitlab_data_efs_az
  }
  gitlab_config_efs_subnet_ids = {
    for k, v in local.private_subnet_ids :
    k => v if try(local.private_subnets_map[k].az, null) == local.gitlab_config_efs_az
  }
}

locals {
  gitlab_data_access_point_uid_effective   = coalesce(var.gitlab_data_access_point_uid, 998)
  gitlab_data_access_point_gid_effective   = coalesce(var.gitlab_data_access_point_gid, 998)
  gitlab_config_access_point_uid_effective = coalesce(var.gitlab_config_access_point_uid, 0)
  gitlab_config_access_point_gid_effective = coalesce(var.gitlab_config_access_point_gid, 0)
}

resource "aws_efs_mount_target" "gitlab_data" {
  for_each = local.manage_gitlab_data_mount_targets ? local.gitlab_data_efs_subnet_ids : {}

  file_system_id  = local.gitlab_data_filesystem_id_effective
  subnet_id       = each.value
  security_groups = [aws_security_group.gitlab_data_efs[0].id]
}

resource "aws_efs_mount_target" "gitlab_config" {
  for_each = local.manage_gitlab_config_mount_targets ? local.gitlab_config_efs_subnet_ids : {}

  file_system_id  = local.gitlab_config_filesystem_id_effective
  subnet_id       = each.value
  security_groups = [aws_security_group.gitlab_config_efs[0].id]
}

resource "aws_efs_access_point" "gitlab_data" {
  count = local.create_gitlab_data_access_point ? 1 : 0

  file_system_id = local.gitlab_data_filesystem_id_effective
  posix_user {
    gid = local.gitlab_data_access_point_gid_effective
    uid = local.gitlab_data_access_point_uid_effective
  }
  root_directory {
    path = var.gitlab_data_access_point_root_path
    creation_info {
      owner_gid   = local.gitlab_data_access_point_gid_effective
      owner_uid   = local.gitlab_data_access_point_uid_effective
      permissions = var.gitlab_access_point_permissions
    }
  }
}

resource "aws_efs_access_point" "gitlab_config" {
  count = local.create_gitlab_config_access_point ? 1 : 0

  file_system_id = local.gitlab_config_filesystem_id_effective
  posix_user {
    gid = local.gitlab_config_access_point_gid_effective
    uid = local.gitlab_config_access_point_uid_effective
  }
  root_directory {
    path = var.gitlab_config_access_point_root_path
    creation_info {
      owner_gid   = local.gitlab_config_access_point_gid_effective
      owner_uid   = local.gitlab_config_access_point_uid_effective
      permissions = var.gitlab_access_point_permissions
    }
  }
}

locals {
  gitlab_data_access_point_id_effective = (
    var.gitlab_data_access_point_id != null && var.gitlab_data_access_point_id != "" ? var.gitlab_data_access_point_id :
    local.create_gitlab_data_access_point ? aws_efs_access_point.gitlab_data[0].id : null
  )
  gitlab_config_access_point_id_effective = (
    var.gitlab_config_access_point_id != null && var.gitlab_config_access_point_id != "" ? var.gitlab_config_access_point_id :
    local.create_gitlab_config_access_point ? aws_efs_access_point.gitlab_config[0].id : null
  )
}

locals {
  gitlab_data_filesystem_id_effective = (
    var.gitlab_data_filesystem_id != null && var.gitlab_data_filesystem_id != "" ? var.gitlab_data_filesystem_id :
    local.gitlab_data_existing_efs_id != null && local.gitlab_data_existing_efs_id != "" ? local.gitlab_data_existing_efs_id :
    local.create_gitlab_data_efs_effective ? try(aws_efs_file_system.gitlab_data[0].id, null) : null
  )
  gitlab_config_filesystem_id_effective = (
    var.gitlab_config_filesystem_id != null && var.gitlab_config_filesystem_id != "" ? var.gitlab_config_filesystem_id :
    local.gitlab_config_existing_efs_id != null && local.gitlab_config_existing_efs_id != "" ? local.gitlab_config_existing_efs_id :
    local.create_gitlab_config_efs_effective ? try(aws_efs_file_system.gitlab_config[0].id, null) : null
  )
}

locals {
  create_gitlab_data_access_point = (
    var.create_ecs && var.create_gitlab &&
    (var.gitlab_data_access_point_id == null || var.gitlab_data_access_point_id == "")
  )
  create_gitlab_config_access_point = (
    var.create_ecs && var.create_gitlab &&
    (var.gitlab_config_access_point_id == null || var.gitlab_config_access_point_id == "")
  )
}

locals {
  grafana_efs_name = "${local.name_prefix}-grafana-efs"
  grafana_efs_sg   = "${local.name_prefix}-grafana-efs-sg"
  grafana_efs_az   = coalesce(var.grafana_efs_availability_zone, try(local.private_subnets[0].az, null), "${var.region}a")
}

data "aws_resourcegroupstaggingapi_resources" "grafana_efs" {
  resource_type_filters = ["elasticfilesystem"]

  tag_filter {
    key    = "Name"
    values = [local.grafana_efs_name]
  }
}

locals {
  grafana_existing_efs_id      = try(regex("fs-[0-9a-f]+", data.aws_resourcegroupstaggingapi_resources.grafana_efs.resource_tag_mapping_list[0].resource_arn), null)
  grafana_existing_efs_count   = length(data.aws_resourcegroupstaggingapi_resources.grafana_efs.resource_tag_mapping_list)
  create_grafana_efs_effective = (var.create_grafana_efs || (var.create_ecs && var.create_grafana)) && var.grafana_filesystem_id == null && (var.manage_existing_efs || local.grafana_existing_efs_count == 0)
}

resource "aws_security_group" "grafana_efs" {
  count = local.create_grafana_efs_effective && var.grafana_filesystem_id == null ? 1 : 0

  name        = local.grafana_efs_sg
  description = "EFS access for Grafana"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.grafana_efs_sg })
}

locals {
  grafana_filesystem_id_effective = (
    var.grafana_filesystem_id != null && var.grafana_filesystem_id != "" ? var.grafana_filesystem_id :
    local.grafana_existing_efs_id != null && local.grafana_existing_efs_id != "" ? local.grafana_existing_efs_id :
    local.create_grafana_efs_effective ? try(aws_efs_file_system.grafana[0].id, null) : null
  )
}

resource "aws_efs_file_system" "grafana" {
  count = local.create_grafana_efs_effective && var.grafana_filesystem_id == null ? 1 : 0

  availability_zone_name = local.grafana_efs_az
  encrypted              = true
  throughput_mode        = "elastic"

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.manage_existing_efs || local.grafana_existing_efs_count == 0
      error_message = "Existing EFS detected for ${local.grafana_efs_name}. Import or reference it instead of creating a new one."
    }
  }

  tags = merge(local.tags, { Name = local.grafana_efs_name })
}

locals {
  grafana_efs_subnet = length(local.private_subnets) > 0 ? local.private_subnets[0] : null
}

resource "aws_efs_mount_target" "grafana" {
  count = local.create_grafana_efs_effective ? 1 : 0

  file_system_id  = local.grafana_filesystem_id_effective
  subnet_id       = local.private_subnet_ids[local.grafana_efs_subnet.name]
  security_groups = [aws_security_group.grafana_efs[0].id]
}
