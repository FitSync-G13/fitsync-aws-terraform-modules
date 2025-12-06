locals {
  common_tags = {
    Terraform = "true"
    Module    = "spoke-infra"
    Env       = var.env
  }
}
