variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "max_azs" {
  description = "Maximum number of availability zones to use (default: 2)"
  type        = number
  default     = 2
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks (auto-generated if empty). Example: ['10.0.1.0/24', '10.0.2.0/24']"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks (auto-generated if empty). Example: ['10.0.10.0/24', '10.0.11.0/24']"
  type        = list(string)
  default     = []
}

variable "admin_cidr" {
  description = "CIDR block for admin access to bastion"
  type        = string
}

variable "ssm_parameter_name" {
  description = "SSM parameter path for AMI ID"
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

variable "public_key_path" {
  description = "Path to the public key file"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
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

variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}
