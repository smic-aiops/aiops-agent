locals {
  name_prefix = coalesce(var.name_prefix, "${var.environment}-${var.platform}")
  keycloak_realm_effective = coalesce(
    var.default_realm != null && var.default_realm != "" ? var.default_realm : null,
    local.name_prefix
  )

  tags = coalesce(var.tags, {})

  default_service_subdomain_map = {
    n8n         = "aiops-agent"
    qdrant      = "qdrant"
    zulip       = "zulip"
    exastro_web = "ita-web"
    exastro_api = "ita-api"
    sulu        = "sulu"
    pgadmin     = "pgadmin"
    keycloak    = "keycloak"
    odoo        = "odoo"
    gitlab      = "gitlab"
    grafana     = "grafana"
  }

  service_subdomain_map = merge(local.default_service_subdomain_map, coalesce(var.service_subdomain_map, {}))

  default_public_subnets = [
    {
      name = "${local.name_prefix}-public-1a"
      cidr = "172.24.0.0/20"
      az   = "${var.region}a"
    },
    {
      name = "${local.name_prefix}-public-1d"
      cidr = "172.24.16.0/20"
      az   = "${var.region}d"
    }
  ]

  default_private_subnets = [
    {
      name = "${local.name_prefix}-private-1a"
      cidr = "172.24.32.0/20"
      az   = "${var.region}a"
    },
    {
      name = "${local.name_prefix}-private-1d"
      cidr = "172.24.48.0/20"
      az   = "${var.region}d"
    }
  ]

  public_subnets  = coalesce(var.public_subnets, local.default_public_subnets)
  private_subnets = coalesce(var.private_subnets, local.default_private_subnets)

  public_subnets_map  = { for s in local.public_subnets : s.name => s }
  private_subnets_map = { for s in local.private_subnets : s.name => s }

  public_subnet_keys = sort(keys(local.public_subnets_map))

  igw_name         = "${local.name_prefix}-igw"
  nat_name         = "${local.name_prefix}-private-nat"
  nat_eip_name     = "${local.name_prefix}-private-nat-eip"
  s3_endpoint_name = "${local.name_prefix}-s3-endpoint"

  vpc_id = coalesce(
    var.existing_vpc_id,
    try(aws_vpc.this[0].id, null)
  )
}

locals {
  create_igw = var.existing_internet_gateway_id == null
}

resource "aws_vpc" "this" {
  count = var.existing_vpc_id == null ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

data "aws_vpc" "selected" {
  id = local.vpc_id
}

resource "aws_default_route_table" "main" {
  default_route_table_id = data.aws_vpc.selected.main_route_table_id

  tags = merge(local.tags, { Name = "${local.name_prefix}-main-rt" })

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.igw_id
  }
}

resource "aws_internet_gateway" "this" {
  count = local.create_igw ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.tags, { Name = local.igw_name })
}

locals {
  igw_id = coalesce(
    var.existing_internet_gateway_id,
    try(aws_internet_gateway.this[0].id, null)
  )
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets_map

  vpc_id                  = local.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = each.value.name })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets_map

  vpc_id            = local.vpc_id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.tags, { Name = each.value.name })
}

locals {
  public_subnet_ids  = { for k, v in aws_subnet.public : k => v.id }
  private_subnet_ids = { for k, v in aws_subnet.private : k => v.id }
}

locals {
  public_route_tables_to_create = { for k, v in local.public_subnets_map : k => v if k != local.public_subnet_keys[0] }
}

resource "aws_route_table" "public" {
  for_each = local.public_route_tables_to_create

  vpc_id = local.vpc_id

  tags = merge(local.tags, { Name = "${each.value.name}-rt" })
}

locals {
  public_route_table_ids = merge(
    { (local.public_subnet_keys[0]) = aws_default_route_table.main.id },
    { for k, v in aws_route_table.public : k => v.id }
  )
}

resource "aws_main_route_table_association" "this" {
  vpc_id         = local.vpc_id
  route_table_id = aws_default_route_table.main.id
}

resource "aws_route" "public_internet" {
  for_each = aws_route_table.public

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.igw_id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_route_table_ids

  subnet_id      = local.public_subnet_ids[each.key]
  route_table_id = each.value
}

locals {
  existing_nat_gateway_id = var.existing_nat_gateway_id
  create_nat_gateway      = local.existing_nat_gateway_id == null
  nat_gateway_id = coalesce(
    local.existing_nat_gateway_id,
    try(aws_nat_gateway.this[0].id, null)
  )
  nat_subnet_id = try(local.public_subnet_ids[local.public_subnet_keys[0]], null)
}

resource "aws_eip" "nat" {
  count  = local.create_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.tags, { Name = local.nat_eip_name })
}

resource "aws_nat_gateway" "this" {
  count = local.create_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = local.nat_subnet_id

  tags = merge(local.tags, { Name = local.nat_name })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets_map

  vpc_id = local.vpc_id

  tags = merge(local.tags, { Name = "${each.value.name}-rt" })
}

locals {
  private_route_table_ids = { for k, v in aws_route_table.private : k => v.id }
}

resource "aws_route" "private_nat" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = local.nat_gateway_id

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_route_table.private

  subnet_id      = local.private_subnet_ids[each.key]
  route_table_id = each.value.id
}

locals {
  interface_vpc_endpoint_services = {
    ssm         = "com.amazonaws.${var.region}.ssm"
    ssmmessages = "com.amazonaws.${var.region}.ssmmessages"
    ec2messages = "com.amazonaws.${var.region}.ec2messages"
    logs        = "com.amazonaws.${var.region}.logs"
    ecs         = "com.amazonaws.${var.region}.ecs"
  }
  interface_vpc_endpoint_sg_name = "${local.name_prefix}-vpce-sg"
  s3_endpoint_route_table_ids_effective = (
    var.s3_endpoint_route_table_ids != null ? var.s3_endpoint_route_table_ids : values(local.private_route_table_ids)
  )
}

resource "aws_security_group" "vpc_endpoints" {
  count = length(local.interface_vpc_endpoint_services) > 0 ? 1 : 0

  name        = local.interface_vpc_endpoint_sg_name
  description = "Interface VPC endpoint access"
  vpc_id      = local.vpc_id

  ingress {
    description = "Interface endpoint HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = local.interface_vpc_endpoint_sg_name })
}

resource "aws_vpc_endpoint" "s3" {
  count = 1

  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.s3_endpoint_route_table_ids_effective

  tags = merge(local.tags, { Name = local.s3_endpoint_name })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_vpc_endpoint_services

  vpc_id              = local.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = values(local.private_subnet_ids)
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}-vpce" })
}

output "new_vpc_id" {
  description = "ID of the newly created VPC"
  value       = local.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = local.private_subnet_ids
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = local.nat_gateway_id
}

output "vpc_endpoint_ids" {
  description = "IDs of created VPC endpoints"
  value = {
    s3          = try(aws_vpc_endpoint.s3[0].id, null)
    ssm         = try(aws_vpc_endpoint.interface["ssm"].id, null)
    ssmmessages = try(aws_vpc_endpoint.interface["ssmmessages"].id, null)
    ec2messages = try(aws_vpc_endpoint.interface["ec2messages"].id, null)
    logs        = try(aws_vpc_endpoint.interface["logs"].id, null)
    ecs         = try(aws_vpc_endpoint.interface["ecs"].id, null)
  }
}
