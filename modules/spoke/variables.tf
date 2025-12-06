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

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "public_key_path" {
  description = "Path to the public key file"
  type        = string
}
