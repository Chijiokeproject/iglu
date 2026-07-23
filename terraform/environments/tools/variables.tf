variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "jenkins_state_bucket" {
  type        = string
  description = "S3 bucket containing the Jenkins bootstrap state."
  default     = "iglu-terraform-state"
}

variable "jenkins_state_key" {
  type        = string
  description = "State key exported by the Jenkins bootstrap stack."
  default     = "jenkins/terraform.tfstate"
}

variable "allowed_admin_cidr" {
  type        = string
  description = "Restricted public CIDR allowed to access CI tools."
  default     = "88.97.185.63/32"

  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "allowed_admin_cidr must be a valid restricted CIDR and cannot be 0.0.0.0/0."
  }
}

variable "domain_name" {
  type    = string
  default = "chijiokedevops.com"
}

variable "jenkins_subdomain" {
  type    = string
  default = "jenkins"
}

variable "create_route53_records" {
  type        = bool
  description = "Create tool DNS records and a DNS-validated ACM certificate."
  default     = true
}

variable "tools_acm_certificate_arn" {
  type        = string
  description = "Optional existing ACM certificate covering the four CI tool hostnames."
  default     = null
}

variable "bastion_ami_id" {
  type    = string
  default = "ami-037b1265ce539a36b"
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"

  validation {
    condition     = var.bastion_instance_type != "t3.nano"
    error_message = "The configured RHEL AMI does not support t3.nano; use t3.micro or larger."
  }
}

variable "bastion_key_name" {
  type        = string
  description = "Optional EC2 key pair; null uses Session Manager only."
  default     = null
}

variable "tools_ami_id" {
  type    = string
  default = "ami-037b1265ce539a36b"
}

variable "tools_instance_type" {
  type    = string
  default = "t3.large"
}

variable "sonarqube_database_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "sonarqube_database_deletion_protection" {
  type    = bool
  default = true
}

variable "sonarqube_database_skip_final_snapshot" {
  type        = bool
  description = "Skip the final SonarQube database snapshot only when data loss is intentional."
  default     = false
}

variable "sonarqube_database_final_snapshot_identifier" {
  type        = string
  description = "Optional final snapshot identifier; otherwise the database module generates a unique suffix."
  default     = null
}

variable "monitoring_instance_type" {
  type    = string
  default = "t3.small"
}

variable "monitoring_ami_id" {
  type    = string
  default = "ami-037b1265ce539a36b"
}

variable "additional_http_probe_targets" {
  type    = list(string)
  default = []
}
