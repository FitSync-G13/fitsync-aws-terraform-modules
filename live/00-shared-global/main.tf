module "shared" {
  source = "../../modules/shared"

  project_name               = var.project_name
  aws_region                 = var.aws_region
  env                        = var.env
  enable_deletion_protection = var.enable_deletion_protection
}
