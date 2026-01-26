# -----------------------------------------------------------------------------
# ECR（コンテナイメージ用）
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = "wiz-dev-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "wiz-dev-app"
    Project = "tf-aws"
    Env     = "dev"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "ECR repository URL (push: docker push <url>:tag)"
}
