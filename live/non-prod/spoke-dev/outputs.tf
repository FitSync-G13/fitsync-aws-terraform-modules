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

output "public_alb_dns" {
  description = "Public NLB DNS for internet access"
  value       = module.spoke.public_alb_dns
}

output "opensearch_master_private_ips" {
  description = "Private IP addresses of OpenSearch master nodes"
  value       = module.spoke.opensearch_master_private_ips
}

output "opensearch_worker_private_ips" {
  description = "Private IP addresses of OpenSearch worker nodes"
  value       = module.spoke.opensearch_worker_private_ips
}

output "opensearch_private_dns" {
  description = "Private DNS name for OpenSearch cluster"
  value       = module.spoke.opensearch_private_dns
}

output "opensearch_nlb_dns" {
  description = "DNS name of the OpenSearch internal load balancer"
  value       = module.spoke.opensearch_nlb_dns
}

output "opensearch_ebs_volume_id" {
  description = "EBS volume ID for OpenSearch storage"
  value       = module.spoke.opensearch_ebs_volume_id
}

output "opensearch_dashboard_fqdn" {
  description = "Public FQDN for OpenSearch Dashboard"
  value       = module.spoke.opensearch_dashboard_fqdn
}
