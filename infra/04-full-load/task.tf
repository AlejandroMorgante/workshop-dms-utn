resource "aws_dms_replication_task" "full_load" {
  replication_task_id       = "${var.workshop_name}-full-load"
  migration_type            = "full-load"
  replication_instance_arn  = local.dms.replication_instance_arn
  source_endpoint_arn       = try(local.dms.source_endpoint_arn, null)
  target_endpoint_arn       = local.dms.target_endpoint_arn
  table_mappings            = templatefile("${path.module}/config/table-mappings.json.tftpl", { catalog_name = local.catalog_name })
  replication_task_settings = file("${path.module}/config/task-settings.json")
  # Start explicitly with AWS CLI during the workshop, after inspecting the task.
  start_replication_task = false
  depends_on             = [aws_glue_catalog_database.full_load]

  lifecycle {
    precondition {
      condition = try(
        local.dms.workshop_context.account_id == var.expected_account_id &&
        local.dms.workshop_context.region == var.aws_region,
        false
      )
      error_message = "Reaplicá el stack 03 actualizado. DMS y full load deben usar la misma cuenta y región."
    }
    precondition {
      condition     = try(local.dms.source_endpoint_arn != null && local.dms.source_endpoint_arn != "", false)
      error_message = "Completá la etapa 03: prepará el usuario, aplicá source_credentials_ready=true y probá ambas conexiones."
    }
  }
}
