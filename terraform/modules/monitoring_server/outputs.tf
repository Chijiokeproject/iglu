output "instance_id" {
  description = "Monitoring EC2 instance ID."
  value       = aws_instance.monitoring.id
}

output "public_ip" {
  description = "Monitoring public IP address."
  value       = aws_instance.monitoring.public_ip
}

output "private_ip" {
  description = "Monitoring private IP address."
  value       = aws_instance.monitoring.private_ip
}

output "grafana_url" {
  description = "Grafana web URL."
  value       = "https://${var.grafana_hostname}"
}

output "prometheus_url" {
  description = "Prometheus web URL."
  value       = "https://${var.prometheus_hostname}"
}

output "security_group_id" {
  description = "Monitoring security group ID."
  value       = aws_security_group.monitoring.id
}
