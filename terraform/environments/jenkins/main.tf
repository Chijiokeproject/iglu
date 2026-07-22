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
  region = var.aws_region
}

locals {
  project          = "iglu"
  environment      = "jenkins"
  environment_type = "prod"
  jenkins_fqdn     = "${var.jenkins_subdomain}.${var.domain_name}"
  grafana_fqdn     = "grafana.${local.jenkins_fqdn}"
  prometheus_fqdn  = "prometheus.${local.jenkins_fqdn}"
  certificate_arn  = var.jenkins_acm_certificate_arn != null ? var.jenkins_acm_certificate_arn : try(aws_acm_certificate_validation.jenkins[0].certificate_arn, null)
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

resource "aws_acm_certificate" "jenkins" {
  count                     = var.jenkins_acm_certificate_arn == null && var.create_route53_record ? 1 : 0
  domain_name               = local.jenkins_fqdn
  subject_alternative_names = [local.grafana_fqdn, local.prometheus_fqdn]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.jenkins_acm_certificate_arn == null && var.create_route53_record ? {
    for option in aws_acm_certificate.jenkins[0].domain_validation_options : option.domain_name => {
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

resource "aws_acm_certificate_validation" "jenkins" {
  count                   = var.jenkins_acm_certificate_arn == null && var.create_route53_record ? 1 : 0
  certificate_arn         = aws_acm_certificate.jenkins[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

module "vpc" {
  source               = "../../modules/vpc"
  project              = local.project
  environment          = local.environment
  cidr_block           = "10.2.0.0/16"
  availability_zones   = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]
  tags                 = local.tags
}

module "jenkins_server" {
  source              = "../../modules/jenkins_server"
  project             = local.project
  environment         = local.environment
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.public_subnet_ids
  allowed_admin_cidr  = var.allowed_admin_cidr
  acm_certificate_arn = local.certificate_arn
  instance_type       = var.jenkins_instance_type
  ami_id              = var.jenkins_ami_id
  instance_count      = var.jenkins_instance_count
  tags                = local.tags
}

module "monitoring_server" {
  source                          = "../../modules/monitoring_server"
  project                         = local.project
  environment                     = local.environment
  vpc_id                          = module.vpc.vpc_id
  subnet_id                       = module.vpc.public_subnet_ids[1]
  load_balancer_security_group_id = module.jenkins_server.load_balancer_security_group_id
  https_listener_arn              = module.jenkins_server.https_listener_arn
  grafana_hostname                = local.grafana_fqdn
  prometheus_hostname             = local.prometheus_fqdn
  allowed_admin_cidr              = var.allowed_admin_cidr
  instance_type                   = var.monitoring_instance_type
  ami_id                          = var.monitoring_ami_id
  scrape_targets                  = formatlist("%s:9100", module.jenkins_server.private_ip)
  http_probe_targets = concat(
    var.create_route53_record ? ["https://${local.jenkins_fqdn}/login"] : [],
    [
      "http://localhost:3000/login",
      "http://localhost:9090/-/healthy"
    ],
    formatlist("http://%s:8080/login", module.jenkins_server.private_ip),
    var.additional_http_probe_targets
  )
  tags = local.tags
}

resource "aws_security_group_rule" "monitoring_to_jenkins_node_exporter" {
  type                     = "ingress"
  description              = "Allow Prometheus to scrape Jenkins Node Exporter"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = module.jenkins_server.security_group_id
  source_security_group_id = module.monitoring_server.security_group_id
}

resource "aws_security_group_rule" "monitoring_to_jenkins_web" {
  type                     = "ingress"
  description              = "Allow Prometheus Blackbox Exporter to probe Jenkins"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.jenkins_server.security_group_id
  source_security_group_id = module.monitoring_server.security_group_id
}

resource "aws_route53_record" "jenkins" {
  count   = var.create_route53_record ? 1 : 0
  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = local.jenkins_fqdn
  type    = "A"

  alias {
    name                   = module.jenkins_server.load_balancer_dns_name
    zone_id                = module.jenkins_server.load_balancer_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "jenkins_monitoring" {
  for_each = var.create_route53_record ? toset(["grafana", "prometheus"]) : toset([])

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = "${each.value}.${local.jenkins_fqdn}"
  type    = "A"

  alias {
    name                   = module.jenkins_server.load_balancer_dns_name
    zone_id                = module.jenkins_server.load_balancer_zone_id
    evaluate_target_health = true
  }
}
