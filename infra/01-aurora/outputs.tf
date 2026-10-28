output "cluster_identifier" {
  description = "Cluster para localizar en la consola de RDS."
  value       = aws_rds_cluster.aurora.cluster_identifier
}

output "writer_endpoint" {
  description = "Endpoint privado para el futuro source endpoint de DMS."
  value       = aws_rds_cluster.aurora.endpoint
}

output "database_name" {
  value = aws_rds_cluster.aurora.database_name
}

output "database_username" {
  value = aws_rds_cluster.aurora.master_username
}

output "data_api_request" {
  description = "JSON para la CLI: incluye ARNs y nombre de base, nunca la contraseña."
  value = jsonencode({
    resourceArn = aws_rds_cluster.aurora.arn
    secretArn   = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
    database    = aws_rds_cluster.aurora.database_name
  })

  depends_on = [aws_rds_cluster_instance.writer]
}

output "vpc_id" {
  value = aws_vpc.workshop.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "workshop_context" {
  value = { account_id = var.expected_account_id, region = var.aws_region }
}
