provider "aws" {
  region = var.aws_region
}

module "hub" {
  source = "../../modules/hub"

  project_name               = var.project_name
  env                        = var.env
  vpc_cidr                   = var.vpc_cidr
  max_azs                    = var.max_azs
  public_subnet_cidrs        = var.public_subnet_cidrs
  private_subnet_cidrs       = var.private_subnet_cidrs
  admin_cidr                 = var.admin_cidr
  public_key_path            = var.public_key_path
  ssm_parameter_name         = var.ssm_parameter_name
  enable_deletion_protection = var.enable_deletion_protection
}
