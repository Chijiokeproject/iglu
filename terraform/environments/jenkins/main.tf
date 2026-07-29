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
  count             = var.jenkins_acm_certificate_arn == null && var.create_route53_record ? 1 : 0
  domain_name       = local.jenkins_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.jenkins_acm_certificate_arn == null && var.create_route53_record ? toset([
    local.jenkins_fqdn,
  ]) : toset([])

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.primary[0].zone_id
  name = one([
    for option in aws_acm_certificate.jenkins[0].domain_validation_options :
    option.resource_record_name if option.domain_name == each.value
  ])
  type = one([
    for option in aws_acm_certificate.jenkins[0].domain_validation_options :
    option.resource_record_type if option.domain_name == each.value
  ])
  ttl = 60
  records = [one([
    for option in aws_acm_certificate.jenkins[0].domain_validation_options :
    option.resource_record_value if option.domain_name == each.value
  ])]
}

resource "aws_acm_certificate_validation" "jenkins" {
  count                   = var.jenkins_acm_certificate_arn == null && var.create_route53_record ? 1 : 0
  certificate_arn         = aws_acm_certificate.jenkins[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

module "vpc" {
  source                = "../../modules/vpc"
  project               = local.project
  environment           = local.environment
  cidr_block            = "10.2.0.0/16"
  availability_zones    = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnet_cidrs   = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs  = ["10.2.11.0/24", "10.2.12.0/24"]
  database_subnet_cidrs = ["10.2.21.0/24", "10.2.22.0/24"]
  nat_gateway_per_az    = true
  tags                  = local.tags
}

module "jenkins_server" {
  source                          = "../../modules/jenkins_server"
  project                         = local.project
  environment                     = local.environment
  aws_region                      = var.aws_region
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnet_ids
  load_balancer_subnet_ids        = module.vpc.public_subnet_ids
  allowed_admin_cidr              = var.allowed_admin_cidr
  acm_certificate_arn             = local.certificate_arn
  enable_https                    = true
  instance_type                   = var.jenkins_instance_type
  ami_id                          = var.jenkins_ami_id
  attach_admin_policy             = var.jenkins_attach_admin_policy
  ecr_repository_arns             = var.ecr_repository_arns
  terraform_state_bucket_name     = "iglu-terraform-state"
  terraform_state_lock_table_name = "iglu-terraform-locks"
  terraform_state_read_only_keys  = ["jenkins/terraform.tfstate"]
  terraform_state_read_write_keys = [
    "dev/terraform.tfstate",
    "tools/terraform.tfstate",
    "prod/terraform.tfstate"
  ]
  route53_hosted_zone_arns = var.create_route53_record ? [
    "arn:aws:route53:::hostedzone/${data.aws_route53_zone.primary[0].zone_id}"
  ] : []
  tags       = local.tags
  depends_on = [module.vpc]
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
