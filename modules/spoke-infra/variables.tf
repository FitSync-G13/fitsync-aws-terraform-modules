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

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
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

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "public_key_path" {
  description = "Path to the public key file"
  type        = string
}
