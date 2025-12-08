variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "ssm_parameter_name" {
  description = "SSM parameter path for AMI ID"
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

variable "hub_env" {
  description = "Hub environment name for resource discovery"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "hub_tgw_id" {
  description = "Transit Gateway ID from hub"
  type        = string
}

variable "hub_vpc_cidr" {
  description = "CIDR block of the hub VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the spoke VPC"
  type        = string
}

variable "max_azs" {
  description = "Maximum number of availability zones to use (default: 2)"
  type        = number
  default     = 2
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks (auto-generated if empty). Example: ['10.1.1.0/24', '10.1.2.0/24']"
  type        = list(string)
  default     = []
}

variable "master_count" {
  description = "Number of K3s master nodes"
  type        = number
}

variable "worker_count" {
  description = "Number of K3s worker nodes"
  type        = number
}

variable "db_count" {
  description = "Number of database nodes"
  type        = number
}

variable "db_vol_size" {
  description = "Size of database EBS volume in GB"
  type        = number
}

variable "master_instance_type" {
  description = "Instance type for K3s master nodes"
  type        = string
  default     = "t3.micro"
}

variable "worker_instance_type" {
  description = "Instance type for K3s worker nodes"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_type" {
  description = "Instance type for database nodes"
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "Path to the public key file"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository for OIDC (format: owner/repo-name)"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token for managing secrets"
  type        = string
  sensitive   = true
}

variable "deployment_environment" {
  description = "Deployment environment name (production, staging, development)"
  type        = string
}

variable "domain_name" {
  description = "Domain name for this spoke (e.g., fitsync.online)"
  type        = string
  default     = ""
}

variable "subdomain_prefix" {
  description = "Subdomain prefix for this spoke (empty for prod, e.g., staging, dev)"
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS management"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_api_key" {
  description = "Cloudflare Global API Key (alternative to api_token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_email" {
  description = "Cloudflare account email (required with api_key)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_cloudflare_restriction" {
  description = "Restrict NLB traffic to Cloudflare IPs only"
  type        = bool
  default     = true
}

variable "acm_certificate_validation_method" {
  description = "ACM certificate validation method (DNS or EMAIL)"
  type        = string
  default     = "DNS"
}

variable "db_subdomain_prefix" {
  description = "Subdomain prefix for database private DNS (e.g., 'fitsync-db' creates fitsync-db.fitsync.online)"
  type        = string
  default     = ""
}
