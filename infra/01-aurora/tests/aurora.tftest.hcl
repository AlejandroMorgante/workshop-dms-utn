mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
}

variables {
  expected_account_id = "123456789012"
}

run "private_database_ready_for_the_workshop" {
  command = plan

  assert {
    condition = (
      !aws_rds_cluster_instance.writer.publicly_accessible &&
      alltrue([for subnet in aws_subnet.private : !subnet.map_public_ip_on_launch]) &&
      length(aws_security_group.aurora.egress) == 0
    )
    error_message = "La base debe permanecer privada y sin reglas de acceso de red en esta etapa."
  }

  assert {
    condition = (
      aws_rds_cluster.aurora.enable_http_endpoint &&
      aws_rds_cluster.aurora.manage_master_user_password &&
      aws_rds_cluster.aurora.storage_encrypted &&
      aws_rds_cluster.aurora.master_password == null
    )
    error_message = "Data API y la contraseña administrada por RDS deben estar habilitados, sin contraseña en Terraform."
  }

  assert {
    condition = alltrue([
      for name in ["rds.logical_replication", "rds.force_ssl"] :
      anytrue([for parameter in aws_rds_cluster_parameter_group.aurora.parameter : parameter.name == name && parameter.value == "1"])
    ])
    error_message = "La replicación lógica y SSL deben configurarse desde la creación."
  }

  assert {
    condition = (
      aws_rds_cluster_instance.writer.instance_class == "db.serverless" &&
      aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].min_capacity == 0.5 &&
      aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].max_capacity == 2 &&
      length(toset([for subnet in aws_subnet.private : subnet.availability_zone])) == 2
    )
    error_message = "El taller debe usar Serverless v2 acotado y subnets en dos zonas."
  }
}

run "reject_unconfigured_account" {
  command = plan
  variables {
    expected_account_id = "REEMPLAZAR_CON_12_DIGITOS"
  }
  expect_failures = [var.expected_account_id]
}

run "reject_incompatible_parameter_family" {
  command = plan
  variables {
    aurora_engine_version = "17.9"
  }
  expect_failures = [var.aurora_engine_version]
}
