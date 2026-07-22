output "dev_cluster_id" {
  description = "ECS cluster ID for dev environment."
  value       = module.ecs_fargate.cluster_id
}

output "dev_alb_dns_name" {
  description = "Application Load Balancer DNS name for dev environment."
  value       = module.ecs_fargate.load_balancer_dns_name
}

output "dev_dns_name" {
  description = "Route 53 DNS name for dev application."
  value       = var.create_route53_record ? aws_route53_record.dev[0].fqdn : null
}

output "dev_url" {
  description = "HTTPS URL for the dev application."
  value       = "https://${local.dev_fqdn}"
}

output "dev_grafana_url" {
  description = "Grafana web URL for dev monitoring."
  value       = var.create_route53_record ? "https://${aws_route53_record.dev_monitoring["grafana"].fqdn}" : module.monitoring_server.grafana_url
}

output "dev_prometheus_url" {
  description = "Prometheus web URL for dev monitoring."
  value       = var.create_route53_record ? "https://${aws_route53_record.dev_monitoring["prometheus"].fqdn}" : module.monitoring_server.prometheus_url
}

output "dev_datadog_url" {
  description = "Datadog-hosted browser URL for ECS monitoring."
  value = lookup({
    "datadoghq.com"     = "https://app.datadoghq.com"
    "datadoghq.eu"      = "https://app.datadoghq.eu"
    "us3.datadoghq.com" = "https://us3.datadoghq.com"
    "us5.datadoghq.com" = "https://us5.datadoghq.com"
    "ap1.datadoghq.com" = "https://ap1.datadoghq.com"
    "ap2.datadoghq.com" = "https://ap2.datadoghq.com"
    "uk1.datadoghq.com" = "https://uk1.datadoghq.com"
  }, var.datadog_site)
}

output "dev_datadog_api_key_secret_arn" {
  description = "Secrets Manager ARN used for the dev Datadog API key."
  value       = module.ecs_fargate.datadog_api_key_secret_arn
}

output "dev_datadog_app_key_secret_arn" {
  description = "Secrets Manager ARN used for the dev Datadog application key."
  value       = module.ecs_fargate.datadog_app_key_secret_arn
}

output "dev_monitoring_instance_id" {
  description = "Monitoring EC2 instance ID for dev."
  value       = module.monitoring_server.instance_id
}
