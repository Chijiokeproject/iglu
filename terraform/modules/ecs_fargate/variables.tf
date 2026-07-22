variable "project" {
  type        = string
  description = "Project name used with environment for naming ECS resources."

  validation {
    condition     = length(trimspace(var.project)) > 0
    error_message = "project must not be empty."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment name. Used for tags and Datadog DD_ENV."

  validation {
    condition     = length(trimspace(var.environment)) > 0
    error_message = "environment must not be empty."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region used for ECS resources."

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for ECS cluster resources."

  validation {
    condition     = startswith(var.vpc_id, "vpc-")
    error_message = "vpc_id must be a valid VPC ID starting with vpc-."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for the load balancer."

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "public_subnet_ids must contain at least two subnet IDs for ALB high availability."
  }
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the public HTTPS listener."

  validation {
    condition     = startswith(var.acm_certificate_arn, "arn:aws:acm:")
    error_message = "acm_certificate_arn must be a valid ACM certificate ARN."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for ECS tasks."

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "private_subnet_ids must contain at least two subnet IDs for ECS service high availability."
  }
}

variable "container_image" {
  type        = string
  description = "Container image to deploy."
  default     = "nginxinc/nginx-unprivileged:stable"

  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "container_image must not be empty."
  }
}

variable "container_port" {
  type        = number
  description = "Port exposed by the application container and targeted by the load balancer."
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "desired_count" {
  type        = number
  description = "Number of ECS tasks to run."
  default     = 2

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1."
  }
}

variable "task_cpu" {
  type        = string
  description = "Task CPU units."
  default     = "512"
}

variable "task_memory" {
  type        = string
  description = "Task memory in MiB."
  default     = "1024"
}

variable "log_retention_in_days" {
  type        = number
  description = "CloudWatch log retention in days for ECS application logs."
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1096, 1827, 2192, 2557,
      2922, 3288, 3653
    ], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a valid CloudWatch Logs retention value."
  }
}

variable "enable_datadog" {
  type        = bool
  description = "Enable the Datadog Agent sidecar for ECS Fargate."
  default     = false
}

variable "manage_datadog_secrets" {
  type        = bool
  description = "Create Secrets Manager containers for the Datadog API and application keys. Secret values must be populated outside Terraform."
  default     = true
}

variable "datadog_api_key_secret_arn" {
  type        = string
  description = "AWS Secrets Manager secret ARN containing the Datadog API key."
  default     = null

  validation {
    condition     = var.datadog_api_key_secret_arn == null ? true : startswith(var.datadog_api_key_secret_arn, "arn:aws:secretsmanager:")
    error_message = "datadog_api_key_secret_arn must be null or a Secrets Manager ARN."
  }
}

variable "datadog_api_key_secret_name" {
  type        = string
  description = "Optional AWS Secrets Manager name for the Datadog API key. Defaults to <project>/<environment>/datadog/api-key."
  default     = null

  validation {
    condition     = var.datadog_api_key_secret_name == null ? true : length(trimspace(var.datadog_api_key_secret_name)) > 0
    error_message = "datadog_api_key_secret_name must be null or a non-empty name."
  }
}

variable "datadog_app_key_secret_name" {
  type        = string
  description = "Optional AWS Secrets Manager name for the Datadog application key. Defaults to <project>/<environment>/datadog/app-key."
  default     = null

  validation {
    condition     = var.datadog_app_key_secret_name == null ? true : length(trimspace(var.datadog_app_key_secret_name)) > 0
    error_message = "datadog_app_key_secret_name must be null or a non-empty name."
  }
}

variable "datadog_site" {
  type        = string
  description = "Datadog site, for example datadoghq.com or datadoghq.eu."
  default     = "datadoghq.com"

  validation {
    condition     = contains(["datadoghq.com", "datadoghq.eu", "us3.datadoghq.com", "us5.datadoghq.com", "ap1.datadoghq.com", "ap2.datadoghq.com", "uk1.datadoghq.com"], var.datadog_site)
    error_message = "datadog_site must be one of: datadoghq.com, datadoghq.eu, us3.datadoghq.com, us5.datadoghq.com, ap1.datadoghq.com, ap2.datadoghq.com, uk1.datadoghq.com."
  }
}

variable "datadog_agent_image" {
  type        = string
  description = "Datadog Agent container image."
  default     = "public.ecr.aws/datadog/agent:latest"

  validation {
    condition     = length(trimspace(var.datadog_agent_image)) > 0
    error_message = "datadog_agent_image must not be empty."
  }
}

variable "datadog_firelens_image" {
  type        = string
  description = "AWS for Fluent Bit image used to send Fargate logs to Datadog through FireLens."
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"

  validation {
    condition     = length(trimspace(var.datadog_firelens_image)) > 0
    error_message = "datadog_firelens_image must not be empty."
  }
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

variable "tags" {
  type        = map(string)
  description = "Tags applied to ECS resources."
  default     = {}
}
