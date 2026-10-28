data "terraform_remote_state" "aurora" {
  backend = "local"
  config  = { path = "${path.module}/../01-aurora/terraform.tfstate" }
}

data "terraform_remote_state" "storage" {
  backend = "local"
  config  = { path = "${path.module}/../02-s3/terraform.tfstate" }
}

data "aws_partition" "current" {}

locals {
  aurora    = data.terraform_remote_state.aurora.outputs
  storage   = data.terraform_remote_state.storage.outputs
  partition = data.aws_partition.current.partition
  account   = var.expected_account_id
  region    = var.aws_region
  data_api  = jsondecode(local.aurora.data_api_request)
}
