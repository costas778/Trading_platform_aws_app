resource "aws_kms_key" "main" {
  description             = "${var.project_name} ${var.environment} encryption key"
  deletion_window_in_days = 7
  enable_key_rotation    = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}
