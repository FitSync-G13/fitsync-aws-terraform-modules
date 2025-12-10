output "repository_urls" {
  description = "Comma-separated list of ECR repository URLs"
  value       = join(",", values(module.shared.repository_urls))
}

output "repository_arns" {
  description = "Comma-separated list of ECR repository ARNs"
  value       = join(",", values(module.shared.repository_arns))
}

output "repository_names" {
  description = "Comma-separated list of ECR repository names"
  value       = join(",", values(module.shared.repository_names))
}
