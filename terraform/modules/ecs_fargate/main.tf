resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-ecs-cluster"
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-cluster"
  })
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for the application load balancer."
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP for HTTPS redirection"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "ecs_service" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Security group for ECS Fargate tasks."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow HTTP traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
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
    Name = "${local.name_prefix}-ecs-service-sg"
  })
}

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-logs"
  })
}

data "aws_iam_policy_document" "ecs_task_execution" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_secretsmanager_secret" "datadog_api_key" {
  count                   = var.manage_datadog_secrets && var.datadog_api_key_secret_arn == null ? 1 : 0
  name                    = coalesce(var.datadog_api_key_secret_name, "${var.project}/${var.environment}/datadog/api-key")
  description             = "Datadog API key for ${var.project} ${var.environment}. Populate the value outside Terraform."
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-datadog-api-key"
  })
}

resource "aws_secretsmanager_secret" "datadog_app_key" {
  count                   = var.manage_datadog_secrets ? 1 : 0
  name                    = coalesce(var.datadog_app_key_secret_name, "${var.project}/${var.environment}/datadog/app-key")
  description             = "Datadog application key for ${var.project} ${var.environment}. Populate the value outside Terraform."
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-datadog-app-key"
  })
}

data "aws_secretsmanager_secret" "datadog_api_key" {
  count = !var.manage_datadog_secrets && var.datadog_api_key_secret_arn == null ? 1 : 0
  name  = coalesce(var.datadog_api_key_secret_name, "${var.project}/${var.environment}/datadog/api-key")
}

locals {
  name_prefix    = "${var.project}-${var.environment}"
  log_group_name = "/ecs/${local.name_prefix}"
  datadog_api_key_secret_arn = var.datadog_api_key_secret_arn != null ? var.datadog_api_key_secret_arn : try(
    aws_secretsmanager_secret.datadog_api_key[0].arn,
    data.aws_secretsmanager_secret.datadog_api_key[0].arn,
    null
  )
  datadog_app_key_secret_arn = try(aws_secretsmanager_secret.datadog_app_key[0].arn, null)
  datadog_logs_enabled       = var.enable_datadog && var.datadog_logs_enabled

  app_container = {
    name  = "app"
    image = var.container_image
    portMappings = [
      {
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }
    ]
    essential = true
    environment = var.enable_datadog ? [
      {
        name  = "DD_AGENT_HOST"
        value = "127.0.0.1"
      },
      {
        name  = "DD_ENV"
        value = var.environment
      },
      {
        name  = "DD_SERVICE"
        value = local.name_prefix
      }
    ] : []
    logConfiguration = local.datadog_logs_enabled ? {
      logDriver = "awsfirelens"
      options = {
        Name       = "datadog"
        Host       = "http-intake.logs.${var.datadog_site}"
        TLS        = "on"
        dd_service = local.name_prefix
        dd_source  = "ecs"
        dd_tags    = "env:${var.environment},project:${var.project}"
        provider   = "ecs"
      }
      secretOptions = [
        {
          name      = "apikey"
          valueFrom = local.datadog_api_key_secret_arn
        }
      ]
      } : {
      logDriver = "awslogs"
      options = {
        awslogs-group         = local.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
      secretOptions = []
    }
  }

  datadog_container = {
    name              = "datadog-agent"
    image             = var.datadog_agent_image
    essential         = false
    memoryReservation = 128
    environment = [
      {
        name  = "ECS_FARGATE"
        value = "true"
      },
      {
        name  = "DD_SITE"
        value = var.datadog_site
      },
      {
        name  = "DD_ENV"
        value = var.environment
      },
      {
        name  = "DD_SERVICE"
        value = local.name_prefix
      },
      {
        name  = "DD_APM_ENABLED"
        value = tostring(var.datadog_apm_enabled)
      },
      {
        name  = "DD_APM_NON_LOCAL_TRAFFIC"
        value = tostring(var.datadog_apm_enabled)
      }
    ]
    secrets = [
      {
        name      = "DD_API_KEY"
        valueFrom = local.datadog_api_key_secret_arn
      }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "agent health"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = local.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "datadog-agent"
      }
    }
  }

  datadog_log_router_container = {
    name              = "log-router"
    image             = var.datadog_firelens_image
    essential         = true
    memoryReservation = 64
    firelensConfiguration = {
      type = "fluentbit"
      options = {
        enable-ecs-log-metadata = "true"
      }
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = local.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "firelens"
      }
    }
  }

  container_definitions = jsonencode(concat(
    [local.app_container],
    var.enable_datadog ? [local.datadog_container] : [],
    local.datadog_logs_enabled ? [local.datadog_log_router_container] : []
  ))
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution.json
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-task-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "datadog_api_key" {
  count = var.enable_datadog ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.datadog_api_key_secret_arn]
  }
}

resource "aws_iam_role_policy" "datadog_api_key" {
  count  = var.enable_datadog ? 1 : 0
  name   = "${local.name_prefix}-datadog-api-key"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.datadog_api_key[0].json
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution.json
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-task-role"
  })
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = local.container_definitions

  depends_on = [aws_cloudwatch_log_group.app]

  lifecycle {
    precondition {
      condition     = !var.enable_datadog || local.datadog_api_key_secret_arn != null
      error_message = "Create the Datadog API-key secret or set datadog_api_key_secret_arn when enable_datadog is true."
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-task-def"
  })
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.https]
  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-service"
  })
}
