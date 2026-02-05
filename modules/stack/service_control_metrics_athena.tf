locals {
  service_control_metrics_athena_enabled = local.service_control_metrics_stream_enabled && var.enable_service_control_metrics_athena
  service_control_metrics_glue_database_name_effective = lower(replace(
    coalesce(var.service_control_metrics_glue_database_name, "${local.name_prefix}_service_metrics"),
    "-",
    "_"
  ))
  service_control_metrics_glue_table_name_effective = lower(replace(
    coalesce(var.service_control_metrics_glue_table_name, "service_metrics"),
    "-",
    "_"
  ))
  service_control_metrics_athena_prefix_effective = trim(var.service_control_metrics_athena_prefix, "/")
  service_control_metrics_athena_location = local.service_control_metrics_athena_prefix_effective != "" ? (
    "s3://${local.service_control_metrics_bucket_name}/${local.service_control_metrics_athena_prefix_effective}/"
  ) : "s3://${local.service_control_metrics_bucket_name}/"
}

resource "aws_glue_catalog_database" "service_control_metrics" {
  count = local.service_control_metrics_athena_enabled ? 1 : 0

  name = local.service_control_metrics_glue_database_name_effective

  tags = merge(local.tags, { Name = "${local.name_prefix}-service-metrics-db" })
}

resource "aws_glue_catalog_table" "service_control_metrics" {
  count         = local.service_control_metrics_athena_enabled ? 1 : 0
  name          = local.service_control_metrics_glue_table_name_effective
  database_name = aws_glue_catalog_database.service_control_metrics[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "json"
  }

  storage_descriptor {
    location      = local.service_control_metrics_athena_location
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "metric_stream_name"
      type = "string"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
    columns {
      name = "namespace"
      type = "string"
    }
    columns {
      name = "metric_name"
      type = "string"
    }
    columns {
      name = "dimensions"
      type = "map<string,string>"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
    columns {
      name = "value"
      type = "double"
    }
    columns {
      name = "unit"
      type = "string"
    }
  }
}
