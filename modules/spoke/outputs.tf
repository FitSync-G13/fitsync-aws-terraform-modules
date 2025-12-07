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

output "public_nlb_dns" {
  description = "DNS name of the public NLB in hub VPC"
  value       = aws_lb.public_ingress.dns_name
}

output "public_nlb_arn" {
  description = "ARN of the public NLB in hub VPC"
  value       = aws_lb.public_ingress.arn
}
