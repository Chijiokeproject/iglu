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
    description = "Grafana web UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  ingress {
    description = "Prometheus web UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
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
