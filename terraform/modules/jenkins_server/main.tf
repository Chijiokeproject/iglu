data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  name               = "${var.project}-${var.environment}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "admin" {
  count      = var.attach_admin_policy ? 1 : 0
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project}-${var.environment}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

resource "aws_security_group" "jenkins" {
  name        = "${var.project}-${var.environment}-jenkins-sg"
  description = "Security group for Jenkins server."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Jenkins web UI from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-jenkins-sg"
  })
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-jenkins-alb-sg"
  description = "Security group for Jenkins application load balancer."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.acm_certificate_arn == null ? [80] : [80, 443]

    content {
      description = ingress.value == 443 ? "Jenkins HTTPS web access" : "Jenkins HTTP test access"
      from_port   = ingress.value
      to_port     = ingress.value
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

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-jenkins-alb-sg"
  })
}

resource "aws_lb" "jenkins" {
  name               = "${var.project}-${var.environment}-jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-jenkins-alb"
  })
}

resource "aws_lb_target_group" "jenkins" {
  name     = "${var.project}-${var.environment}-jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/login"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-jenkins-tg"
  })
}

resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn == null ? 0 : 1

  load_balancer_arn = aws_lb.jenkins.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

resource "aws_lb_listener" "http" {
  count = var.acm_certificate_arn == null ? 1 : 0

  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = var.acm_certificate_arn == null ? 0 : 1

  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_instance" "jenkins" {
  count = var.instance_count

  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = element(var.subnet_ids, count.index)
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  user_data = templatefile("${path.module}/userdata.sh", {
    node_exporter_version = var.node_exporter_version
  })
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  user_data_replace_on_change = true

  depends_on = [aws_iam_role_policy_attachment.ssm]

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-jenkins-${count.index + 1}"
  })
}

resource "aws_lb_target_group_attachment" "jenkins" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins[count.index].id
  port             = 8080
}
