locals { name = "${var.project}-${var.environment}-bastion" }

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
  name               = "${local.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name}-profile"
  role = aws_iam_role.this.name
}

resource "aws_security_group" "this" {
  name        = "${local.name}-sg"
  description = "Hardened administrative jump host; SSH is optional."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.key_name == null ? [] : [1]
    content {
      description = "Restricted SSH administration"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_admin_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name}-sg" })
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.this.name
  key_name                    = var.key_name
  monitoring                  = true
  user_data                   = <<-USER_DATA
    #!/bin/bash
    set -euxo pipefail
    if ! swapon --show | grep -q /swapfile; then
      dd if=/dev/zero of=/swapfile bs=1M count=1024
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    fi
    for attempt in $(seq 1 10); do
      if dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm; then
        break
      fi
      sleep 15
    done
    rpm -q amazon-ssm-agent
    systemctl enable --now amazon-ssm-agent
  USER_DATA
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 10
    delete_on_termination = true
  }

  tags       = merge(var.tags, { Name = local.name })
  depends_on = [aws_iam_role_policy_attachment.ssm]
}
