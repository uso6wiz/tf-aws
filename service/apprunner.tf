# -----------------------------------------------------------------------------
# AWS App Runner で uso8-blog-03 コンテナを実行
# ECR リポジトリからイメージを取得し、RDS PostgreSQL に接続
# -----------------------------------------------------------------------------
# 注意: data "aws_region" "current" は ecs.tf で定義済み
# 注意: data "aws_caller_identity" "me" は main.tf で定義済み

locals {
  apprunner_service_name       = "wiz-dev-blog-apprunner"
  apprunner_vpc_connector_name = "wiz-dev-blog-vpc-connector"
}

# -----------------------------------------------------------------------------
# App Runner インスタンスロール（コンテナ実行用）
# -----------------------------------------------------------------------------
resource "aws_iam_role" "apprunner_instance" {
  name = "${local.apprunner_service_name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "tasks.apprunner.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${local.apprunner_service_name}-instance-role"
    Project = "tf-aws"
    Env     = "dev"
  }
}

# App Runner インスタンスロールに CloudWatch Logs への書き込み権限を付与
resource "aws_iam_role_policy" "apprunner_instance_logs" {
  name = "${local.apprunner_service_name}-instance-logs"
  role = aws_iam_role.apprunner_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:log-group:/aws/apprunner/${local.apprunner_service_name}/*"
    }]
  })
}

# -----------------------------------------------------------------------------
# App Runner アクセスロール（ECR アクセス用）
# -----------------------------------------------------------------------------
resource "aws_iam_role" "apprunner_access" {
  name = "${local.apprunner_service_name}-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "build.apprunner.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${local.apprunner_service_name}-access-role"
    Project = "tf-aws"
    Env     = "dev"
  }
}

# ECR からイメージを取得するための権限
resource "aws_iam_role_policy" "apprunner_access_ecr" {
  name = "${local.apprunner_service_name}-access-ecr"
  role = aws_iam_role.apprunner_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# VPC Connector（RDS への接続用）
# -----------------------------------------------------------------------------
# App Runner から VPC 内の RDS に接続するための VPC Connector
resource "aws_apprunner_vpc_connector" "blog" {
  vpc_connector_name = local.apprunner_vpc_connector_name
  subnets            = module.vpc.private_subnets
  security_groups    = [aws_security_group.apprunner_vpc_connector.id]

  tags = {
    Name    = local.apprunner_vpc_connector_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# VPC Connector 用のセキュリティグループ
# RDS のセキュリティグループから App Runner からのアクセスを許可する必要がある
resource "aws_security_group" "apprunner_vpc_connector" {
  name        = "wiz-dev-apprunner-vpc-connector-sg"
  description = "Security group for App Runner VPC Connector"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wiz-dev-apprunner-vpc-connector-sg"
    Project = "tf-aws"
    Env     = "dev"
  }
}

# RDS のセキュリティグループに App Runner VPC Connector からのアクセスを許可
resource "aws_security_group_rule" "rds_from_apprunner" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.apprunner_vpc_connector.id
  security_group_id        = aws_security_group.rds_blog.id
  description              = "PostgreSQL from App Runner VPC Connector"
}

# -----------------------------------------------------------------------------
# App Runner Service
# -----------------------------------------------------------------------------
resource "aws_apprunner_service" "blog" {
  service_name = local.apprunner_service_name

  source_configuration {
    image_repository {
      image_identifier      = "${aws_ecr_repository.app.repository_url}:latest"
      image_repository_type = "ECR"
      image_configuration {
        port = "8080"
        runtime_environment_variables = {
          SPRING_PROFILES_ACTIVE     = "production"
          SPRING_DATASOURCE_URL      = "jdbc:postgresql://${aws_db_instance.blog.address}:${aws_db_instance.blog.port}/${aws_db_instance.blog.db_name}"
          SPRING_DATASOURCE_USERNAME = aws_db_instance.blog.username
          SPRING_DATASOURCE_PASSWORD = var.db_password
        }
      }
    }
    access_role_arn          = aws_iam_role.apprunner_access.arn
    auto_deployments_enabled = false
  }

  instance_configuration {
    instance_role_arn = aws_iam_role.apprunner_instance.arn
    cpu               = "1 vCPU"
    memory            = "2 GB"
  }

  network_configuration {
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.blog.arn
    }
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/login"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }

  tags = {
    Name    = local.apprunner_service_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for App Runner
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "apprunner" {
  name              = "/aws/apprunner/${local.apprunner_service_name}"
  retention_in_days = 7

  tags = {
    Name    = "${local.apprunner_service_name}-logs"
    Project = "tf-aws"
    Env     = "dev"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "apprunner_service_id" {
  value       = aws_apprunner_service.blog.service_id
  description = "App Runner service ID"
}

output "apprunner_service_arn" {
  value       = aws_apprunner_service.blog.arn
  description = "App Runner service ARN"
}

output "apprunner_service_url" {
  value       = aws_apprunner_service.blog.service_url
  description = "App Runner service URL (use this to access the application)"
}

output "apprunner_vpc_connector_arn" {
  value       = aws_apprunner_vpc_connector.blog.arn
  description = "App Runner VPC Connector ARN"
}
