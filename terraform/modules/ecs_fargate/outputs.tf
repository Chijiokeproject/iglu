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
