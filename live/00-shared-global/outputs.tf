output "repository_url" {
  description = "URL of the ECR repository"
  value       = module.shared_ecr.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = module.shared_ecr.repository_arn
}
