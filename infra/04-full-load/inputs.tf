data "terraform_remote_state" "dms" {
  backend = "local"
  config  = { path = "${path.module}/../03-dms/terraform.tfstate" }
}

locals {
  dms = data.terraform_remote_state.dms.outputs
}
