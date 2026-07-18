output "jenkins_url" {
  description = "Jenkins web URL."
  value       = module.jenkins_server.url
}

output "jenkins_dns_name" {
  description = "Route 53 DNS name for Jenkins."
  value       = var.create_route53_record ? aws_route53_record.jenkins[0].fqdn : null
}

output "jenkins_dns_url" {
  description = "Jenkins URL using Route 53 DNS when enabled, otherwise the ALB DNS name."
  value       = var.create_route53_record ? "${local.jenkins_scheme}://${aws_route53_record.jenkins[0].fqdn}" : module.jenkins_server.url
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
  value       = var.create_route53_record ? "http://${aws_route53_record.jenkins_monitoring["grafana"].fqdn}:3000" : module.monitoring_server.grafana_url
}

output "prometheus_url" {
  description = "Prometheus web URL."
  value       = var.create_route53_record ? "http://${aws_route53_record.jenkins_monitoring["prometheus"].fqdn}:9090" : module.monitoring_server.prometheus_url
}

output "monitoring_instance_id" {
  description = "Monitoring EC2 instance ID."
  value       = module.monitoring_server.instance_id
}
