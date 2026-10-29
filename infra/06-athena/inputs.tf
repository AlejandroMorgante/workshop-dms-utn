data "terraform_remote_state" "cdc" {
  backend = "local"
  config  = { path = "${path.module}/../05-cdc/terraform.tfstate" }
}
locals { cdc = data.terraform_remote_state.cdc.outputs }
