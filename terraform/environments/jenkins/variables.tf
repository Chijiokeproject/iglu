variable "aws_region" {
  type        = string
  description = "AWS region for the Jenkins server."
  default     = "us-east-1"
}

variable "allowed_admin_cidr" {
  type        = string
  description = "Public IP CIDR allowed to access Jenkins HTTPS, Grafana, and Prometheus."
  default     = "88.97.185.63/32"

  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "allowed_admin_cidr must be a valid restricted CIDR and cannot be 0.0.0.0/0."
  }
}

variable "jenkins_acm_certificate_arn" {
  type        = string
  description = "Optional existing ACM certificate ARN for Jenkins, Grafana, and Prometheus. When null, Terraform creates and DNS-validates one."
  default     = null

  validation {
    condition     = var.jenkins_acm_certificate_arn == null ? true : startswith(var.jenkins_acm_certificate_arn, "arn:aws:acm:")
    error_message = "jenkins_acm_certificate_arn must be null or a valid ACM certificate ARN."
  }
}

variable "jenkins_instance_type" {
  type        = string
  description = "EC2 instance type for Jenkins."
  default     = "t3.medium"
}

variable "jenkins_ami_id" {
  type        = string
  description = "Red Hat Enterprise Linux AMI ID for Jenkins EC2 instances."
  default     = "ami-037b1265ce539a36b"

  validation {
    condition     = startswith(var.jenkins_ami_id, "ami-")
    error_message = "jenkins_ami_id must be a valid AMI ID starting with ami-."
  }
}

variable "jenkins_attach_admin_policy" {
  type        = bool
  description = "Attach AdministratorAccess to Jenkins so its Terraform pipeline can manage the account."
  default     = true
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ECR repository ARNs Jenkins is allowed to push to."
  default     = []
}

variable "domain_name" {
  type        = string
  description = "Route 53 domain name used for Jenkins DNS."
  default     = "chijiokedevops.com"
}

variable "create_route53_record" {
  type        = bool
  description = "Create the Jenkins DNS record in an existing public Route 53 hosted zone."
  default     = true
}

variable "jenkins_subdomain" {
  type        = string
  description = "Subdomain used for the Jenkins server."
  default     = "jenkins"
}
