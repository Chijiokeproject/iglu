variable "project" {
  type        = string
  description = "Project name used for naming resources."
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to deploy subnets into."
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every public subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets."
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every private subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all VPC resources."
  default     = {}
}
