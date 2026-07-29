locals { name = "${var.project}-${var.environment}-postgres" }

resource "random_id" "final_snapshot_suffix" {
  count       = !var.skip_final_snapshot && var.final_snapshot_identifier == null ? 1 : 0
  byte_length = 4

  keepers = {
    database_identifier = local.name
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-subnets"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${local.name}-subnets" })
}

resource "aws_security_group" "this" {
  name        = "${local.name}-sg"
  description = "PostgreSQL access from explicitly approved application security groups."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset(var.allowed_security_group_ids)
    content {
      description     = "PostgreSQL client"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
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

resource "aws_db_instance" "this" {
  identifier                   = local.name
  engine                       = "postgres"
  engine_version               = "16"
  instance_class               = var.instance_class
  allocated_storage            = var.allocated_storage
  max_allocated_storage        = var.allocated_storage * 4
  storage_type                 = "gp3"
  storage_encrypted            = true
  db_name                      = var.database_name
  username                     = var.master_username
  manage_master_user_password  = true
  db_subnet_group_name         = aws_db_subnet_group.this.name
  vpc_security_group_ids       = [aws_security_group.this.id]
  publicly_accessible          = false
  multi_az                     = var.multi_az
  backup_retention_period      = var.backup_retention_period
  backup_window                = "03:00-04:00"
  maintenance_window           = "sun:04:30-sun:05:30"
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true
  monitoring_interval          = 0
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.skip_final_snapshot
  delete_automated_backups     = true
  final_snapshot_identifier = var.skip_final_snapshot ? null : (
    var.final_snapshot_identifier != null
    ? var.final_snapshot_identifier
    : "${local.name}-final-${random_id.final_snapshot_suffix[0].hex}"
  )
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  tags                            = merge(var.tags, { Name = local.name })

  lifecycle {
    precondition {
      condition     = length(var.subnet_ids) >= 2
      error_message = "RDS requires at least two isolated database subnets."
    }
  }
}
