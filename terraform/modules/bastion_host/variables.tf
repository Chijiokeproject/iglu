variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "ami_id" { type = string }
variable "instance_type" {
  type        = string
  description = "EC2 instance type for the bastion. RHEL requires t3.micro or larger in the T3 family."
  default     = "t3.micro"
}
variable "allowed_admin_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "allowed_admin_cidr must be a restricted IPv4 CIDR."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair. When null, SSH is disabled and Session Manager is used."
}
variable "tags" {
  type    = map(string)
  default = {}
}
