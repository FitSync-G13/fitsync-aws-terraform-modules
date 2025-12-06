variable "aws_region" {
  description = "AWS region"
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

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDR block"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block for admin access"
  type        = string
}

variable "public_key_path" {
  description = "Path to the public key file"
  type        = string
}
