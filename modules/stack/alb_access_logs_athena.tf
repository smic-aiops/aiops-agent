locals {
  alb_access_logs_athena_enabled = local.alb_access_logs_enabled && var.enable_alb_access_logs_athena
  alb_access_logs_glue_database_name_effective = lower(replace(
    coalesce(var.alb_access_logs_glue_database_name, "${local.name_prefix}_alb_logs"),
    "-",
    "_"
  ))
  alb_access_logs_glue_table_name_effective = lower(replace(
    coalesce(var.alb_access_logs_glue_table_name, "alb_access_logs"),
    "-",
    "_"
  ))
  alb_access_logs_athena_base_prefix = local.alb_access_logs_realm_sorter_enabled ? (
    local.alb_access_logs_realm_sorter_target_prefix != "" ? "${local.alb_access_logs_realm_sorter_target_prefix}/" : ""
  ) : "${local.alb_access_logs_resource_prefix}AWSLogs/${local.account_id}/elasticloadbalancing/${var.region}/"
  alb_access_logs_athena_location = "s3://${local.alb_access_logs_bucket_name}/${local.alb_access_logs_athena_base_prefix}"
  alb_access_logs_athena_realms   = local.alb_access_logs_realm_sorter_enabled ? local.alb_access_logs_realm_sorter_realms : []
  alb_access_logs_athena_table_names_by_realm = {
    for realm in local.alb_access_logs_athena_realms :
    realm => lower(replace(
      "${local.alb_access_logs_glue_table_name_effective}_${realm}",
      "/[^A-Za-z0-9]+/",
      "_"
    ))
  }
}

resource "aws_glue_catalog_database" "alb_access_logs" {
  count = local.alb_access_logs_athena_enabled ? 1 : 0

  name = local.alb_access_logs_glue_database_name_effective

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-logs-db" })
}

resource "aws_glue_catalog_table" "alb_access_logs" {
  count         = local.alb_access_logs_athena_enabled && !local.alb_access_logs_realm_sorter_enabled ? 1 : 0
  name          = local.alb_access_logs_glue_table_name_effective
  database_name = aws_glue_catalog_database.alb_access_logs[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "alb"
  }

  storage_descriptor {
    location      = local.alb_access_logs_athena_location
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "alb-access-logs-serde"
      serialization_library = "org.apache.hadoop.hive.serde2.RegexSerDe"
      parameters = {
        "input.regex" = "([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*)[:|-]([0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) (\"[^\"]*\"|-) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*)"
      }
    }

    columns {
      name = "type"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "elb"
      type = "string"
    }
    columns {
      name = "client_ip"
      type = "string"
    }
    columns {
      name = "client_port"
      type = "int"
    }
    columns {
      name = "target_ip"
      type = "string"
    }
    columns {
      name = "target_port"
      type = "int"
    }
    columns {
      name = "request_processing_time"
      type = "double"
    }
    columns {
      name = "target_processing_time"
      type = "double"
    }
    columns {
      name = "response_processing_time"
      type = "double"
    }
    columns {
      name = "elb_status_code"
      type = "int"
    }
    columns {
      name = "target_status_code"
      type = "string"
    }
    columns {
      name = "received_bytes"
      type = "bigint"
    }
    columns {
      name = "sent_bytes"
      type = "bigint"
    }
    columns {
      name = "request_verb"
      type = "string"
    }
    columns {
      name = "request_url"
      type = "string"
    }
    columns {
      name = "request_proto"
      type = "string"
    }
    columns {
      name = "user_agent"
      type = "string"
    }
    columns {
      name = "ssl_cipher"
      type = "string"
    }
    columns {
      name = "ssl_protocol"
      type = "string"
    }
    columns {
      name = "target_group_arn"
      type = "string"
    }
    columns {
      name = "trace_id"
      type = "string"
    }
    columns {
      name = "domain_name"
      type = "string"
    }
    columns {
      name = "chosen_cert_arn"
      type = "string"
    }
    columns {
      name = "matched_rule_priority"
      type = "string"
    }
    columns {
      name = "request_creation_time"
      type = "string"
    }
    columns {
      name = "actions_executed"
      type = "string"
    }
    columns {
      name = "redirect_url"
      type = "string"
    }
    columns {
      name = "error_reason"
      type = "string"
    }
    columns {
      name = "target_port_list"
      type = "string"
    }
    columns {
      name = "target_status_code_list"
      type = "string"
    }
    columns {
      name = "classification"
      type = "string"
    }
    columns {
      name = "classification_reason"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "alb_access_logs_by_realm" {
  for_each      = local.alb_access_logs_athena_enabled && local.alb_access_logs_realm_sorter_enabled ? local.alb_access_logs_athena_table_names_by_realm : {}
  name          = each.value
  database_name = aws_glue_catalog_database.alb_access_logs[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "alb"
  }

  storage_descriptor {
    location      = "s3://${local.alb_access_logs_bucket_name}/${local.alb_access_logs_athena_base_prefix}${each.key}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "alb-access-logs-serde"
      serialization_library = "org.apache.hadoop.hive.serde2.RegexSerDe"
      parameters = {
        "input.regex" = "([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*)[:|-]([0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) (\"[^\"]*\"|-) (\"[^\"]*\"|-) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*)"
      }
    }

    columns {
      name = "type"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "elb"
      type = "string"
    }
    columns {
      name = "client_ip"
      type = "string"
    }
    columns {
      name = "client_port"
      type = "int"
    }
    columns {
      name = "target_ip"
      type = "string"
    }
    columns {
      name = "target_port"
      type = "int"
    }
    columns {
      name = "request_processing_time"
      type = "double"
    }
    columns {
      name = "target_processing_time"
      type = "double"
    }
    columns {
      name = "response_processing_time"
      type = "double"
    }
    columns {
      name = "elb_status_code"
      type = "int"
    }
    columns {
      name = "target_status_code"
      type = "string"
    }
    columns {
      name = "received_bytes"
      type = "bigint"
    }
    columns {
      name = "sent_bytes"
      type = "bigint"
    }
    columns {
      name = "request_verb"
      type = "string"
    }
    columns {
      name = "request_url"
      type = "string"
    }
    columns {
      name = "request_proto"
      type = "string"
    }
    columns {
      name = "user_agent"
      type = "string"
    }
    columns {
      name = "ssl_cipher"
      type = "string"
    }
    columns {
      name = "ssl_protocol"
      type = "string"
    }
    columns {
      name = "target_group_arn"
      type = "string"
    }
    columns {
      name = "trace_id"
      type = "string"
    }
    columns {
      name = "domain_name"
      type = "string"
    }
    columns {
      name = "chosen_cert_arn"
      type = "string"
    }
    columns {
      name = "matched_rule_priority"
      type = "string"
    }
    columns {
      name = "request_creation_time"
      type = "string"
    }
    columns {
      name = "actions_executed"
      type = "string"
    }
    columns {
      name = "redirect_url"
      type = "string"
    }
    columns {
      name = "error_reason"
      type = "string"
    }
    columns {
      name = "target_port_list"
      type = "string"
    }
    columns {
      name = "target_status_code_list"
      type = "string"
    }
    columns {
      name = "classification"
      type = "string"
    }
    columns {
      name = "classification_reason"
      type = "string"
    }
  }
}
