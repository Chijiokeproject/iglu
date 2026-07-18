output "prod_cluster_id" {
  description = "ECS cluster ID for prod environment."
  value       = module.ecs_fargate.cluster_id
}

output "prod_alb_dns_name" {
  description = "Application Load Balancer DNS name for prod environment."
  value       = module.ecs_fargate.load_balancer_dns_name
}

output "prod_dns_name" {
  description = "Route 53 DNS name for prod application."
  value       = var.create_route53_record ? aws_route53_record.prod[0].fqdn : null
}

output "prod_url" {
  description = "Prod application URL using Route 53 DNS when enabled, otherwise the ALB DNS name."
  value       = var.create_route53_record ? "http://${aws_route53_record.prod[0].fqdn}" : "http://${module.ecs_fargate.load_balancer_dns_name}"
}

output "prod_grafana_url" {
  description = "Grafana web URL for prod monitoring."
  value       = var.create_route53_record ? "http://${aws_route53_record.prod_monitoring["grafana"].fqdn}:3000" : module.monitoring_server.grafana_url
}

output "prod_prometheus_url" {
  description = "Prometheus web URL for prod monitoring."
  value       = var.create_route53_record ? "http://${aws_route53_record.prod_monitoring["prometheus"].fqdn}:9090" : module.monitoring_server.prometheus_url
}

output "prod_datadog_url" {
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

output "prod_monitoring_instance_id" {
  description = "Monitoring EC2 instance ID for prod."
  value       = module.monitoring_server.instance_id
}
