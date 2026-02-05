locals {
  # zulip_cache_subnet_group_name = "${local.name_prefix}-zulip-cache-subnets"
  # zulip_redis_sg_name           = "${local.name_prefix}-zulip-redis-sg"
  # zulip_memcached_sg_name       = "${local.name_prefix}-zulip-memcached-sg"
  # zulip_mq_sg_name              = "${local.name_prefix}-zulip-mq-sg"
  # zulip_mq_password_effective   = coalesce(var.zulip_mq_password, try(random_password.zulip_mq[0].result, null))
  # zulip_redis_port              = 6379
  # zulip_memcached_port          = 11211
}

locals {
  # zulip_redis_host               = try(aws_elasticache_replication_group.zulip_redis[0].primary_endpoint_address, null)
  # zulip_memcached_endpoint       = try(aws_elasticache_cluster.zulip_memcached[0].configuration_endpoint, null)
  # zulip_memcached_host           = local.zulip_memcached_endpoint != null ? split(":", local.zulip_memcached_endpoint)[0] : null
  # zulip_memcached_port_effective = local.zulip_memcached_endpoint != null && length(split(":", local.zulip_memcached_endpoint)) > 1 ? tonumber(split(":", local.zulip_memcached_endpoint)[1]) : local.zulip_memcached_port
  # zulip_mq_amqp_endpoint         = try(aws_mq_broker.zulip[0].instances[0].endpoints[0], null)
  # zulip_mq_host                  = local.zulip_mq_amqp_endpoint != null ? split(":", replace(replace(local.zulip_mq_amqp_endpoint, "amqps://", ""), "amqp://", ""))[0] : null
  # zulip_mq_port_effective        = local.zulip_mq_amqp_endpoint != null && length(split(":", replace(replace(local.zulip_mq_amqp_endpoint, "amqps://", ""), "amqp://", ""))) > 1 ? tonumber(split(":", replace(replace(local.zulip_mq_amqp_endpoint, "amqps://", ""), "amqp://", ""))[1]) : var.zulip_mq_port
}

# resource "aws_elasticache_subnet_group" "zulip" {
#   count = var.create_ecs && var.create_zulip && length(local.private_subnet_ids) > 0 ? 1 : 0

#   name       = local.zulip_cache_subnet_group_name
#   subnet_ids = values(local.private_subnet_ids)

#   tags = merge(local.tags, { Name = local.zulip_cache_subnet_group_name })
# }

# resource "aws_security_group" "zulip_redis" {
#   count = var.create_ecs && var.create_zulip ? 1 : 0

#   name        = local.zulip_redis_sg_name
#   description = "ElastiCache Redis access for Zulip"
#   vpc_id      = local.vpc_id

#   ingress {
#     from_port       = local.zulip_redis_port
#     to_port         = local.zulip_redis_port
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_service[0].id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = merge(local.tags, { Name = local.zulip_redis_sg_name })
# }

# resource "aws_security_group" "zulip_memcached" {
#   count = var.create_ecs && var.create_zulip ? 1 : 0

#   name        = local.zulip_memcached_sg_name
#   description = "ElastiCache Memcached access for Zulip"
#   vpc_id      = local.vpc_id

#   ingress {
#     from_port       = local.zulip_memcached_port
#     to_port         = local.zulip_memcached_port
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_service[0].id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = merge(local.tags, { Name = local.zulip_memcached_sg_name })
# }

# resource "aws_elasticache_replication_group" "zulip_redis" {
#   count = var.create_ecs && var.create_zulip && length(local.private_subnet_ids) > 0 ? 1 : 0

#   replication_group_id       = "${local.name_prefix}-zulip-redis"
#   description                = "Redis for Zulip"
#   engine                     = "redis"
#   engine_version             = var.zulip_redis_engine_version
#   node_type                  = var.zulip_redis_node_type
#   num_cache_clusters         = 1
#   automatic_failover_enabled = false
#   auto_minor_version_upgrade = true
#   port                       = local.zulip_redis_port
#   at_rest_encryption_enabled = true
#   transit_encryption_enabled = false
#   apply_immediately          = true
#   maintenance_window         = var.zulip_redis_maintenance_window
#   subnet_group_name          = aws_elasticache_subnet_group.zulip[0].name
#   security_group_ids         = [aws_security_group.zulip_redis[0].id]
#   snapshot_retention_limit   = 0
#   multi_az_enabled           = false
#   parameter_group_name       = var.zulip_redis_parameter_group
# }

# resource "aws_elasticache_cluster" "zulip_memcached" {
#   count = var.create_ecs && var.create_zulip && length(local.private_subnet_ids) > 0 ? 1 : 0

#   cluster_id           = "${local.name_prefix}-zulip-memcached"
#   engine               = "memcached"
#   node_type            = var.zulip_memcached_node_type
#   num_cache_nodes      = var.zulip_memcached_nodes
#   parameter_group_name = var.zulip_memcached_parameter_group
#   port                 = local.zulip_memcached_port
#   subnet_group_name    = aws_elasticache_subnet_group.zulip[0].name
#   security_group_ids   = [aws_security_group.zulip_memcached[0].id]
#   az_mode              = "single-az"

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-memcached" })
# }

# resource "random_password" "zulip_mq" {
#   count            = var.create_ecs && var.create_zulip && var.zulip_mq_password == null ? 1 : 0
#   length           = 24
#   lower            = true
#   upper            = true
#   numeric          = true
#   special          = true
#   min_lower        = 1
#   min_upper        = 1
#   min_numeric      = 1
#   min_special      = 1
#   override_special = "!#$%&*+-=?"
# }

# resource "aws_security_group" "zulip_mq" {
#   count = var.create_ecs && var.create_zulip ? 1 : 0

#   name        = local.zulip_mq_sg_name
#   description = "Amazon MQ (RabbitMQ) access for Zulip"
#   vpc_id      = local.vpc_id

#   ingress {
#     from_port       = var.zulip_mq_port
#     to_port         = var.zulip_mq_port
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_service[0].id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = merge(local.tags, { Name = local.zulip_mq_sg_name })
# }

# resource "aws_mq_broker" "zulip" {
#   count = var.create_ecs && var.create_zulip && length(local.private_subnet_ids) > 0 ? 1 : 0

#   broker_name                = "${local.name_prefix}-zulip-mq"
#   engine_type                = "RabbitMQ"
#   engine_version             = var.zulip_mq_engine_version
#   host_instance_type         = var.zulip_mq_instance_type
#   deployment_mode            = var.zulip_mq_deployment_mode
#   publicly_accessible        = false
#   apply_immediately          = true
#   auto_minor_version_upgrade = true
#   security_groups            = [aws_security_group.zulip_mq[0].id]
#   subnet_ids                 = [local.private_subnet_ids[local.service_subnet_keys[0]]]

#   user {
#     username = var.zulip_mq_username
#     password = local.zulip_mq_password_effective
#   }

#   encryption_options {
#     use_aws_owned_key = true
#   }

#   logs {
#     general = true
#     audit   = false
#   }

#   tags = merge(local.tags, { Name = "${local.name_prefix}-zulip-mq" })
# }
