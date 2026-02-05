locals {
  hosted_zone_name_input = coalesce(
    var.hosted_zone_name != null ? trim(var.hosted_zone_name, ".") : null,
    try(data.aws_route53_zone.by_id[0].name, null)
  )
  hosted_zone_name_fqdn = local.hosted_zone_name_input != null ? "${local.hosted_zone_name_input}." : null
  hosted_zone_tag_name  = coalesce(var.hosted_zone_tag_name, local.hosted_zone_name_input)
}

# Try to find existing public hosted zone by name when create_hosted_zone = false
data "aws_route53_zone" "existing" {
  count        = var.create_hosted_zone || var.hosted_zone_name == null ? 0 : 1
  name         = "${trim(var.hosted_zone_name, ".")}."
  private_zone = false
}

data "aws_route53_zone" "by_id" {
  count   = var.create_hosted_zone || var.hosted_zone_id == null || var.hosted_zone_name != null ? 0 : 1
  zone_id = var.hosted_zone_id
}

resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0

  name          = local.hosted_zone_name_fqdn
  force_destroy = var.hosted_zone_force_destroy
  comment       = var.hosted_zone_comment

  tags = merge(local.tags, { Name = local.hosted_zone_tag_name })
}

locals {
  hosted_zone_id = coalesce(
    try(data.aws_route53_zone.existing[0].zone_id, null),
    try(data.aws_route53_zone.by_id[0].zone_id, null),
    try(aws_route53_zone.this[0].zone_id, null)
  )
  hosted_zone_name_servers = coalesce(
    try(data.aws_route53_zone.existing[0].name_servers, null),
    try(aws_route53_zone.this[0].name_servers, null),
    try(data.aws_route53_zone.by_id[0].name_servers, null)
  )
}
