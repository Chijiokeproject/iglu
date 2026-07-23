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

variable "aws_region" {
  type        = string
  description = "AWS region used for EFS DNS and Jenkins tooling."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs where Jenkins instances will run."
}

variable "load_balancer_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for the internet-facing Jenkins load balancer."
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ECR repositories Jenkins may push application images to."
  default     = []
}

variable "terraform_state_bucket_name" {
  type        = string
  description = "S3 bucket containing the Terraform states used by the Jenkins pipeline."
  default     = null
  nullable    = true
}

variable "terraform_state_lock_table_name" {
  type        = string
  description = "DynamoDB table used to lock the Terraform states."
  default     = null
  nullable    = true
}

variable "terraform_state_read_only_keys" {
  type        = list(string)
  description = "Terraform state object keys Jenkins may read but not modify."
  default     = []
}

variable "terraform_state_read_write_keys" {
  type        = list(string)
  description = "Terraform state object keys Jenkins may read and modify."
  default     = []
}

variable "route53_hosted_zone_arns" {
  type        = list(string)
  description = "Route 53 hosted zones where Jenkins may manage pipeline DNS validation and service records."
  default     = []
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

variable "enable_https" {
  type        = bool
  description = "Create the HTTPS listener and HTTP-to-HTTPS redirect. This must be a plan-time-known value."
  default     = false
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
  default     = false
}

variable "node_exporter_version" {
  type        = string
  description = "Prometheus Node Exporter version installed on Jenkins."
  default     = "1.11.1"
}

variable "checkov_version" {
  type        = string
  description = "Pinned Checkov version installed on Jenkins."
  default     = "3.3.8"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to Jenkins resources."
  default     = {}
}
