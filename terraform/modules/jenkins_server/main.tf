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
  #checkov:skip=CKV_AWS_274:AdministratorAccess was explicitly requested for the Jenkins Terraform deployment role.
  count      = var.attach_admin_policy ? 1 : 0
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "ecr" {
  count = length(var.ecr_repository_arns) > 0 ? 1 : 0
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
      "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr" {
  count  = length(var.ecr_repository_arns) > 0 ? 1 : 0
  name   = "${var.project}-${var.environment}-jenkins-ecr"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.ecr[0].json
}

data "aws_iam_policy_document" "terraform_state" {
  count = var.terraform_state_bucket_name == null ? 0 : 1

  statement {
    sid       = "ReadStateBucketMetadata"
    actions   = ["s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.terraform_state_bucket_name}"]
  }

  statement {
    sid       = "ListApprovedStateKeys"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.terraform_state_bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = distinct(concat(
        var.terraform_state_read_only_keys,
        var.terraform_state_read_write_keys
      ))
    }
  }

  statement {
    sid     = "ReadApprovedStates"
    actions = ["s3:GetObject"]
    resources = [
      for key in distinct(concat(
        var.terraform_state_read_only_keys,
        var.terraform_state_read_write_keys
      )) : "arn:aws:s3:::${var.terraform_state_bucket_name}/${key}"
    ]
  }

  statement {
    sid = "WriteDeploymentStates"
    actions = [
      "s3:DeleteObject",
      "s3:PutObject"
    ]
    resources = [
      for key in var.terraform_state_read_write_keys :
      "arn:aws:s3:::${var.terraform_state_bucket_name}/${key}"
    ]
  }

  dynamic "statement" {
    for_each = var.terraform_state_lock_table_name == null ? [] : [var.terraform_state_lock_table_name]

    content {
      sid = "ManageTerraformStateLocks"
      actions = [
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem"
      ]
      resources = [
        "arn:aws:dynamodb:${var.aws_region}:*:table/${statement.value}"
      ]
    }
  }
}

resource "aws_iam_role_policy" "terraform_state" {
  count  = var.terraform_state_bucket_name == null ? 0 : 1
  name   = "${var.project}-${var.environment}-jenkins-terraform-state"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.terraform_state[0].json
}

data "aws_iam_policy_document" "pipeline_dns" {
  count = length(var.route53_hosted_zone_arns) > 0 ? 1 : 0

  statement {
    sid = "DiscoverHostedZones"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadDnsChangeStatus"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid = "ManageApprovedHostedZones"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets"
    ]
    resources = var.route53_hosted_zone_arns
  }
}

data "aws_iam_policy_document" "pipeline_certificates" {
  count = length(var.route53_hosted_zone_arns) > 0 ? 1 : 0

  # RequestCertificate does not support resource-level permissions because the
  # certificate ARN does not exist until ACM accepts the request.
  #checkov:skip=CKV_AWS_111:ACM RequestCertificate requires Resource "*" at certificate creation time.
  #checkov:skip=CKV_AWS_356:ACM RequestCertificate has no resource ARN to constrain before creation.
  statement {
    sid       = "RequestPipelineCertificates"
    actions   = ["acm:RequestCertificate"]
    resources = ["*"]
  }

  statement {
    sid = "ManageCreatedPipelineCertificates"
    actions = [
      "acm:AddTagsToCertificate",
      "acm:DeleteCertificate",
      "acm:DescribeCertificate",
      "acm:ListTagsForCertificate"
    ]
    resources = ["arn:aws:acm:${var.aws_region}:*:certificate/*"]
  }
}

resource "aws_iam_role_policy" "pipeline_dns" {
  count  = length(var.route53_hosted_zone_arns) > 0 ? 1 : 0
  name   = "${var.project}-${var.environment}-jenkins-pipeline-dns"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.pipeline_dns[0].json
}

resource "aws_iam_role_policy" "pipeline_certificates" {
  count  = length(var.route53_hosted_zone_arns) > 0 ? 1 : 0
  name   = "${var.project}-${var.environment}-jenkins-pipeline-certificates"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.pipeline_certificates[0].json
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project}-${var.environment}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

resource "aws_security_group" "jenkins" {
  name        = "${var.project}-${var.environment}-jenkins-sg"
  description = "Security group for Jenkins server."
  vpc_id      = var.vpc_id

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

resource "aws_vpc_security_group_ingress_rule" "alb_to_jenkins" {
  security_group_id            = aws_security_group.jenkins.id
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "Jenkins web UI from ALB"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  tags                         = var.tags
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-jenkins-alb-sg"
  description = "Security group for Jenkins application load balancer."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.enable_https ? [80, 443] : [80]

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
  subnets            = var.load_balancer_subnet_ids

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
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.jenkins.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  lifecycle {
    precondition {
      condition     = var.acm_certificate_arn != null
      error_message = "acm_certificate_arn must be provided when enable_https is true."
    }
  }
}

resource "aws_lb_listener" "http" {
  count = var.enable_https ? 0 : 1

  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = var.enable_https ? 1 : 0

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

resource "aws_security_group" "efs" {
  name        = "${var.project}-${var.environment}-jenkins-efs-sg"
  description = "NFS access to Jenkins home from the controller Auto Scaling Group."
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from Jenkins controllers"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-jenkins-efs-sg"
  })
}

resource "aws_efs_file_system" "jenkins_home" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-jenkins-home"
  })
}

resource "aws_efs_backup_policy" "jenkins_home" {
  file_system_id = aws_efs_file_system.jenkins_home.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_mount_target" "jenkins_home" {
  # Subnet IDs can be unknown during the first plan because the VPC and
  # Jenkins modules are applied together. Use the known list indexes as the
  # resource keys and keep the apply-time subnet IDs in the map values.
  for_each = {
    for index, subnet_id in var.subnet_ids : tostring(index) => subnet_id
  }

  file_system_id  = aws_efs_file_system.jenkins_home.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_launch_template" "jenkins" {
  name_prefix   = "${var.project}-${var.environment}-jenkins-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    aws_region            = var.aws_region
    checkov_version       = var.checkov_version
    efs_file_system_id    = aws_efs_file_system.jenkins_home.id
    node_exporter_version = var.node_exporter_version
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.jenkins.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.jenkins.id]
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-jenkins"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-jenkins-root"
    })
  }

  update_default_version = true
}

resource "aws_autoscaling_group" "jenkins" {
  name                      = "${var.project}-${var.environment}-jenkins-asg"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  health_check_type         = "ELB"
  health_check_grace_period = 900
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = [aws_lb_target_group.jenkins.arn]

  launch_template {
    id      = aws_launch_template.jenkins.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      instance_warmup        = 900
      min_healthy_percentage = 0
    }

    triggers = ["tag"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-jenkins"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_efs_mount_target.jenkins_home,
    aws_iam_role_policy_attachment.ssm
  ]
}

resource "aws_ssm_association" "build_toolchain" {
  name             = "AWS-RunShellScript"
  association_name = "${var.project}-${var.environment}-jenkins-build-toolchain"

  targets {
    key    = "tag:Name"
    values = ["${var.project}-${var.environment}-jenkins"]
  }

  parameters = {
    commands = join("\n", [
      "set -euxo pipefail",
      "for attempt in $(seq 1 120); do test -f /var/lib/cloud/instance/boot-finished && break; sleep 15; done",
      "test -f /var/lib/cloud/instance/boot-finished",
      "dnf install -y java-21-openjdk maven podman jq awscli dnf-plugins-core python3 python3-pip python3.11 python3.11-pip",
      "JAVA21_BIN=$(find /usr/lib/jvm -path '*/java-21-openjdk*/bin/java' -type f | head -n 1)",
      "test -n \"$JAVA21_BIN\"",
      "alternatives --set java \"$JAVA21_BIN\"",
      "python3.11 -m venv /opt/checkov-py311",
      "/opt/checkov-py311/bin/pip install --upgrade pip",
      "/opt/checkov-py311/bin/pip install --upgrade checkov==${var.checkov_version}",
      "ln -sf /opt/checkov-py311/bin/checkov /usr/local/bin/checkov",
      "checkov --version",
      "dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo",
      "dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "systemctl enable --now docker",
      "usermod -aG docker jenkins",
      "usermod -aG docker ec2-user",
      "systemctl restart jenkins"
    ])
  }

  depends_on = [
    aws_autoscaling_group.jenkins,
    aws_iam_role_policy_attachment.ssm
  ]
}
