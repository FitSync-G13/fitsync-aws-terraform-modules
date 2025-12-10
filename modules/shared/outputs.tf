output "repository_urls" {
  description = "Map of service names to ECR repository URLs"
  value = var.enable_deletion_protection ? {
    for k, v in aws_ecr_repository.main_protected : split("-", k)[1] => v.repository_url
  } : {
    for k, v in aws_ecr_repository.main : split("-", k)[1] => v.repository_url
  }
}

output "repository_arns" {
  description = "Map of service names to ECR repository ARNs"
  value = var.enable_deletion_protection ? {
    for k, v in aws_ecr_repository.main_protected : split("-", k)[1] => v.arn
  } : {
    for k, v in aws_ecr_repository.main : split("-", k)[1] => v.arn
  }
}

output "repository_names" {
  description = "Map of service names to ECR repository names"
  value = var.enable_deletion_protection ? {
    for k, v in aws_ecr_repository.main_protected : split("-", k)[1] => v.name
  } : {
    for k, v in aws_ecr_repository.main : split("-", k)[1] => v.name
  }
}
