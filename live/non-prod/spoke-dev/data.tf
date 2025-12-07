# Dynamic discovery of Hub resources
data "aws_ec2_transit_gateway" "hub" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-${var.hub_env}-tgw"]
  }
}

data "aws_vpc" "hub" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-${var.hub_env}-vpc"]
  }
}
