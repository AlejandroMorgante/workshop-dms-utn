resource "aws_athena_workgroup" "workshop" {
  name          = "${var.workshop_name}-queries"
  force_destroy = true
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 104857600
    engine_version { selected_engine_version = "Athena engine version 3" }
    result_configuration {
      output_location       = "s3://${aws_s3_bucket.lake.id}/results/"
      expected_bucket_owner = var.expected_account_id
      encryption_configuration { encryption_option = "SSE_S3" }
    }
  }
  lifecycle {
    precondition {
      condition     = local.cdc.workshop_context.account_id == var.expected_account_id && local.cdc.workshop_context.region == var.aws_region
      error_message = "Athena y CDC deben usar la misma cuenta y región."
    }
  }
  depends_on = [aws_s3_bucket_public_access_block.lake, aws_s3_bucket_policy.https_only]
}
resource "aws_athena_named_query" "events" {
  name      = "01 - Eventos CDC del producto de prueba"
  workgroup = aws_athena_workgroup.workshop.name
  database  = local.cdc.catalog_database
  query     = <<-SQL
    SELECT op, producto_id, nombre, precio, dms_commit_timestamp, dms_change_seq, "$path" AS archivo
    FROM "${local.cdc.catalog_database}"."productos"
    WHERE producto_id = 9001
    ORDER BY dms_change_seq;
  SQL
}
resource "aws_athena_named_query" "latest" {
  name      = "02 - Ultimo evento y estado actual del producto de prueba"
  workgroup = aws_athena_workgroup.workshop.name
  database  = local.cdc.catalog_database
  query     = <<-SQL
    WITH ordered AS (
      SELECT *, row_number() OVER (PARTITION BY producto_id ORDER BY dms_change_seq DESC) AS rn
      FROM "${local.cdc.catalog_database}"."productos"
      WHERE producto_id = 9001
    )
    SELECT producto_id, nombre, precio, op
    FROM ordered WHERE rn = 1 AND op <> 'D';
  SQL
}
