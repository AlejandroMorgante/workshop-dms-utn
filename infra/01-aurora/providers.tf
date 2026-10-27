provider "aws" {
  region              = var.aws_region
  profile             = var.aws_profile
  allowed_account_ids = [var.expected_account_id]

  default_tags {
    tags = {
      Project     = "workshop-dms-utn"
      Environment = "workshop"
      ManagedBy   = "Terraform"
    }
  }
}
