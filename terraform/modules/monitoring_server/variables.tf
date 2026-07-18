variable "project" {
  type        = string
  description = "Project name used for monitoring resource names."
}

variable "environment" {
  type        = string
  description = "Environment name used for monitoring resource names."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where monitoring will run."
}

variable "subnet_id" {
  type        = string
  description = "Public subnet ID where monitoring will run."
}

variable "allowed_admin_cidr" {
  type        = string
  description = "CIDR block allowed to access Grafana and Prometheus."

  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "allowed_admin_cidr must be a valid restricted CIDR and cannot be 0.0.0.0/0."
  }
}

variable "scrape_targets" {
  type        = list(string)
  description = "Additional Prometheus scrape targets such as private-ip:9100."
  default     = []
}

variable "http_probe_targets" {
  type        = list(string)
  description = "HTTP URLs that Prometheus should monitor through Blackbox Exporter."
  default     = []
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for Prometheus and Grafana."
  default     = "t3.small"
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB."
  default     = 30
}

variable "prometheus_version" {
  type        = string
  description = "Prometheus version to install."
  default     = "3.13.0"
}

variable "node_exporter_version" {
  type        = string
  description = "Node Exporter version to install."
  default     = "1.11.1"
}

variable "blackbox_exporter_version" {
  type        = string
  description = "Blackbox Exporter version to install."
  default     = "0.27.0"
}

variable "ami_id" {
  type        = string
  description = "Red Hat Enterprise Linux AMI ID for the monitoring EC2 instance."

  validation {
    condition     = startswith(var.ami_id, "ami-")
    error_message = "ami_id must be a valid AMI ID starting with ami-."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to monitoring resources."
  default     = {}
}
