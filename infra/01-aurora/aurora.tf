resource "aws_db_subnet_group" "aurora" {
  name_prefix = "${var.workshop_name}-"
  subnet_ids  = aws_subnet.private[*].id
  description = "Private subnets for the UTN workshop database"
}

resource "aws_rds_cluster_parameter_group" "aurora" {
  name_prefix = "${var.workshop_name}-pg16-"
  family      = "aurora-postgresql16"
  description = "PostgreSQL settings for the DMS workshop"

  # Configure at creation, before the writer starts: CDC needs logical WAL.
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/cluster/${var.workshop_name}-aurora/postgresql"
  retention_in_days = 7
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.workshop_name}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # Serverless v2 uses a db.serverless instance.
  engine_version     = var.aurora_engine_version
  database_name      = "workshop"
  master_username    = "workshop_admin"

  # RDS generates and rotates the password. Terraform never receives its value.
  manage_master_user_password = true
  storage_encrypted           = true
  enable_http_endpoint        = true

  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  enabled_cloudwatch_logs_exports = ["postgresql"]
  backup_retention_period         = 1

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 2
  }

  # Disposable training data only. Document this before terraform destroy.
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true

  tags = {
    created_by       = "aurora-skill"
    generation_model = "unknown"
  }

  depends_on = [aws_cloudwatch_log_group.postgresql]
}

resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${var.workshop_name}-writer"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  publicly_accessible = false

  tags = {
    created_by       = "aurora-skill"
    generation_model = "unknown"
  }
}
