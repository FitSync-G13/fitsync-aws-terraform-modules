variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}
