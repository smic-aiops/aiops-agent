locals {
  mysql_rds_identifier        = "${local.name_prefix}-mysql-db"
  mysql_rds_subnet_group_name = "${local.name_prefix}-mysql-subnets"
  mysql_rds_security_group    = "${local.name_prefix}-mysql-rds-sg"
}

resource "aws_security_group" "mysql_rds" {
  count       = var.create_mysql_rds ? 1 : 0
  name        = local.mysql_rds_security_group
  description = "MySQL access"
  vpc_id      = local.vpc_id

  ingress {
    description = "MySQL from ECS services"
    from_port   = 3306
    to_port     = 3306
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

  tags = merge(local.tags, { Name = local.mysql_rds_security_group })
}

locals {
  mysql_rds_sg_id = var.create_mysql_rds ? try(aws_security_group.mysql_rds[0].id, null) : null
}

resource "aws_db_subnet_group" "mysql" {
  count = var.create_mysql_rds ? 1 : 0

  name       = local.mysql_rds_subnet_group_name
  subnet_ids = values(local.private_subnet_ids)

  tags = merge(local.tags, { Name = local.mysql_rds_subnet_group_name })
}

resource "aws_db_instance" "mysql" {
  count = var.create_mysql_rds ? 1 : 0

  identifier = local.mysql_rds_identifier

  engine         = "mysql"
  engine_version = var.mysql_rds_engine_version

  instance_class          = var.mysql_rds_instance_class
  multi_az                = false
  publicly_accessible     = false
  storage_encrypted       = true
  deletion_protection     = var.rds_deletion_protection
  skip_final_snapshot     = var.mysql_rds_skip_final_snapshot
  backup_retention_period = var.mysql_rds_backup_retention

  allocated_storage = var.mysql_rds_allocated_storage
  storage_type      = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.mysql[0].name
  vpc_security_group_ids = [local.mysql_rds_sg_id]

  db_name  = var.mysql_db_name
  username = local.mysql_db_username_value
  password = local.mysql_db_password_value

  tags = merge(local.tags, { Name = local.mysql_rds_identifier })
}
