variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}
