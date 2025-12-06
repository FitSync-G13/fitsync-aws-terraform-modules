data "aws_ssm_parameter" "ami" {
  name = var.ssm_parameter_name
}

resource "aws_key_pair" "main" {
  key_name   = "${var.env}-key"
  public_key = file(var.public_key_path)

  tags = merge(local.common_tags, {
    Name = "${var.env}-key"
  })
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.env}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = var.public_subnets
  private_subnets = [var.private_subnets]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = merge(local.common_tags, {
    Name = "${var.env}-vpc"
  })
}

module "tgw" {
  source = "terraform-aws-modules/transit-gateway/aws"

  name        = "${var.env}-tgw"
  description = "Transit Gateway for ${var.env} environment"

  enable_auto_accept_shared_attachments  = true
  enable_default_route_table_association = true
  enable_default_route_table_propagation = true

  vpc_attachments = {
    vpc = {
      vpc_id     = module.vpc.vpc_id
      subnet_ids = module.vpc.private_subnets

      dns_support  = true
      ipv6_support = false

      transit_gateway_default_route_table_association = true
      transit_gateway_default_route_table_propagation = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.env}-tgw"
  })
}

resource "aws_ec2_transit_gateway_route_table" "protected" {
  count              = var.enable_deletion_protection ? 1 : 0
  transit_gateway_id = module.tgw.ec2_transit_gateway_id

  tags = merge(local.common_tags, {
    Name = "${var.env}-tgw-protected-rt"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.env}-bastion-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.env}-bastion-sg"
  })
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${var.env}-bastion"
    Role = "bastion"
  })
}
