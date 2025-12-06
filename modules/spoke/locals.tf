locals {
  # Use first N available AZs based on max_azs
  azs = slice(data.aws_availability_zones.available.names, 0, var.max_azs)
  
  # Auto-generate private subnets if not provided
  # Pattern: 10.1.1.0/24, 10.1.2.0/24, etc.
  auto_private_subnets = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
    for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 1)
  ]

  common_tags = {
    Terraform = "true"
    Project   = var.project_name
    Layer     = "spoke"
    Env       = var.env
  }
}
