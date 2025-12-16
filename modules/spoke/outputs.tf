output "k3s_api_dns" {
  description = "DNS name of the K3s API load balancer"
  value       = aws_lb.k3s_api.dns_name
}

output "master_private_ips" {
  description = "Private IP addresses of K3s master nodes"
  value       = aws_instance.k3s_masters[*].private_ip
}

output "worker_private_ips" {
  description = "Private IP addresses of K3s worker nodes"
  value       = aws_instance.k3s_workers[*].private_ip
}

output "db_private_ips" {
  description = "Private IP addresses of database nodes"
  value       = aws_instance.databases[*].private_ip
}

output "public_alb_dns" {
  description = "DNS name of the public NLB in hub VPC"
  value       = aws_lb.public_ingress.dns_name
}

output "public_nlb_arn" {
  description = "ARN of the public NLB in hub VPC"
  value       = aws_lb.public_ingress.arn
}

output "acm_certificate_arn" {
  description = "ARN of the ACM wildcard certificate (empty if no domain configured)"
  value       = var.domain_name != "" ? aws_acm_certificate.wildcard[0].arn : ""
}

output "domain_name" {
  description = "Domain name configured for this spoke (empty if not configured)"
  value       = var.domain_name
}

output "wildcard_domain" {
  description = "Wildcard domain for applications (empty if not configured)"
  value       = var.domain_name != "" ? "*.${var.domain_name}" : ""
}

output "db_private_dns" {
  description = "Private DNS name for database instance (empty if not configured)"
  value       = var.domain_name != "" && var.db_count > 0 ? local.db_fqdn : ""
}

output "db_private_zone_id" {
  description = "Route53 private hosted zone ID for database (empty if not configured)"
  value       = var.domain_name != "" && var.db_count > 0 ? aws_route53_zone.db_private[0].zone_id : ""
}

output "opensearch_master_private_ips" {
  description = "Private IP addresses of OpenSearch master nodes"
  value       = aws_instance.opensearch_masters[*].private_ip
}

output "opensearch_worker_private_ips" {
  description = "Private IP addresses of OpenSearch worker nodes"
  value       = aws_instance.opensearch_workers[*].private_ip
}

output "opensearch_subdomain" {
  description = "OpenSearch subdomain FQDN (empty if not configured)"
  value       = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? local.opensearch_fqdn : ""
}

output "opensearch_private_dns" {
  description = "Private DNS name for OpenSearch cluster (empty if not configured)"
  value       = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? local.opensearch_fqdn : ""
}

output "opensearch_private_zone_id" {
  description = "Route53 private hosted zone ID for OpenSearch (shared with database)"
  value       = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? aws_route53_zone.db_private[0].zone_id : ""
}

output "opensearch_nlb_dns" {
  description = "DNS name of the OpenSearch internal load balancer (empty if not configured)"
  value       = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? aws_lb.opensearch_internal[0].dns_name : ""
}

output "opensearch_ebs_volume_id" {
  description = "EBS volume ID for OpenSearch storage (for CSI driver)"
  value       = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? aws_ebs_volume.opensearch_storage[0].id : ""
}

output "opensearch_availability_zone" {
  description = "Availability zone of the OpenSearch EBS volume"
  value       = var.opensearch_master_count > 0 || var.opensearch_worker_count > 0 ? aws_ebs_volume.opensearch_storage[0].availability_zone : ""
}

output "opensearch_dashboard_fqdn" {
  description = "Public FQDN for OpenSearch Dashboard (empty if not configured)"
  value       = var.domain_name != "" && (var.opensearch_master_count > 0 || var.opensearch_worker_count > 0) ? local.opensearch_dashboard_fqdn : ""
}
