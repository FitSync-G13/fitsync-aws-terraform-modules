provider "aws" {
  region = var.aws_region
}

module "shared_ecr" {
  source = "../../modules/shared-ecr"

  repository_name            = var.repository_name
  account_id                 = var.account_id
  env                        = var.env
  enable_deletion_protection = var.enable_deletion_protection
}
