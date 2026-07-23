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
  environment     = "prod"
  prod_fqdn       = "${var.prod_subdomain}.${var.domain_name}"
  grafana_fqdn    = "grafana.${local.prod_fqdn}"
  prometheus_fqdn = "prometheus.${local.prod_fqdn}"
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
  domain_name               = local.prod_fqdn
  subject_alternative_names = [local.grafana_fqdn, local.prometheus_fqdn]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.acm_certificate_arn == null && var.create_route53_record ? {
    for option in aws_acm_certificate.environment[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.primary[0].zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "environment" {
  count                   = var.acm_certificate_arn == null && var.create_route53_record ? 1 : 0
  certificate_arn         = aws_acm_certificate.environment[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

module "vpc" {
  source                = "../../modules/vpc"
  project               = local.project
  environment           = local.environment
  cidr_block            = "10.1.0.0/16"
  availability_zones    = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs   = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs  = ["10.1.11.0/24", "10.1.12.0/24"]
  database_subnet_cidrs = ["10.1.21.0/24", "10.1.22.0/24"]
  nat_gateway_per_az    = true
  tags                  = local.tags
}

module "bastion" {
  source             = "../../modules/bastion_host"
  project            = local.project
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnet_ids[0]
  ami_id             = var.bastion_ami_id
  instance_type      = var.bastion_instance_type
  allowed_admin_cidr = var.allowed_admin_cidr
  key_name           = var.bastion_key_name
  tags               = local.tags
  depends_on         = [module.vpc]
}

module "ecr" {
  source      = "../../modules/ecr"
  project     = local.project
  environment = local.environment
  tags        = local.tags
}

module "ecs_fargate" {
  source                      = "../../modules/ecs_fargate"
  project                     = local.project
  environment                 = local.environment
  aws_region                  = "us-east-1"
  vpc_id                      = module.vpc.vpc_id
  public_subnet_ids           = module.vpc.public_subnet_ids
  private_subnet_ids          = module.vpc.private_subnet_ids
  acm_certificate_arn         = local.certificate_arn
  container_image             = var.container_image
  database_endpoint           = module.database.endpoint
  database_name               = module.database.database_name
  database_secret_arn         = module.database.master_user_secret_arn
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

module "database" {
  source                     = "../../modules/database"
  project                    = local.project
  environment                = local.environment
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.database_subnet_ids
  allowed_security_group_ids = [module.bastion.security_group_id]
  database_name              = var.database_name
  instance_class             = var.database_instance_class
  allocated_storage          = var.database_allocated_storage
  multi_az                   = true
  deletion_protection        = var.database_deletion_protection
  backup_retention_period    = var.database_backup_retention_period
  tags                       = local.tags
}

resource "aws_security_group_rule" "ecs_to_database" {
  type                     = "ingress"
  description              = "PostgreSQL from ECS application tasks"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.database.security_group_id
  source_security_group_id = module.ecs_fargate.service_security_group_id
}

module "monitoring_server" {
  source                          = "../../modules/monitoring_server"
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
  ecs_cluster_name                = module.ecs_fargate.cluster_name
  http_probe_targets = concat([
    "https://${local.prod_fqdn}",
    "http://localhost:3000/login",
    "http://localhost:9090/-/healthy"
  ], var.additional_http_probe_targets)
  tags       = local.tags
  depends_on = [module.vpc]
}

resource "aws_route53_record" "prod" {
  count   = var.create_route53_record ? 1 : 0
  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = local.prod_fqdn
  type    = "A"

  alias {
    name                   = module.ecs_fargate.load_balancer_dns_name
    zone_id                = module.ecs_fargate.load_balancer_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "prod_monitoring" {
  for_each = var.create_route53_record ? toset(["grafana", "prometheus"]) : toset([])

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = "${each.value}.${local.prod_fqdn}"
  type    = "A"

  alias {
    name                   = module.ecs_fargate.load_balancer_dns_name
    zone_id                = module.ecs_fargate.load_balancer_zone_id
    evaluate_target_health = true
  }
}
