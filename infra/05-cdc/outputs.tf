output "replication_task_arn" { value = aws_dms_replication_task.cdc.replication_task_arn }
output "replication_task_id" { value = aws_dms_replication_task.cdc.replication_task_id }
output "target_endpoint_arn" { value = aws_dms_s3_endpoint.target.endpoint_arn }
output "target_data_uri" { value = "s3://${aws_s3_bucket.lake.id}/dms/" }
output "bucket_name" { value = aws_s3_bucket.lake.id }
output "catalog_database" { value = aws_glue_catalog_database.cdc.name }
output "task_log_group_name" { value = local.dms.task_log_group_name }
output "workshop_context" { value = { account_id = var.expected_account_id, region = var.aws_region } }
