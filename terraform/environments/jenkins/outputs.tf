output "jenkins_url" {
  description = "Jenkins web URL."
  value       = "https://${local.jenkins_fqdn}"
}

output "jenkins_dns_name" {
  description = "Route 53 DNS name for Jenkins."
  value       = var.create_route53_record ? aws_route53_record.jenkins[0].fqdn : null
}

output "jenkins_dns_url" {
  description = "Jenkins HTTPS URL using its configured DNS hostname."
  value       = "https://${local.jenkins_fqdn}"
}

output "jenkins_instance_id" {
  description = "Jenkins EC2 instance IDs."
  value       = module.jenkins_server.instance_id
}

output "jenkins_public_ip" {
  description = "Jenkins public IP addresses."
  value       = module.jenkins_server.public_ip
}

output "grafana_url" {
  description = "Grafana web URL."
  value       = var.create_route53_record ? "https://${aws_route53_record.jenkins_monitoring["grafana"].fqdn}" : module.monitoring_server.grafana_url
}

output "prometheus_url" {
  description = "Prometheus web URL."
  value       = var.create_route53_record ? "https://${aws_route53_record.jenkins_monitoring["prometheus"].fqdn}" : module.monitoring_server.prometheus_url
}

output "monitoring_instance_id" {
  description = "Monitoring EC2 instance ID."
  value       = module.monitoring_server.instance_id
}
