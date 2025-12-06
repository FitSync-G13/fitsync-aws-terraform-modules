provider "aws" {
  region = var.aws_region
}

module "shared" {
  source = "../../modules/shared"

  project_name               = var.project_name
  env                        = var.env
  enable_deletion_protection = var.enable_deletion_protection
}
