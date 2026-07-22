data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  prometheus_targets = concat(["localhost:9100"], var.scrape_targets)
  prometheus_targets_yaml = join(", ", [
    for target in local.prometheus_targets : "\"${target}\""
  ])
  http_probe_targets_yaml = join(", ", [
    for target in var.http_probe_targets : "\"${target}\""
  ])
}

resource "aws_iam_role" "monitoring" {
  name               = "${var.project}-${var.environment}-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project}-${var.environment}-monitoring-profile"
  role = aws_iam_role.monitoring.name
}

resource "aws_security_group" "monitoring" {
  name        = "${var.project}-${var.environment}-monitoring-sg"
  description = "Security group for Prometheus and Grafana."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Grafana from monitoring ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [var.load_balancer_security_group_id]
  }

  ingress {
    description     = "Prometheus from monitoring ALB"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [var.load_balancer_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-monitoring-sg"
  })
}

resource "aws_lb_target_group" "grafana" {
  name     = "${var.project}-${var.environment}-grafana-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path    = "/api/health"
    matcher = "200"
  }

  tags = var.tags
}

resource "aws_lb_target_group" "prometheus" {
  name     = "${var.project}-${var.environment}-prom-tg"
  port     = 9090
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path    = "/-/healthy"
    matcher = "200"
  }

  tags = var.tags
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = aws_instance.monitoring.id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "prometheus" {
  target_group_arn = aws_lb_target_group.prometheus.arn
  target_id        = aws_instance.monitoring.id
  port             = 9090
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = var.https_listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    host_header {
      values = [var.grafana_hostname]
    }
  }

  condition {
    source_ip {
      values = [var.allowed_admin_cidr]
    }
  }
}

resource "aws_lb_listener_rule" "prometheus" {
  listener_arn = var.https_listener_arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }

  condition {
    host_header {
      values = [var.prometheus_hostname]
    }
  }

  condition {
    source_ip {
      values = [var.allowed_admin_cidr]
    }
  }
}

resource "aws_lb_listener_rule" "deny_untrusted_monitoring_access" {
  listener_arn = var.https_listener_arn
  priority     = 30

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    host_header {
      values = [var.grafana_hostname, var.prometheus_hostname]
    }
  }
}

resource "aws_instance" "monitoring" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  user_data = templatefile("${path.module}/userdata.sh", {
    prometheus_version        = var.prometheus_version
    node_exporter_version     = var.node_exporter_version
    blackbox_exporter_version = var.blackbox_exporter_version
    prometheus_targets_yaml   = local.prometheus_targets_yaml
    http_probe_targets_yaml   = local.http_probe_targets_yaml
    grafana_hostname          = var.grafana_hostname
    prometheus_hostname       = var.prometheus_hostname
  })
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.monitoring.name
  user_data_replace_on_change = true

  depends_on = [aws_iam_role_policy_attachment.ssm]

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-monitoring"
  })
}
