mock_provider "aws" {}

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

variables { expected_account_id = "123456789012" }

run "full_load_waits_for_manual_start" {
  command = plan
  assert {
    condition = (
      aws_dms_replication_task.full_load.migration_type == "full-load" &&
      !aws_dms_replication_task.full_load.start_replication_task &&
      aws_dms_replication_task.full_load.cdc_start_time == null &&
      aws_dms_replication_task.full_load.source_endpoint_arn == "arn:aws:dms:us-east-1:123456789012:endpoint:SOURCE" &&
      aws_dms_replication_task.full_load.target_endpoint_arn == "arn:aws:dms:us-east-1:123456789012:endpoint:TARGET"
    )
    error_message = "La etapa debe crear una carga inicial sin arrancarla ni configurar CDC."
  }
  assert {
    condition = (
      length(jsondecode(aws_dms_replication_task.full_load.table_mappings).rules) == 4 &&
      toset([for rule in jsondecode(aws_dms_replication_task.full_load.table_mappings).rules : rule.object-locator.table-name]) == toset(["clientes", "productos", "pedidos", "items_pedido"]) &&
      alltrue([for rule in jsondecode(aws_dms_replication_task.full_load.table_mappings).rules :
        rule.rule-type == "selection" && rule.rule-action == "explicit" && rule.object-locator.schema-name == "tienda"
      ])
    )
    error_message = "Solo deben seleccionarse las cuatro tablas, con nombres exactos y sin expansión de comodines."
  }
  assert {
    condition = (
      jsondecode(aws_dms_replication_task.full_load.replication_task_settings).Logging.EnableLogging &&
      jsondecode(aws_dms_replication_task.full_load.replication_task_settings).ErrorBehavior.TableErrorPolicy == "STOP_TASK" &&
      jsondecode(aws_dms_replication_task.full_load.replication_task_settings).ErrorBehavior.DataErrorPolicy == "STOP_TASK" &&
      jsondecode(aws_dms_replication_task.full_load.replication_task_settings).ErrorBehavior.DataTruncationErrorPolicy == "STOP_TASK" &&
      jsondecode(aws_dms_replication_task.full_load.replication_task_settings).ErrorBehavior.FailOnNoTablesCaptured &&
      jsondecode(aws_dms_replication_task.full_load.replication_task_settings).FullLoadSettings.TargetTablePrepMode == "DROP_AND_CREATE"
    )
    error_message = "La carga debe registrar logs y detenerse ante errores de datos/tablas o selección vacía."
  }
}

run "reject_mixed_accounts" {
  command = plan
  variables { expected_account_id = "999999999999" }
  expect_failures = [aws_dms_replication_task.full_load]
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
  expect_failures = [aws_dms_replication_task.full_load]
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
  expect_failures = [aws_dms_replication_task.full_load]
}
