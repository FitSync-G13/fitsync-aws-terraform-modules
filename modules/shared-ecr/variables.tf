variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID for repository policy"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}
