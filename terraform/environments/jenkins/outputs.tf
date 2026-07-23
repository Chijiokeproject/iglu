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

output "jenkins_autoscaling_group_name" {
  description = "Jenkins controller Auto Scaling Group."
  value       = module.jenkins_server.autoscaling_group_name
}

output "jenkins_home_efs_id" {
  description = "Encrypted EFS file system holding durable Jenkins controller state."
  value       = module.jenkins_server.efs_file_system_id
}

output "vpc_id" {
  description = "Jenkins VPC ID consumed by the optional tools stack."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs consumed by the optional tools stack."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs consumed by the optional tools stack."
  value       = module.vpc.private_subnet_ids
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs consumed by the optional tools stack."
  value       = module.vpc.database_subnet_ids
}

output "load_balancer_dns_name" {
  description = "Shared CI load balancer DNS name."
  value       = module.jenkins_server.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  description = "Shared CI load balancer Route 53 zone ID."
  value       = module.jenkins_server.load_balancer_zone_id
}

output "load_balancer_security_group_id" {
  description = "Shared CI load balancer security group ID."
  value       = module.jenkins_server.load_balancer_security_group_id
}

output "https_listener_arn" {
  description = "Shared CI HTTPS listener ARN used by optional tools."
  value       = module.jenkins_server.https_listener_arn
}

output "jenkins_security_group_id" {
  description = "Jenkins security group ID used by optional monitoring."
  value       = module.jenkins_server.security_group_id
}
