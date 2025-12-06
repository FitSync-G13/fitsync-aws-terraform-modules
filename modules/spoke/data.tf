data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ami" {
  name = var.ssm_parameter_name
}

data "aws_vpc" "hub" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-${var.hub_env}-vpc"]
  }
}

data "aws_internet_gateway" "hub" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.hub.id]
  }
}

data "aws_route_table" "hub_public" {
  vpc_id = data.aws_vpc.hub.id
  
  filter {
    name   = "route.gateway-id"
    values = [data.aws_internet_gateway.hub.id]
  }
}

data "aws_ec2_transit_gateway_route_table" "default" {
  filter {
    name   = "default-association-route-table"
    values = ["true"]
  }
  filter {
    name   = "transit-gateway-id"
    values = [var.hub_tgw_id]
  }
}

data "aws_ec2_transit_gateway_vpc_attachment" "hub_attachment" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.hub.id]
  }
  filter {
    name   = "transit-gateway-id"
    values = [var.hub_tgw_id]
  }
}
