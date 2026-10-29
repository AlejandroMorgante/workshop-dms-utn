data "terraform_remote_state" "dms" {
  backend = "local"
  config  = { path = "${path.module}/../03-dms/terraform.tfstate" }
}

locals {
  dms = data.terraform_remote_state.dms.outputs
}

locals { catalog_name = "${replace(var.workshop_name, "-", "_")}_load" }
resource "aws_glue_catalog_database" "full_load" {
  name        = local.catalog_name
  description = "Isolated catalog namespace for the workshop full load"
}
