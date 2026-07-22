variable "allowed_admin_cidr" {
  type        = string
  description = "Public IP CIDR allowed to access Grafana and Prometheus."
  default     = "88.97.185.63/32"

  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "allowed_admin_cidr must be a valid restricted CIDR and cannot be 0.0.0.0/0."
  }
}

variable "monitoring_instance_type" {
  type        = string
  description = "EC2 instance type for Prometheus and Grafana."
  default     = "t3.small"
}

variable "monitoring_ami_id" {
  type        = string
  description = "Red Hat Enterprise Linux AMI ID for the monitoring EC2 instance."
  default     = "ami-037b1265ce539a36b"

  validation {
    condition     = startswith(var.monitoring_ami_id, "ami-")
    error_message = "monitoring_ami_id must be a valid AMI ID starting with ami-."
  }
}

variable "additional_http_probe_targets" {
  type        = list(string)
  description = "Additional HTTP URLs for Prometheus Blackbox Exporter to monitor."
  default     = []
}

variable "domain_name" {
  type        = string
  description = "Route 53 domain name used for dev DNS."
  default     = "chijiokedevops.com"
}

variable "create_route53_record" {
  type        = bool
  description = "Create the dev DNS record in an existing public Route 53 hosted zone."
  default     = true
}

variable "acm_certificate_arn" {
  type        = string
  description = "Optional existing ACM certificate ARN covering the application, Grafana, and Prometheus hostnames."
  default     = null

  validation {
    condition     = var.acm_certificate_arn == null ? true : startswith(var.acm_certificate_arn, "arn:aws:acm:")
    error_message = "acm_certificate_arn must be null or a valid ACM certificate ARN."
  }
}

variable "dev_subdomain" {
  type        = string
  description = "Subdomain used for the dev application."
  default     = "dev"
}

variable "enable_datadog" {
  type        = bool
  description = "Enable the Datadog Agent sidecar for ECS Fargate."
  default     = false
}

variable "manage_datadog_secrets" {
  type        = bool
  description = "Create Secrets Manager containers for the Datadog API and application keys."
  default     = true
}

variable "datadog_api_key_secret_arn" {
  type        = string
  description = "AWS Secrets Manager secret ARN containing the Datadog API key."
  default     = null
}

variable "datadog_api_key_secret_name" {
  type        = string
  description = "Optional AWS Secrets Manager name for the Datadog API key."
  default     = null
}

variable "datadog_app_key_secret_name" {
  type        = string
  description = "Optional AWS Secrets Manager name for the Datadog application key."
  default     = null
}

variable "datadog_site" {
  type        = string
  description = "Datadog site, for example datadoghq.com or datadoghq.eu."
  default     = "datadoghq.com"
}

variable "datadog_logs_enabled" {
  type        = bool
  description = "Enable Datadog log collection from ECS containers."
  default     = true
}

variable "datadog_apm_enabled" {
  type        = bool
  description = "Enable Datadog APM in the Agent sidecar."
  default     = true
}
