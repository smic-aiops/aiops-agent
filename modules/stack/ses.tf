locals {
  ses_domain           = coalesce(var.ses_domain, local.hosted_zone_name_input)
  ses_smtp_user_name   = coalesce(var.ses_smtp_user_name, "${local.name_prefix}-ses-smtp")
  ses_smtp_policy_name = coalesce(var.ses_smtp_policy_name, "${local.name_prefix}-ses-send-email")
}

resource "aws_ses_domain_identity" "this" {
  count  = var.create_ses ? 1 : 0
  domain = local.ses_domain
}

resource "aws_ses_domain_dkim" "this" {
  count  = var.create_ses ? 1 : 0
  domain = aws_ses_domain_identity.this[0].domain
}

resource "aws_route53_record" "ses_verification" {
  count = var.create_ses ? 1 : 0

  zone_id         = local.hosted_zone_id
  name            = "_amazonses.${aws_ses_domain_identity.this[0].domain}"
  type            = "TXT"
  ttl             = 300
  records         = [aws_ses_domain_identity.this[0].verification_token]
  allow_overwrite = true
}

resource "aws_route53_record" "ses_dkim" {
  # SES always returns 3 DKIM tokens; use static keys (0,1,2) so for_each keys are known at plan time.
  for_each = var.create_ses ? { for idx in range(3) : idx => aws_ses_domain_dkim.this[0].dkim_tokens[idx] } : {}

  zone_id         = local.hosted_zone_id
  name            = "${each.value}._domainkey.${aws_ses_domain_identity.this[0].domain}"
  type            = "CNAME"
  ttl             = 300
  records         = ["${each.value}.dkim.amazonses.com"]
  allow_overwrite = true
}

resource "aws_iam_user" "ses_smtp" {
  count = var.enable_ses_smtp_auto ? 1 : 0

  name          = local.ses_smtp_user_name
  force_destroy = true

  tags = merge(local.tags, { Name = local.ses_smtp_user_name })
}

resource "aws_iam_policy" "ses_smtp" {
  count = var.enable_ses_smtp_auto ? 1 : 0

  name        = local.ses_smtp_policy_name
  path        = "/"
  description = "Allow sending email via SES SMTP for ${local.name_prefix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "ses_smtp" {
  count = var.enable_ses_smtp_auto ? 1 : 0

  user       = aws_iam_user.ses_smtp[0].name
  policy_arn = aws_iam_policy.ses_smtp[0].arn
}

resource "aws_iam_access_key" "ses_smtp" {
  count = var.enable_ses_smtp_auto ? 1 : 0

  user = aws_iam_user.ses_smtp[0].name

  lifecycle {
    create_before_destroy = true
  }
}
