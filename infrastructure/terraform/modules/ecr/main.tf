resource "aws_ecr_repository" "repository" {
  for_each             = toset(var.repository_names)
  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key        = var.kms_key_arn
  }

  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = var.environment
  }
}

resource "aws_ecr_lifecycle_policy" "policy" {
  for_each   = aws_ecr_repository.repository
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 30
      }
      action = {
        type = "expire"
      }
    }]
  })
}
