output "tgw_id" {
  description = "ID of the Transit Gateway"
  value       = module.hub.tgw_id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.hub.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.hub.vpc_cidr_block
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = module.hub.bastion_public_ip
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = module.hub.github_actions_role_arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = module.hub.github_actions_role_name
}
