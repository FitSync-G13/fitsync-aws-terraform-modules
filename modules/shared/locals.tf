locals {
  repository_name = "${var.project_name}-ecr"

  common_tags = {
    Terraform = "true"
    Project   = var.project_name
    Layer     = "shared"
    Env       = var.env
  }
}
