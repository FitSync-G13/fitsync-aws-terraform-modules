provider "aws" {
  region = var.aws_region
}

# Dynamic discovery of Hub resources
data "aws_ec2_transit_gateway" "hub" {
  filter {
    name   = "tag:Name"
    values = ["${var.hub_env}-tgw"]
  }
}

data "aws_vpc" "hub" {
  filter {
    name   = "tag:Name"
    values = ["${var.hub_env}-vpc"]
  }
}

module "spoke" {
  source = "../../modules/spoke-infra"

  hub_env                    = var.hub_env
  aws_region                 = var.aws_region
  env                        = var.env
  hub_tgw_id                 = data.aws_ec2_transit_gateway.hub.id
  hub_vpc_cidr               = data.aws_vpc.hub.cidr_block
  vpc_cidr                   = var.vpc_cidr
  availability_zones         = var.availability_zones
  private_subnets            = var.private_subnets
  master_count               = var.master_count
  worker_count               = var.worker_count
  db_count                   = var.db_count
  db_vol_size                = var.db_vol_size
  instance_type              = var.instance_type
  public_key_path            = var.public_key_path
  ssm_parameter_name         = var.ssm_parameter_name
  enable_deletion_protection = var.enable_deletion_protection
}
