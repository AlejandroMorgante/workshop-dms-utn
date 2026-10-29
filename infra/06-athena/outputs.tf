output "workgroup_name" { value = aws_athena_workgroup.workshop.name }
output "results_bucket_name" { value = aws_s3_bucket.lake.id }
output "catalog_database" { value = local.cdc.catalog_database }
output "query_ids" { value = { events = aws_athena_named_query.events.id, latest = aws_athena_named_query.latest.id } }
output "workshop_context" { value = { account_id = var.expected_account_id, region = var.aws_region } }
