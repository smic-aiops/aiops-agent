locals {
  service_logs_athena_enabled = var.enable_service_logs_athena && var.create_ecs
  service_logs_glue_database_name_effective = lower(replace(
    coalesce(var.service_logs_glue_database_name, "${local.name_prefix}_service_logs"),
    "-",
    "_"
  ))
  n8n_logs_athena_enabled     = local.service_logs_athena_enabled && lookup(local.logs_to_s3_service_map, "n8n", false)
  grafana_logs_athena_enabled = local.service_logs_athena_enabled && lookup(local.logs_to_s3_service_map, "grafana", false) && var.create_grafana
  n8n_logs_athena_location    = "s3://${local.n8n_logs_bucket_name}/${local.n8n_logs_prefix_effective}/"
  grafana_logs_athena_locations = {
    for realm in local.grafana_realms :
    realm => "s3://${local.grafana_logs_bucket_name}/${replace(local.grafana_logs_prefix_effective, "!{partitionKeyFromQuery:realm}", realm)}/"
  }
  grafana_logs_athena_table_names_by_realm = {
    for realm in local.grafana_realms :
    realm => lower(replace("grafana_logs_${realm}", "/[^A-Za-z0-9]+/", "_"))
  }
  service_logs_athena_targets = local.service_logs_athena_enabled ? {
    for item in flatten([
      for service, realms in local.service_logs_realms_by_service : [
        for realm in realms : {
          service    = service
          realm      = realm
          table_name = length(realms) > 1 ? "${service}_logs_${realm}" : "${service}_logs"
          location   = "s3://${local.service_logs_bucket_name_by_service[service]}/${local.service_logs_prefix_by_service_realm[service][realm]}/"
        }
      ]
    ]) : "${item.service}::${item.realm}" => item
  } : {}
  service_logs_athena_table_names = {
    for key, target in local.service_logs_athena_targets :
    key => lower(replace(target.table_name, "/[^A-Za-z0-9]+/", "_"))
  }
}

resource "aws_glue_catalog_database" "service_logs" {
  count = local.service_logs_athena_enabled ? 1 : 0

  name = local.service_logs_glue_database_name_effective

  tags = merge(local.tags, { Name = "${local.name_prefix}-service-logs-db" })
}

resource "aws_glue_catalog_table" "n8n_logs" {
  count         = local.n8n_logs_athena_enabled ? 1 : 0
  name          = "n8n_logs"
  database_name = aws_glue_catalog_database.service_logs[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "json"
  }

  storage_descriptor {
    location      = local.n8n_logs_athena_location
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "timestamp"
      type = "bigint"
    }
    columns {
      name = "message"
      type = "string"
    }
    columns {
      name = "log_group"
      type = "string"
    }
    columns {
      name = "log_stream"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "grafana_logs" {
  for_each      = local.grafana_logs_athena_enabled ? local.grafana_logs_athena_table_names_by_realm : {}
  name          = each.value
  database_name = aws_glue_catalog_database.service_logs[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "json"
  }

  storage_descriptor {
    location      = local.grafana_logs_athena_locations[each.key]
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "timestamp"
      type = "bigint"
    }
    columns {
      name = "message"
      type = "string"
    }
    columns {
      name = "log_group"
      type = "string"
    }
    columns {
      name = "log_stream"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "service_logs" {
  for_each      = local.service_logs_athena_targets
  name          = local.service_logs_athena_table_names[each.key]
  database_name = aws_glue_catalog_database.service_logs[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "json"
  }

  storage_descriptor {
    location      = each.value.location
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "timestamp"
      type = "bigint"
    }
    columns {
      name = "message"
      type = "string"
    }
    columns {
      name = "log_group"
      type = "string"
    }
    columns {
      name = "log_stream"
      type = "string"
    }
  }
}
