mock_provider "aws" {
  mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/mock-target" } }
  mock_resource "aws_dms_s3_endpoint" { defaults = { endpoint_arn = "arn:aws:dms:us-east-1:123456789012:endpoint:CDC" } }
}

override_data {
  target = data.terraform_remote_state.dms
  values = {
    outputs = {
      replication_instance_arn = "arn:aws:dms:us-east-1:123456789012:rep:EXAMPLE"
      source_endpoint_arn      = "arn:aws:dms:us-east-1:123456789012:endpoint:SOURCE"
      target_endpoint_arn      = "arn:aws:dms:us-east-1:123456789012:endpoint:TARGET"
      workshop_context         = { account_id = "123456789012", region = "us-east-1" }
      target_data_uri          = "s3://utn-lake-123456789012-us-east-1-an/dms/"
      task_log_group_name      = "dms-tasks-utn-dms-replication"
    }
  }
}

variables {
  expected_account_id = "123456789012"
  workshop_name       = "utn-dms"
}

run "cdc_waits_for_manual_start" {
  command = apply
  assert {
    condition = (
      aws_dms_s3_endpoint.target.date_partition_enabled &&
      aws_dms_s3_endpoint.target.glue_catalog_generation &&
      aws_glue_catalog_database.cdc.name == "utn_dms_cdc" &&
      aws_dms_replication_task.cdc.migration_type == "full-load-and-cdc" &&
      !aws_dms_replication_task.cdc.start_replication_task &&
      aws_dms_replication_task.cdc.cdc_start_time == null &&
      aws_dms_replication_task.cdc.source_endpoint_arn == "arn:aws:dms:us-east-1:123456789012:endpoint:SOURCE" &&
      aws_dms_replication_task.cdc.target_endpoint_arn == aws_dms_s3_endpoint.target.endpoint_arn
    )
    error_message = "La etapa debe crear full load + CDC con arranque manual."
  }
  assert {
    condition = (
      length(jsondecode(aws_dms_replication_task.cdc.table_mappings).rules) == 6 &&
      toset([for rule in jsondecode(aws_dms_replication_task.cdc.table_mappings).rules : rule.object-locator.table-name if rule.rule-type == "selection"]) == toset(["clientes", "productos", "pedidos", "items_pedido"]) &&
      alltrue([for rule in jsondecode(aws_dms_replication_task.cdc.table_mappings).rules :
        rule.rule-action == "explicit" && rule.object-locator.schema-name == "tienda" if rule.rule-type == "selection"
      ])
    )
    error_message = "Solo deben seleccionarse las cuatro tablas, con nombres exactos y sin expansión de comodines."
  }
  assert {
    condition = (
      jsondecode(aws_dms_replication_task.cdc.replication_task_settings).Logging.EnableLogging &&
      jsondecode(aws_dms_replication_task.cdc.replication_task_settings).ErrorBehavior.TableErrorPolicy == "STOP_TASK" &&
      jsondecode(aws_dms_replication_task.cdc.replication_task_settings).ErrorBehavior.DataErrorPolicy == "STOP_TASK" &&
      jsondecode(aws_dms_replication_task.cdc.replication_task_settings).ErrorBehavior.DataTruncationErrorPolicy == "STOP_TASK" &&
      jsondecode(aws_dms_replication_task.cdc.replication_task_settings).ErrorBehavior.FailOnNoTablesCaptured &&
      jsondecode(aws_dms_replication_task.cdc.replication_task_settings).FullLoadSettings.TargetTablePrepMode == "DROP_AND_CREATE"
    )
    error_message = "La carga debe registrar logs y detenerse ante errores de datos/tablas o selección vacía."
  }
}

run "reject_mixed_accounts" {
  command = plan
  variables { expected_account_id = "999999999999" }
  expect_failures = [aws_dms_replication_task.cdc]
}

run "reject_unprepared_source" {
  command = plan
  override_data {
    target = data.terraform_remote_state.dms
    values = {
      outputs = {
        replication_instance_arn = "arn:aws:dms:us-east-1:123456789012:rep:EXAMPLE"
        target_endpoint_arn      = "arn:aws:dms:us-east-1:123456789012:endpoint:TARGET"
        workshop_context         = { account_id = "123456789012", region = "us-east-1" }
        target_data_uri          = "s3://utn-lake-123456789012-us-east-1-an/dms/"
        task_log_group_name      = "dms-tasks-utn-dms-replication"
      }
    }
  }
  expect_failures = [aws_dms_replication_task.cdc]
}

run "reject_mixed_regions" {
  command = plan
  override_data {
    target = data.terraform_remote_state.dms
    values = {
      outputs = {
        replication_instance_arn = "arn:aws:dms:us-west-2:123456789012:rep:EXAMPLE"
        source_endpoint_arn      = "arn:aws:dms:us-west-2:123456789012:endpoint:SOURCE"
        target_endpoint_arn      = "arn:aws:dms:us-west-2:123456789012:endpoint:TARGET"
        workshop_context         = { account_id = "123456789012", region = "us-west-2" }
        target_data_uri          = "s3://utn-lake-123456789012-us-west-2-an/dms/"
        task_log_group_name      = "dms-tasks-utn-dms-replication"
      }
    }
  }
  expect_failures = [aws_dms_replication_task.cdc]
}
