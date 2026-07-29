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

data "terraform_remote_state" "jenkins" {
  backend = "s3"

  config = {
    bucket = var.jenkins_state_bucket
    key    = var.jenkins_state_key
    region = var.aws_region
  }
}

locals {
  project = "iglu"
  # Keep the original resource-name prefix so existing CI tool resources can
  # be moved from the former combined Jenkins state without replacement.
  environment     = "jenkins"
  jenkins_fqdn    = "${var.jenkins_subdomain}.${var.domain_name}"
  grafana_fqdn    = "grafana.${var.domain_name}"
  prometheus_fqdn = "prometheus.${var.domain_name}"
  nexus_fqdn      = "nexus.${var.domain_name}"
  sonarqube_fqdn  = "sonar.${var.domain_name}"
  certificate_arn = var.tools_acm_certificate_arn != null ? var.tools_acm_certificate_arn : try(aws_acm_certificate_validation.tools[0].certificate_arn, null)
  jenkins         = data.terraform_remote_state.jenkins.outputs
  tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_route53_zone" "primary" {
  count        = var.create_route53_records ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "tools" {
  count                     = var.tools_acm_certificate_arn == null && var.create_route53_records ? 1 : 0
  domain_name               = local.nexus_fqdn
  subject_alternative_names = [local.sonarqube_fqdn, local.grafana_fqdn, local.prometheus_fqdn]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.tools_acm_certificate_arn == null && var.create_route53_records ? {
    for option in aws_acm_certificate.tools[0].domain_validation_options : option.domain_name => {
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

resource "aws_acm_certificate_validation" "tools" {
  count                   = var.tools_acm_certificate_arn == null && var.create_route53_records ? 1 : 0
  certificate_arn         = aws_acm_certificate.tools[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_lb_listener_certificate" "tools" {
  listener_arn    = local.jenkins.https_listener_arn
  certificate_arn = local.certificate_arn

  lifecycle {
    precondition {
      condition     = local.certificate_arn != null
      error_message = "Provide tools_acm_certificate_arn when Route 53 certificate creation is disabled."
    }
  }
}

module "bastion" {
  source             = "../../modules/bastion_host"
  project            = local.project
  environment        = local.environment
  vpc_id             = local.jenkins.vpc_id
  subnet_id          = local.jenkins.public_subnet_ids[0]
  ami_id             = var.bastion_ami_id
  instance_type      = var.bastion_instance_type
  allowed_admin_cidr = var.allowed_admin_cidr
  key_name           = var.bastion_key_name
  tags               = local.tags
}

module "sonarqube_database" {
  source                     = "../../modules/database"
  project                    = local.project
  environment                = "${local.environment}-sonar"
  vpc_id                     = local.jenkins.vpc_id
  subnet_ids                 = local.jenkins.database_subnet_ids
  allowed_security_group_ids = []
  database_name              = "sonarqube"
  instance_class             = var.sonarqube_database_instance_class
  allocated_storage          = 50
  multi_az                   = true
  deletion_protection        = var.sonarqube_database_deletion_protection
  skip_final_snapshot        = var.sonarqube_database_skip_final_snapshot
  final_snapshot_identifier  = var.sonarqube_database_final_snapshot_identifier
  backup_retention_period    = 14
  tags                       = local.tags
}

module "devops_tools" {
  source                          = "../../modules/devops_tools"
  project                         = local.project
  environment                     = local.environment
  aws_region                      = var.aws_region
  vpc_id                          = local.jenkins.vpc_id
  subnet_ids                      = local.jenkins.private_subnet_ids
  ami_id                          = var.tools_ami_id
  instance_type                   = var.tools_instance_type
  load_balancer_security_group_id = local.jenkins.load_balancer_security_group_id
  https_listener_arn              = local.jenkins.https_listener_arn
  nexus_hostname                  = local.nexus_fqdn
  sonarqube_hostname              = local.sonarqube_fqdn
  allowed_admin_cidr              = var.allowed_admin_cidr
  sonarqube_database_endpoint     = module.sonarqube_database.endpoint
  sonarqube_database_name         = module.sonarqube_database.database_name
  sonarqube_database_secret_arn   = module.sonarqube_database.master_user_secret_arn
  tags                            = local.tags
}

resource "aws_security_group_rule" "tools_to_sonarqube_database" {
  type                     = "ingress"
  description              = "SonarQube PostgreSQL access"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.sonarqube_database.security_group_id
  source_security_group_id = module.devops_tools.security_group_id
}

module "monitoring_server" {
  source                          = "../../modules/monitoring_server"
  project                         = local.project
  environment                     = local.environment
  aws_region                      = var.aws_region
  vpc_id                          = local.jenkins.vpc_id
  subnet_id                       = local.jenkins.private_subnet_ids[1]
  associate_public_ip_address     = false
  load_balancer_security_group_id = local.jenkins.load_balancer_security_group_id
  https_listener_arn              = local.jenkins.https_listener_arn
  grafana_hostname                = local.grafana_fqdn
  prometheus_hostname             = local.prometheus_fqdn
  allowed_admin_cidr              = var.allowed_admin_cidr
  instance_type                   = var.monitoring_instance_type
  ami_id                          = var.monitoring_ami_id
  ec2_sd_tag_name                 = "iglu-jenkins-jenkins"
  http_probe_targets = concat(
    var.create_route53_records ? ["https://${local.jenkins_fqdn}/login"] : [],
    [
      "http://localhost:3000/login",
      "http://localhost:9090/-/healthy"
    ],
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
  security_group_id        = local.jenkins.jenkins_security_group_id
  source_security_group_id = module.monitoring_server.security_group_id
}

resource "aws_security_group_rule" "monitoring_to_jenkins_web" {
  type                     = "ingress"
  description              = "Allow Prometheus Blackbox Exporter to probe Jenkins"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = local.jenkins.jenkins_security_group_id
  source_security_group_id = module.monitoring_server.security_group_id
}

resource "aws_route53_record" "jenkins_monitoring" {
  for_each = var.create_route53_records ? {
    grafana    = local.grafana_fqdn
    prometheus = local.prometheus_fqdn
  } : {}

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = local.jenkins.load_balancer_dns_name
    zone_id                = local.jenkins.load_balancer_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "jenkins_tools" {
  for_each = var.create_route53_records ? {
    nexus = local.nexus_fqdn
    sonar = local.sonarqube_fqdn
  } : {}

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = local.jenkins.load_balancer_dns_name
    zone_id                = local.jenkins.load_balancer_zone_id
    evaluate_target_health = true
  }
}
