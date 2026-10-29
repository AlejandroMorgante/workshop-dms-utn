mock_provider "aws" {}

variables {
  workshop_name       = "utn-dms"
  expected_account_id = "123456789012"
}

run "private_versioned_destination" {
  # Apply against the mock provider only; no AWS calls are made.
  command = apply
  override_resource {
    target = aws_s3_bucket.lake
    values = {
      id  = "utn-dms-lake-123456789012-us-east-1-an"
      arn = "arn:aws:s3:::utn-dms-lake-123456789012-us-east-1-an"
    }
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.lake.block_public_acls &&
      aws_s3_bucket_public_access_block.lake.block_public_policy &&
      aws_s3_bucket_public_access_block.lake.ignore_public_acls &&
      aws_s3_bucket_public_access_block.lake.restrict_public_buckets &&
      aws_s3_bucket_ownership_controls.lake.rule[0].object_ownership == "BucketOwnerEnforced"
    )
    error_message = "El destino debe bloquear acceso público y deshabilitar ACLs."
  }

  assert {
    condition = (
      aws_s3_bucket_versioning.lake.versioning_configuration[0].status == "Enabled" &&
      !aws_s3_bucket.lake.force_destroy &&
      aws_s3_bucket_lifecycle_configuration.lake.rule[0].noncurrent_version_expiration[0].noncurrent_days == 1 &&
      alltrue([for rule in aws_s3_bucket_server_side_encryption_configuration.lake.rule :
        rule.apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
        contains(rule.blocked_encryption_types, "SSE-C")
      ])
    )
    error_message = "Debe conservar versiones, cifrar con SSE-S3 y bloquear destrucción de un bucket no vacío."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.https_only.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.https_only.policy).Statement[0].Principal == "*" &&
      jsondecode(aws_s3_bucket_policy.https_only.policy).Statement[0].Action == "s3:*" &&
      jsondecode(aws_s3_bucket_policy.https_only.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false" &&
      toset(jsondecode(aws_s3_bucket_policy.https_only.policy).Statement[0].Resource) == toset([
        "arn:aws:s3:::utn-dms-lake-123456789012-us-east-1-an",
        "arn:aws:s3:::utn-dms-lake-123456789012-us-east-1-an/*"
      ])
    )
    error_message = "La política debe denegar HTTP tanto para el bucket como para sus objetos."
  }

  assert {
    condition = (
      aws_s3_bucket.lake.bucket_namespace == "account-regional" &&
      aws_s3_bucket.lake.bucket == "utn-dms-lake-123456789012-us-east-1-an" &&
      output.dms_prefix == "dms" &&
      output.sample_uri == "s3://utn-dms-lake-123456789012-us-east-1-an/exploracion/tienda.json"
    )
    error_message = "El nombre debe pertenecer a la cuenta y región, con muestra separada del prefijo de DMS."
  }
}

run "reject_unconfigured_account" {
  command = plan
  variables { expected_account_id = "REEMPLAZAR_CON_12_DIGITOS" }
  expect_failures = [var.expected_account_id]
}

run "reject_invalid_bucket_prefix" {
  command = plan
  variables { workshop_name = "Mi_Workshop" }
  expect_failures = [var.workshop_name]
}
