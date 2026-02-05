data "aws_iam_policy_document" "grafana_cloudwatch" {
  count = var.create_ecs && var.create_grafana ? 1 : 0

  statement {
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetDashboard",
      "cloudwatch:ListDashboards"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "grafana_cloudwatch" {
  count  = var.create_ecs && var.create_grafana ? 1 : 0
  name   = "${local.name_prefix}-grafana-cloudwatch"
  policy = data.aws_iam_policy_document.grafana_cloudwatch[0].json
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  count      = var.create_ecs && var.create_grafana ? 1 : 0
  role       = aws_iam_role.ecs_task[0].name
  policy_arn = aws_iam_policy.grafana_cloudwatch[0].arn
}
