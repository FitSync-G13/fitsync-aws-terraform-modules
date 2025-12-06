locals {
  common_tags = {
    Terraform = "true"
    Module    = "hub-network"
    Env       = var.env
  }
}
