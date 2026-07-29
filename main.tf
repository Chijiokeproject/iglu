terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  project         = "iglu"
  environment     = "dev"
  dev_fqdn        = "${var.dev_subdomain}.${var.domain_name}"
  grafana_fqdn    = "grafana.${local.dev_fqdn}"
  prometheus_fqdn = "prometheus.${local.dev_fqdn}"
  certificate_arn = var.acm_certificate_arn != null ? var.acm_certificate_arn : try(aws_acm_certificate_validation.environment[0].certificate_arn, null)
  tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_route53_zone" "primary" {
  count        = var.create_route53_record ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "environment" {
  count                     = var.acm_certificate_arn == null && var.create_route53_record ? 1 : 0
  domain_name               = local.dev_fqdn
  subject_alternative_names = [local.grafana_fqdn, local.prometheus_fqdn]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.acm_certificate_arn == null && var.create_route53_record ? toset([
    local.dev_fqdn,
    local.grafana_fqdn,
    local.prometheus_fqdn,
  ]) : toset([])

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.primary[0].zone_id
  name = one([
    for option in aws_acm_certificate.environment[0].domain_validation_options :
    option.resource_record_name if option.domain_name == each.value
  ])
  type = one([
    for option in aws_acm_certificate.environment[0].domain_validation_options :
    option.resource_record_type if option.domain_name == each.value
  ])
  ttl = 60
  records = [one([
    for option in aws_acm_certificate.environment[0].domain_validation_options :
    option.resource_record_value if option.domain_name == each.value
  ])]
}

resource "aws_acm_certificate_validation" "environment" {
  count                   = var.acm_certificate_arn == null && var.create_route53_record ? 1 : 0
  certificate_arn         = aws_acm_certificate.environment[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

module "vpc" {
  source               = "./terraform/modules/vpc"
  project              = local.project
  environment          = local.environment
  cidr_block           = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  tags                 = local.tags
}

module "ecs_fargate" {
  source                      = "./terraform/modules/ecs_fargate"
  project                     = local.project
  environment                 = local.environment
  aws_region                  = "us-east-1"
  vpc_id                      = module.vpc.vpc_id
  public_subnet_ids           = module.vpc.public_subnet_ids
  private_subnet_ids          = module.vpc.private_subnet_ids
  acm_certificate_arn         = local.certificate_arn
  container_image             = "nginxinc/nginx-unprivileged:stable"
  enable_datadog              = var.enable_datadog
  manage_datadog_secrets      = var.manage_datadog_secrets
  datadog_api_key_secret_arn  = var.datadog_api_key_secret_arn
  datadog_api_key_secret_name = var.datadog_api_key_secret_name
  datadog_app_key_secret_name = var.datadog_app_key_secret_name
  datadog_site                = var.datadog_site
  datadog_logs_enabled        = var.datadog_logs_enabled
  datadog_apm_enabled         = var.datadog_apm_enabled
  tags                        = local.tags
  depends_on                  = [module.vpc]
}

module "monitoring_server" {
  source                          = "./terraform/modules/monitoring_server"
  project                         = local.project
  environment                     = local.environment
  aws_region                      = "us-east-1"
  vpc_id                          = module.vpc.vpc_id
  subnet_id                       = module.vpc.private_subnet_ids[1]
  associate_public_ip_address     = false
  load_balancer_security_group_id = module.ecs_fargate.load_balancer_security_group_id
  https_listener_arn              = module.ecs_fargate.https_listener_arn
  grafana_hostname                = local.grafana_fqdn
  prometheus_hostname             = local.prometheus_fqdn
  allowed_admin_cidr              = var.allowed_admin_cidr
  instance_type                   = var.monitoring_instance_type
  ami_id                          = var.monitoring_ami_id
  enable_ecs_discovery            = true
  ecs_cluster_name                = module.ecs_fargate.cluster_name
  http_probe_targets = concat([
    "https://${local.dev_fqdn}",
    "http://localhost:3000/login",
    "http://localhost:9090/-/healthy"
  ], var.additional_http_probe_targets)
  tags       = local.tags
  depends_on = [module.vpc]
}

resource "aws_route53_record" "dev" {
  count   = var.create_route53_record ? 1 : 0
  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = local.dev_fqdn
  type    = "A"

  alias {
    name                   = module.ecs_fargate.load_balancer_dns_name
    zone_id                = module.ecs_fargate.load_balancer_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "dev_monitoring" {
  for_each = var.create_route53_record ? toset(["grafana", "prometheus"]) : toset([])

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = "${each.value}.${local.dev_fqdn}"
  type    = "A"

  alias {
    name                   = module.ecs_fargate.load_balancer_dns_name
    zone_id                = module.ecs_fargate.load_balancer_zone_id
    evaluate_target_health = true
  }
}
