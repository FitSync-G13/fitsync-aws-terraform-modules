locals {
  # Use first N available AZs based on max_azs
  azs = slice(data.aws_availability_zones.available.names, 0, var.max_azs)
  
  # Auto-generate public subnets if not provided
  # Pattern: 10.0.1.0/24, 10.0.2.0/24, etc.
  auto_public_subnets = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [
    for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 1)
  ]
  
  # Auto-generate private subnets if not provided  
  # Pattern: 10.0.10.0/24, 10.0.11.0/24, etc.
  auto_private_subnets = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
    for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 10)
  ]

  common_tags = {
    Terraform = "true"
    Project   = var.project_name
    Layer     = "hub"
    Env       = var.env
  }
}
