output "repository_url" {
  description = "URL of the ECR repository"
  value       = var.enable_deletion_protection ? aws_ecr_repository.main_protected[0].repository_url : aws_ecr_repository.main[0].repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = var.enable_deletion_protection ? aws_ecr_repository.main_protected[0].arn : aws_ecr_repository.main[0].arn
}
