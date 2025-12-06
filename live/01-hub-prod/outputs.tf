output "tgw_id" {
  description = "ID of the Transit Gateway"
  value       = module.hub_network.tgw_id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.hub_network.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.hub_network.vpc_cidr_block
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = module.hub_network.bastion_public_ip
}
