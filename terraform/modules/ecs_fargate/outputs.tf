output "cluster_id" {
  description = "ECS cluster ID."
  value       = aws_ecs_cluster.this.id
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "load_balancer_dns_name" {
  description = "DNS name for the application load balancer."
  value       = aws_lb.app.dns_name
}

output "load_balancer_zone_id" {
  description = "Route 53 hosted zone ID for the application load balancer."
  value       = aws_lb.app.zone_id
}

output "load_balancer_security_group_id" {
  description = "Application Load Balancer security group ID."
  value       = aws_security_group.alb.id
}

output "https_listener_arn" {
  description = "HTTPS listener ARN for additional host-based routes."
  value       = aws_lb_listener.https.arn
}

output "datadog_api_key_secret_arn" {
  description = "Secrets Manager ARN used for the Datadog API key."
  value       = local.datadog_api_key_secret_arn
}

output "datadog_app_key_secret_arn" {
  description = "Managed Secrets Manager ARN for the Datadog application key, or null when secret management is disabled."
  value       = local.datadog_app_key_secret_arn
}
