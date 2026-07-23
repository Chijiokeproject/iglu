locals {
  name_prefix = "${var.project}-${var.environment}"
  services = {
    nexus = {
      port     = 8081
      hostname = var.nexus_hostname
      priority = 40
      health   = "/service/rest/v1/status"
    }
    sonarqube = {
      port     = 9000
      hostname = var.sonarqube_hostname
      priority = 50
      health   = "/api/system/status"
    }
  }
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.name_prefix}-tools-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "sonar_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.sonarqube_database_secret_arn]
  }
}

resource "aws_iam_role_policy" "sonar_secret" {
  name   = "${local.name_prefix}-sonarqube-db-secret"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.sonar_secret.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name_prefix}-tools-profile"
  role = aws_iam_role.this.name
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-tools-sg"
  description = "Private Nexus and SonarQube services reachable only through the CI ALB."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = local.services
    content {
      description     = "${ingress.key} from ALB"
      from_port       = ingress.value.port
      to_port         = ingress.value.port
      protocol        = "tcp"
      security_groups = [var.load_balancer_security_group_id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${local.name_prefix}-tools-sg" })
}

resource "aws_instance" "this" {
  for_each = local.services

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = element(var.subnet_ids, index(keys(local.services), each.key))
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.this.name
  monitoring                  = true
  user_data = templatefile("${path.module}/userdata.sh", {
    service             = each.key
    aws_region          = var.aws_region
    database_endpoint   = var.sonarqube_database_endpoint
    database_name       = var.sonarqube_database_name
    database_secret_arn = var.sonarqube_database_secret_arn
  })
  user_data_replace_on_change = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = each.key == "nexus" ? 100 : 50
    delete_on_termination = false
  }

  tags       = merge(var.tags, { Name = "${local.name_prefix}-${each.key}" })
  depends_on = [aws_iam_role_policy_attachment.ssm]
}

resource "aws_lb_target_group" "this" {
  for_each = local.services
  name     = "${local.name_prefix}-${each.key}-tg"
  port     = each.value.port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path    = each.value.health
    matcher = "200-399"
  }
  tags = var.tags
}

resource "aws_lb_target_group_attachment" "this" {
  for_each         = local.services
  target_group_arn = aws_lb_target_group.this[each.key].arn
  target_id        = aws_instance.this[each.key].id
  port             = each.value.port
}

resource "aws_lb_listener_rule" "this" {
  for_each     = local.services
  listener_arn = var.https_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
  condition {
    host_header { values = [each.value.hostname] }
  }
  condition {
    source_ip { values = [var.allowed_admin_cidr] }
  }
}

resource "aws_lb_listener_rule" "deny_untrusted" {
  listener_arn = var.https_listener_arn
  priority     = 60
  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
  condition {
    host_header { values = [var.nexus_hostname, var.sonarqube_hostname] }
  }
}
