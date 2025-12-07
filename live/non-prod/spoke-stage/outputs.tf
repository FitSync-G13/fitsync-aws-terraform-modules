output "k3s_api_dns" {
  description = "DNS name of the K3s API load balancer"
  value       = module.spoke.k3s_api_dns
}

output "master_private_ips" {
  description = "Private IP addresses of K3s master nodes"
  value       = module.spoke.master_private_ips
}

output "worker_private_ips" {
  description = "Private IP addresses of K3s worker nodes"
  value       = module.spoke.worker_private_ips
}

output "db_private_ips" {
  description = "Private IP addresses of database nodes"
  value       = module.spoke.db_private_ips
}

output "public_nlb_dns" {
  description = "Public NLB DNS for internet access"
  value       = module.spoke.public_nlb_dns
}
