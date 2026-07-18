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
  description = "Route 53 domain name used for prod DNS."
  default     = "chijiokedevops.com"
}

variable "create_route53_record" {
  type        = bool
  description = "Create the prod DNS record in an existing public Route 53 hosted zone."
  default     = true
}

variable "prod_subdomain" {
  type        = string
  description = "Subdomain used for the prod application."
  default     = "prod"
}

variable "enable_datadog" {
  type        = bool
  description = "Enable the Datadog Agent sidecar for ECS Fargate."
  default     = false
}

variable "datadog_api_key_secret_arn" {
  type        = string
  description = "AWS Secrets Manager secret ARN containing the Datadog API key."
  default     = null
}

variable "datadog_api_key_secret_name" {
  type        = string
  description = "AWS Secrets Manager secret name containing the Datadog API key."
  default     = "iglu/datadog/api-key"
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
