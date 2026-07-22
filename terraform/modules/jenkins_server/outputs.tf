output "instance_id" {
  description = "Jenkins EC2 instance IDs."
  value       = aws_instance.jenkins[*].id
}

output "public_ip" {
  description = "Jenkins public IP addresses."
  value       = aws_instance.jenkins[*].public_ip
}

output "private_ip" {
  description = "Jenkins private IP addresses."
  value       = aws_instance.jenkins[*].private_ip
}

output "url" {
  description = "Jenkins web URL through the load balancer."
  value       = "${var.acm_certificate_arn == null ? "http" : "https"}://${aws_lb.jenkins.dns_name}"
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
