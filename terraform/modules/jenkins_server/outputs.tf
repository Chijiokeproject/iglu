output "autoscaling_group_name" {
  description = "Jenkins controller Auto Scaling Group name."
  value       = aws_autoscaling_group.jenkins.name
}

output "efs_file_system_id" {
  description = "Encrypted EFS file system storing JENKINS_HOME."
  value       = aws_efs_file_system.jenkins_home.id
}

output "url" {
  description = "Jenkins web URL through the load balancer."
  value       = "${var.enable_https ? "https" : "http"}://${aws_lb.jenkins.dns_name}"
}

output "load_balancer_dns_name" {
  description = "Jenkins application load balancer DNS name."
  value       = aws_lb.jenkins.dns_name
}

output "load_balancer_zone_id" {
  description = "Jenkins application load balancer Route 53 zone ID."
  value       = aws_lb.jenkins.zone_id
}

output "security_group_id" {
  description = "Jenkins security group ID."
  value       = aws_security_group.jenkins.id
}

output "load_balancer_security_group_id" {
  description = "Jenkins load balancer security group ID."
  value       = aws_security_group.alb.id
}

output "https_listener_arn" {
  description = "Jenkins HTTPS listener ARN for additional host-based routes."
  value       = try(aws_lb_listener.https[0].arn, null)
}
