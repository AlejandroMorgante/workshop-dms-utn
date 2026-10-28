output "bucket_name" {
  description = "Nombre del bucket para la consola, la CLI y el endpoint de DMS."
  value       = aws_s3_bucket.lake.id
}

output "bucket_arn" {
  description = "ARN para los permisos del rol de DMS en la etapa 03."
  value       = aws_s3_bucket.lake.arn
}

output "bucket_region" {
  description = "Región del bucket."
  value       = var.aws_region
}

output "dms_prefix" {
  description = "Prefijo reservado para DMS; no crea carpetas ni objetos."
  value       = local.dms_prefix
}

output "sample_uri" {
  description = "Destino del archivo manual, separado de los futuros datos de DMS."
  value       = "s3://${aws_s3_bucket.lake.id}/exploracion/tienda.json"
}

output "workshop_context" {
  value = { account_id = var.expected_account_id, region = var.aws_region }
}
