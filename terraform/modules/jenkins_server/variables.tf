variable "project" {
  type        = string
  description = "Project name used for Jenkins resource names."
}

variable "environment" {
  type        = string
  description = "Environment name used for Jenkins resource names."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where Jenkins will run."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs where Jenkins instances will run."
}

variable "instance_count" {
  type        = number
  description = "Run exactly one Jenkins controller."
  default     = 1

  validation {
    condition     = var.instance_count == 1
    error_message = "instance_count must be exactly 1 because this deployment uses a single Jenkins controller."
  }
}

variable "allowed_admin_cidr" {
  type        = string
  description = "CIDR block allowed to access the Jenkins ALB."

  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "allowed_admin_cidr must be a valid restricted CIDR and cannot be 0.0.0.0/0."
  }
}

variable "acm_certificate_arn" {
  type        = string
  description = "Optional ACM certificate ARN for the Jenkins HTTPS listener. When null, the ALB uses HTTP for testing."
  default     = null

  validation {
    condition     = var.acm_certificate_arn == null ? true : startswith(var.acm_certificate_arn, "arn:aws:acm:")
    error_message = "acm_certificate_arn must be null or a valid ACM certificate ARN."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for Jenkins."
  default     = "t3.medium"
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB."
  default     = 30
}

variable "ami_id" {
  type        = string
  description = "Red Hat Enterprise Linux AMI ID for the Jenkins EC2 instances."

  validation {
    condition     = startswith(var.ami_id, "ami-")
    error_message = "ami_id must be a valid AMI ID starting with ami-."
  }
}

variable "attach_admin_policy" {
  type        = bool
  description = "Attach AdministratorAccess so Jenkins can run Terraform deployments. Use only for labs or replace with least privilege."
  default     = true
}

variable "node_exporter_version" {
  type        = string
  description = "Prometheus Node Exporter version installed on Jenkins."
  default     = "1.11.1"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to Jenkins resources."
  default     = {}
}
