locals {
  repository_names = [for service in var.service_names : "${var.project_name}-${service}"]

  common_tags = {
    Terraform = "true"
    Project   = var.project_name
    Layer     = "shared"
    Env       = var.env
  }
}
