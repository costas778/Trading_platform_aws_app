resource "aws_secretsmanager_secret" "secret" {
  for_each                = var.secrets
  name                    = "${var.project_name}/${var.environment}/${each.key}"
  description             = each.value.description
  kms_key_id             = var.kms_key_arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "secret_version" {
  for_each      = var.secrets
  secret_id     = aws_secretsmanager_secret.secret[each.key].id
  secret_string = jsonencode(each.value.value)
}

resource "aws_secretsmanager_secret_policy" "secret_policy" {
  for_each   = var.secrets
  secret_arn = aws_secretsmanager_secret.secret[each.key].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_role_arns
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}
