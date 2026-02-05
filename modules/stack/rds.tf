locals {
  rds_identifier           = coalesce(var.rds_identifier, "${local.name_prefix}-pg")
  rds_subnet_group_name    = "${local.name_prefix}-db-subnets"
  rds_security_group_name  = "${local.name_prefix}-rds-sg"
  rds_parameter_group_name = "${local.name_prefix}-pg-params"
  rds_parameter_family     = "postgres${split(".", var.rds_engine_version)[0]}"
  master_username          = coalesce(var.pg_db_username, "${var.platform}user")
  # RDS master password: 8-128 chars, must include upper/lower/digit/special, avoid "/" and "\"".
  db_password_effective = var.create_rds ? coalesce(var.pg_db_password, try(random_password.master[0].result, null)) : var.pg_db_password
}

resource "aws_security_group" "rds" {
  count       = var.create_rds ? 1 : 0
  name        = local.rds_security_group_name
  description = "PostgreSQL access"
  vpc_id      = local.vpc_id

  ingress {
    description = "Postgres from ECS services"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.ecs_service[0].id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.rds_security_group_name })
}

locals {
  rds_sg_id = var.create_rds ? try(aws_security_group.rds[0].id, null) : null
}

resource "random_password" "master" {
  count            = var.create_rds && var.pg_db_password == null ? 1 : 0
  length           = 16
  lower            = true
  upper            = true
  numeric          = true
  special          = true
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%^&*()-_+=" # exclude '/', '"', '@'
}

resource "aws_db_subnet_group" "this" {
  count = var.create_rds ? 1 : 0

  name       = local.rds_subnet_group_name
  subnet_ids = values(local.private_subnet_ids)

  tags = merge(local.tags, { Name = local.rds_subnet_group_name })
}

resource "aws_db_parameter_group" "postgres" {
  count = var.create_rds ? 1 : 0

  name   = local.rds_parameter_group_name
  family = local.rds_parameter_family

  parameter {
    name         = "max_locks_per_transaction"
    value        = tostring(var.rds_max_locks_per_transaction)
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "0"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_connections"
    value        = var.rds_log_connections ? "1" : "0"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = var.rds_log_disconnections ? "1" : "0"
    apply_method = "immediate"
  }

  tags = merge(local.tags, { Name = local.rds_parameter_group_name })
}

resource "aws_db_instance" "this" {
  count = var.create_rds ? 1 : 0

  identifier = local.rds_identifier

  engine         = "postgres"
  engine_version = var.rds_engine_version

  instance_class          = var.rds_instance_class
  multi_az                = false
  publicly_accessible     = false
  storage_encrypted       = true
  deletion_protection     = var.rds_deletion_protection
  skip_final_snapshot     = var.rds_skip_final_snapshot
  apply_immediately       = true
  backup_retention_period = var.rds_backup_retention

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"

  parameter_group_name   = aws_db_parameter_group.postgres[0].name
  db_subnet_group_name   = aws_db_subnet_group.this[0].name
  vpc_security_group_ids = [local.rds_sg_id]

  db_name  = var.pg_db_name
  username = local.master_username
  password = local.db_password_effective

  performance_insights_enabled          = var.rds_performance_insights_enabled
  performance_insights_retention_period = var.rds_performance_insights_enabled ? var.rds_performance_insights_retention_period : null

  tags = merge(local.tags, { Name = local.rds_identifier })
}
