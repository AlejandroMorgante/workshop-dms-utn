data "terraform_remote_state" "dms" {
  backend = "local"
  config  = { path = "${path.module}/../03-dms/terraform.tfstate" }
}

locals {
  dms = data.terraform_remote_state.dms.outputs
}

data "aws_partition" "current" {}
locals {
  partition    = data.aws_partition.current.partition
  account      = var.expected_account_id
  region       = var.aws_region
  catalog_name = "${replace(var.workshop_name, "-", "_")}_cdc"
}
resource "aws_glue_catalog_database" "cdc" {
  name        = local.catalog_name
  description = "Isolated catalog namespace for the workshop CDC task"
}
