output "replication_task_arn" { value = aws_dms_replication_task.full_load.replication_task_arn }
output "replication_task_id" { value = aws_dms_replication_task.full_load.replication_task_id }
output "target_data_uri" { value = local.dms.target_data_uri }
output "task_log_group_name" { value = local.dms.task_log_group_name }
output "catalog_database" { value = aws_glue_catalog_database.full_load.name }
output "workshop_context" { value = { account_id = var.expected_account_id, region = var.aws_region } }
