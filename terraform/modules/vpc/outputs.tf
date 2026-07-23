output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets."
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs of isolated database subnets."
  value       = aws_subnet.database[*].id
}

output "nat_gateway_id" {
  description = "The primary NAT Gateway ID."
  value       = aws_nat_gateway.this.id
}

output "nat_gateway_ids" {
  description = "IDs of all NAT gateways."
  value       = concat([aws_nat_gateway.this.id], aws_nat_gateway.secondary[*].id)
}
