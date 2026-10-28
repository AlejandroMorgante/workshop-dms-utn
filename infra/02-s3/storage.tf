locals {
  bucket_name = "${var.workshop_name}-lake-${var.expected_account_id}-${var.aws_region}-an"
  dms_prefix  = "dms"
}

resource "aws_s3_bucket" "lake" {
  bucket           = local.bucket_name
  bucket_namespace = "account-regional"
  force_destroy    = false

  tags = { Stage = "02-s3" }
}

# Keep S3's private defaults explicit in the lab's desired state.
resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    blocked_encryption_types = ["SSE-C"]
    # Bucket Keys optimize SSE-KMS; this workshop uses SSE-S3.
    bucket_key_enabled = false
  }
}

# This stack owns the bucket policy. DMS permissions belong to its IAM role later.
resource "aws_s3_bucket_policy" "https_only" {
  bucket = aws_s3_bucket.lake.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# DMS recommends removing old versions on versioned S3 targets.
resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    id     = "remove-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 1 }
    expiration { expired_object_delete_marker = true }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
  depends_on = [aws_s3_bucket_versioning.lake]
}
