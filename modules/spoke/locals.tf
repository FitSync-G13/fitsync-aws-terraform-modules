locals {
  # Use first N available AZs based on max_azs
  azs = slice(data.aws_availability_zones.available.names, 0, var.max_azs)

  # Auto-generate private subnets if not provided
  # Pattern: 10.1.1.0/24, 10.1.2.0/24, etc.
  auto_private_subnets = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
    for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 1)
  ]

  # Database FQDN
  db_subdomain = var.db_subdomain_prefix != "" ? var.db_subdomain_prefix : "${var.project_name}-db"
  db_fqdn      = var.subdomain_prefix != "" ? "${local.db_subdomain}.${var.subdomain_prefix}.${var.domain_name}" : "${local.db_subdomain}.${var.domain_name}"

  # OpenSearch FQDN
  opensearch_subdomain = var.opensearch_subdomain_prefix != "" ? var.opensearch_subdomain_prefix : "${var.project_name}-search"
  opensearch_fqdn      = var.subdomain_prefix != "" ? "${local.opensearch_subdomain}.${var.subdomain_prefix}.${var.domain_name}" : "${local.opensearch_subdomain}.${var.domain_name}"

  # OpenSearch Dashboard FQDN for public access (single-level subdomain only)
  opensearch_dashboard_subdomain = var.opensearch_dashboard_subdomain_prefix != "" ? var.opensearch_dashboard_subdomain_prefix : "${local.opensearch_subdomain}-dashboard-${var.subdomain_prefix}"
  opensearch_dashboard_fqdn      = "${local.opensearch_dashboard_subdomain}.${var.domain_name}"

  common_tags = {
    Terraform = "true"
    Project   = var.project_name
    Layer     = "spoke"
    Env       = var.env
  }
}
