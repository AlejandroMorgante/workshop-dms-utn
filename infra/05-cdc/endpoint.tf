resource "aws_dms_s3_endpoint" "target" {
  endpoint_id                                 = "${var.workshop_name}-cdc-target"
  endpoint_type                               = "target"
  bucket_name                                 = aws_s3_bucket.lake.id
  bucket_folder                               = "dms"
  expected_bucket_owner                       = var.expected_account_id
  service_access_role_arn                     = aws_iam_role.target.arn
  data_format                                 = "parquet"
  parquet_version                             = "parquet-2-0"
  parquet_timestamp_in_millisecond            = true
  include_op_for_full_load                    = true
  timestamp_column_name                       = "dms_commit_timestamp"
  use_task_start_time_for_full_load_timestamp = true
  glue_catalog_generation                     = true
  # Date partitions are supported for full-load-and-cdc.
  date_partition_enabled   = true
  date_partition_sequence  = "YYYYMMDD"
  date_partition_delimiter = "SLASH"
  date_partition_timezone  = "UTC"
  encryption_mode          = "SSE_S3"
  cdc_max_batch_interval   = 60
  cdc_min_file_size        = 32
  # No CdcPath/PreserveTransactions: incompatible with catalog/date partitioning.
  depends_on = [aws_iam_role_policy.target, aws_s3_bucket_policy.https_only, aws_glue_catalog_database.cdc]
}
