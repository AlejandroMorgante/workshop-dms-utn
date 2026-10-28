mock_provider "aws" {
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:dms-reader-example" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/workshop-dms" }
  }
  mock_resource "aws_dms_certificate" {
    defaults = { certificate_arn = "arn:aws:dms:us-east-1:123456789012:cert:EXAMPLE" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_resource "aws_vpc_endpoint" {
    defaults = { dns_entry = [{ dns_name = "vpce-workshop.example.com", hosted_zone_id = "ZEXAMPLE" }] }
  }
}

override_data {
  target = data.terraform_remote_state.aurora
  values = {
    outputs = {
      vpc_id                 = "vpc-12345678", private_subnet_ids = ["subnet-11111111", "subnet-22222222"]
      private_route_table_id = "rtb-12345678", aurora_security_group_id = "sg-12345678"
      writer_endpoint        = "utn.cluster-example.us-east-1.rds.amazonaws.com", database_name = "workshop"
      workshop_context       = { account_id = "123456789012", region = "us-east-1" }
      data_api_request       = "{\"resourceArn\":\"arn:aws:rds:us-east-1:123456789012:cluster:utn\",\"secretArn\":\"arn:aws:secretsmanager:us-east-1:123456789012:secret:admin\",\"database\":\"workshop\"}"
    }
  }
}
override_data {
  target = data.terraform_remote_state.storage
  values = {
    outputs = {
      bucket_name      = "utn-lake-123456789012-us-east-1-an", bucket_arn = "arn:aws:s3:::utn-lake-123456789012-us-east-1-an"
      dms_prefix       = "dms", bucket_region = "us-east-1"
      workshop_context = { account_id = "123456789012", region = "us-east-1" }
    }
  }
}
variables {
  expected_account_id = "123456789012"
}

run "infrastructure_before_credentials" {
  command = plan
  assert {
    condition     = length(aws_dms_endpoint.source) == 0
    error_message = "El endpoint de origen debe esperar a la preparación del usuario."
  }
  assert {
    condition = (
      !aws_dms_replication_instance.workshop.publicly_accessible &&
      aws_vpc_security_group_ingress_rule.aurora_from_dms.from_port == 5432 &&
      aws_vpc_security_group_ingress_rule.aurora_from_dms.cidr_ipv4 == null &&
      aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" &&
      length(aws_vpc_endpoint.services) == 4 &&
      alltrue([for endpoint in aws_vpc_endpoint.services : endpoint.private_dns_enabled])
    )
    error_message = "La instancia y el acceso a Aurora/servicios deben permanecer privados."
  }
  assert {
    condition = (
      aws_dms_s3_endpoint.target.data_format == "parquet" &&
      aws_dms_s3_endpoint.target.glue_catalog_generation &&
      aws_dms_s3_endpoint.target.date_partition_enabled &&
      aws_dms_s3_endpoint.target.include_op_for_full_load &&
      aws_dms_s3_endpoint.target.parquet_timestamp_in_millisecond &&
      aws_dms_s3_endpoint.target.cdc_path == null &&
      aws_dms_s3_endpoint.target.preserve_transactions != true
    )
    error_message = "El destino debe mantener una combinación compatible de Parquet, CDC, particiones y catálogo."
  }
}

run "source_with_secret_and_verified_tls" {
  command = apply
  variables { source_credentials_ready = true }
  assert {
    condition = (
      aws_dms_endpoint.source[0].password == null &&
      aws_dms_endpoint.source[0].username == null &&
      aws_dms_endpoint.source[0].server_name == null &&
      aws_dms_endpoint.source[0].ssl_mode == "verify-full" &&
      aws_dms_endpoint.source[0].secrets_manager_arn == aws_secretsmanager_secret.source.arn &&
      !aws_dms_endpoint.source[0].postgres_settings[0].capture_ddls
    )
    error_message = "El origen debe usar el secreto, verificar TLS y no requerir privilegios de captura DDL."
  }
  assert {
    condition = (
      strcontains(aws_dms_endpoint.source[0].extra_connection_attributes, "secretsManagerEndpointOverride=") &&
      jsondecode(output.bootstrap_config).username == "dms_reader" &&
      !contains(keys(jsondecode(output.bootstrap_config)), "password")
    )
    error_message = "El asistente debe recibir solo metadatos; Secrets Manager debe tener ruta privada."
  }
}

run "reuse_account_roles" {
  command = plan
  variables {
    create_dms_vpc_role  = false
    create_dms_logs_role = false
  }
  assert {
    condition     = length(aws_iam_role.vpc) == 0 && length(aws_iam_role.logs) == 0
    error_message = "La opción de reutilizar roles no debe administrar roles ajenos al stack."
  }
}

run "reject_mixed_accounts" {
  command = plan
  variables { expected_account_id = "999999999999" }
  expect_failures = [aws_dms_replication_instance.workshop]
}
