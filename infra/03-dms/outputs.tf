output "bootstrap_config" {
  description = "ARNs y metadatos para el asistente; no contiene valores secretos."
  value = jsonencode({
    account_id        = var.expected_account_id
    region            = var.aws_region
    resource_arn      = local.data_api.resourceArn
    admin_secret_arn  = local.data_api.secretArn
    database          = local.aurora.database_name
    host              = local.aurora.writer_endpoint
    source_secret_arn = aws_secretsmanager_secret.source.arn
    username          = "dms_reader"
  })
}
output "replication_instance_arn" { value = aws_dms_replication_instance.workshop.replication_instance_arn }
output "source_endpoint_arn" { value = try(aws_dms_endpoint.source[0].endpoint_arn, null) }
output "target_endpoint_arn" { value = aws_dms_s3_endpoint.target.endpoint_arn }
output "connection_tests" {
  description = "Peticiones para test-connection; disponibles después de preparar el origen."
  value = var.source_credentials_ready ? {
    source = { ReplicationInstanceArn = aws_dms_replication_instance.workshop.replication_instance_arn, EndpointArn = aws_dms_endpoint.source[0].endpoint_arn }
    target = { ReplicationInstanceArn = aws_dms_replication_instance.workshop.replication_instance_arn, EndpointArn = aws_dms_s3_endpoint.target.endpoint_arn }
  } : {}
}
