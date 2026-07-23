variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "ami_id" { type = string }
variable "instance_type" {
  type    = string
  default = "t3.large"
}
variable "load_balancer_security_group_id" { type = string }
variable "https_listener_arn" { type = string }
variable "nexus_hostname" { type = string }
variable "sonarqube_hostname" { type = string }
variable "allowed_admin_cidr" { type = string }
variable "sonarqube_database_endpoint" { type = string }
variable "sonarqube_database_name" { type = string }
variable "sonarqube_database_secret_arn" { type = string }
variable "aws_region" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
