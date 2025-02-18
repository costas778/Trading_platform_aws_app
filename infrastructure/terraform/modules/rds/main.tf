resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-db"

  engine         = "postgres"
  engine_version = "13.18"

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  db_name  = var.database_name
  username = var.database_username
  password = var.database_password

  vpc_security_group_ids = [var.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  multi_az               = var.environment == "prod" ? true : false
  publicly_accessible    = false
  skip_final_snapshot    = var.environment != "prod"
  deletion_protection    = var.environment == "prod"

  backup_retention_period = var.environment == "prod" ? 30 : 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = var.monitoring_role_arn

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  auto_minor_version_upgrade = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-db"
      Environment = var.environment
    }
  )
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}"
      Environment = var.environment
    }
  )
}
