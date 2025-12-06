provider "aws" {
  region = var.aws_region
}

module "hub_network" {
  source = "../../modules/hub-network"

  env                        = var.env
  vpc_cidr                   = var.vpc_cidr
  availability_zones         = var.availability_zones
  public_subnets             = var.public_subnets
  private_subnets            = var.private_subnets
  admin_cidr                 = var.admin_cidr
  public_key_path            = var.public_key_path
  ssm_parameter_name         = var.ssm_parameter_name
  enable_deletion_protection = var.enable_deletion_protection
}
