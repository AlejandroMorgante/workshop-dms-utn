resource "aws_secretsmanager_secret" "source" {
  name_prefix             = "${var.workshop_name}/dms-source-"
  description             = "Dedicated PostgreSQL replication user; initialized by the workshop helper"
  recovery_window_in_days = 0 # Disposable lab: permanently delete on destroy.
}

resource "aws_dms_replication_instance" "workshop" {
  replication_instance_id     = "${var.workshop_name}-replication"
  replication_instance_class  = "dms.t3.small"
  engine_version              = "3.6.1"
  allocated_storage           = 50
  publicly_accessible         = false
  multi_az                    = false
  auto_minor_version_upgrade  = false
  replication_subnet_group_id = aws_dms_replication_subnet_group.workshop.id
  vpc_security_group_ids      = [aws_security_group.dms.id]

  lifecycle {
    precondition {
      condition = alltrue([
        for context in [local.aurora.workshop_context, local.storage.workshop_context] :
        context.account_id == var.expected_account_id && context.region == var.aws_region
      ])
      error_message = "Aurora, S3 y DMS deben usar la misma cuenta y región. Reaplicá primero los stacks 01 y 02 actualizados."
    }
  }
  depends_on = [aws_iam_role_policy_attachment.vpc, aws_iam_role_policy_attachment.logs]
}

resource "aws_dms_certificate" "rds" {
  certificate_id  = "${var.workshop_name}-rds-ca"
  certificate_pem = file("${path.module}/certs/us-east-1-bundle.pem")
}

resource "aws_dms_endpoint" "source" {
  count                           = var.source_credentials_ready ? 1 : 0
  endpoint_id                     = "${var.workshop_name}-aurora-source"
  endpoint_type                   = "source"
  engine_name                     = "aurora-postgresql"
  database_name                   = local.aurora.database_name
  secrets_manager_arn             = aws_secretsmanager_secret.source.arn
  secrets_manager_access_role_arn = aws_iam_role.source.arn
  extra_connection_attributes     = "secretsManagerEndpointOverride=${aws_vpc_endpoint.services["secretsmanager"].dns_entry[0].dns_name}"
  ssl_mode                        = "verify-full"
  certificate_arn                 = aws_dms_certificate.rds.certificate_arn
  postgres_settings {
    capture_ddls = false
    plugin_name  = "test-decoding"
  }
  depends_on = [aws_iam_role_policy.source, aws_vpc_endpoint.services]
}

resource "aws_dms_s3_endpoint" "target" {
  endpoint_id                                 = "${var.workshop_name}-s3-target"
  endpoint_type                               = "target"
  bucket_name                                 = local.storage.bucket_name
  bucket_folder                               = local.storage.dms_prefix
  expected_bucket_owner                       = var.expected_account_id
  service_access_role_arn                     = aws_iam_role.target.arn
  data_format                                 = "parquet"
  parquet_version                             = "parquet-2-0"
  parquet_timestamp_in_millisecond            = true
  include_op_for_full_load                    = true
  timestamp_column_name                       = "dms_commit_timestamp"
  use_task_start_time_for_full_load_timestamp = true
  glue_catalog_generation                     = true
  # DMS rejects full-load-only tasks when date partitioning is enabled.
  date_partition_enabled   = false
  date_partition_sequence  = "YYYYMMDD"
  date_partition_delimiter = "SLASH"
  date_partition_timezone  = "UTC"
  encryption_mode          = "SSE_S3"
  cdc_max_batch_interval   = 60
  cdc_min_file_size        = 32
  # No CdcPath/PreserveTransactions: incompatible with catalog/date partitioning.
  depends_on = [aws_iam_role_policy.target, aws_vpc_endpoint.s3, aws_vpc_endpoint.services]
}
