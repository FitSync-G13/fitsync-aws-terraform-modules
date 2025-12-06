locals {
  common_tags = {
    Terraform = "true"
    Module    = "shared-ecr"
    Env       = var.env
  }
}
