output "tgw_id" {
  description = "ID of the Transit Gateway"
  value       = module.tgw.ec2_transit_gateway_id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = var.enable_deletion_protection ? aws_instance.bastion_protected[0].public_ip : aws_instance.bastion[0].public_ip
}
