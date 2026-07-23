output "instance_ids" { value = { for name, instance in aws_instance.this : name => instance.id } }
output "security_group_id" { value = aws_security_group.this.id }
