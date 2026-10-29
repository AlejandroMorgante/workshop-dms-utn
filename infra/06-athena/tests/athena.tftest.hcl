mock_provider "aws" {}
override_data {
  target = data.terraform_remote_state.cdc
  values = { outputs = {
    catalog_database = "utn_dms_cdc"
    workshop_context = { account_id = "123456789012", region = "us-east-1" }
  } }
}
variables { expected_account_id = "123456789012" }
run "controlled_query_results" {
  command = plan
  assert {
    condition     = aws_athena_workgroup.workshop.configuration[0].enforce_workgroup_configuration && aws_athena_workgroup.workshop.configuration[0].bytes_scanned_cutoff_per_query == 104857600 && aws_s3_bucket_public_access_block.lake.block_public_policy && !aws_s3_bucket.lake.force_destroy
    error_message = "Los resultados deben ser privados, con límite de escaneo y vaciado explícito."
  }
  assert {
    condition     = strcontains(aws_athena_named_query.latest.query, "rn = 1 AND op <> 'D'")
    error_message = "El borrado se filtra después de elegir el último evento."
  }
}
run "reject_mixed_accounts" {
  command = plan
  variables { expected_account_id = "999999999999" }
  expect_failures = [aws_athena_workgroup.workshop]
}
