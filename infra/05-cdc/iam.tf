resource "aws_iam_role" "target" {
  name_prefix        = "${var.workshop_name}-cdc-target-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "dms.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy" "target" {
  role = aws_iam_role.target.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = aws_s3_bucket.lake.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:PutObjectTagging", "s3:PutObjectAcl", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = "${aws_s3_bucket.lake.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["glue:CreateDatabase", "glue:GetDatabase", "glue:CreateTable", "glue:DeleteTable", "glue:UpdateTable", "glue:GetTable", "glue:BatchCreatePartition", "glue:CreatePartition", "glue:UpdatePartition", "glue:GetPartition", "glue:GetPartitions", "glue:BatchGetPartition"]
        # The schema transformation isolates generated tables in this namespace.
        Resource = ["arn:${local.partition}:glue:${local.region}:${local.account}:catalog", "arn:${local.partition}:glue:${local.region}:${local.account}:database/${local.catalog_name}", "arn:${local.partition}:glue:${local.region}:${local.account}:table/${local.catalog_name}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["athena:CreateWorkGroup", "athena:StartQueryExecution", "athena:GetQueryExecution"]
        Resource = "arn:${local.partition}:athena:${local.region}:${local.account}:workgroup/glue_catalog_generation_for_task_*"
      }
    ]
  })
}
