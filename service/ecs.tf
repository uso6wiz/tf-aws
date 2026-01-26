# -----------------------------------------------------------------------------
# ECS Fargate 最小構成（ALB + 1 タスク）
# コンテナイメージは var.ecs_container_image（未指定時はサンプルアプリ）
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

locals {
  ecs_name = "wiz-dev-ecs"
  app_port = var.ecs_container_port
}

# -----------------------------------------------------------------------------
# ECS Cluster
# 注意: Fargate ではサービスリンクロール（AWSServiceRoleForECS）が自動使用される。
# iam_role を指定するとエラーになるため、指定しない。
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = local.ecs_name
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
  tags = {
    Name    = local.ecs_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

# -----------------------------------------------------------------------------
# Task Execution Role（ECR 取得・CloudWatch Logs）
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution" {
  name = "wiz-dev-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "wiz-dev-ecs-execution", Project = "tf-aws", Env = "dev" }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# -----------------------------------------------------------------------------
# ALB + Target Group + Listener
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs_alb" {
  name        = "wiz-dev-ecs-alb-sg"
  description = "ALB for ECS (HTTP)"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wiz-dev-ecs-alb-sg", Project = "tf-aws", Env = "dev" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "wiz-dev-ecs-tasks-sg"
  description = "ECS Fargate tasks (from ALB only)"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = local.app_port
    to_port         = local.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wiz-dev-ecs-tasks-sg", Project = "tf-aws", Env = "dev" }
}

resource "aws_lb" "ecs" {
  name               = "wiz-dev-ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_alb.id]
  subnets            = module.vpc.public_subnets
  tags               = { Name = "wiz-dev-ecs-alb", Project = "tf-aws", Env = "dev" }
}

resource "aws_lb_target_group" "ecs" {
  name        = "wiz-dev-ecs-tg"
  port        = local.app_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    path                = "/login"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
  tags = { Name = "wiz-dev-ecs-tg", Project = "tf-aws", Env = "dev" }
}

resource "aws_lb_listener" "ecs" {
  load_balancer_arn = aws_lb.ecs.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}

# -----------------------------------------------------------------------------
# Task Definition + Service
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "wiz-dev-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.ecs_container_image
    essential = true
    portMappings = [{
      containerPort = local.app_port
      protocol      = "tcp"
    }]
    environment = [
      { name = "SPRING_PROFILES_ACTIVE", value = "production" },
      { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${aws_db_instance.blog.address}:${aws_db_instance.blog.port}/${aws_db_instance.blog.db_name}" },
      { name = "SPRING_DATASOURCE_USERNAME", value = aws_db_instance.blog.username },
      { name = "SPRING_DATASOURCE_PASSWORD", value = var.db_password }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
  tags = { Name = "wiz-dev-app", Project = "tf-aws", Env = "dev" }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/wiz-dev-app"
  retention_in_days = 7
  tags              = { Name = "wiz-dev-ecs-logs", Project = "tf-aws", Env = "dev" }
}

resource "aws_ecs_service" "app" {
  name            = "wiz-dev-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "app"
    container_port   = local.app_port
  }
  tags = { Name = "wiz-dev-app", Project = "tf-aws", Env = "dev" }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "ecs_cluster_name" {
  value       = aws_ecs_cluster.main.name
  description = "ECS cluster name"
}

output "ecs_service_name" {
  value       = aws_ecs_service.app.name
  description = "ECS service name"
}

output "ecs_alb_dns_name" {
  value       = aws_lb.ecs.dns_name
  description = "ALB DNS (http://<this>/ でアクセス)"
}

output "ecs_alb_zone_id" {
  value       = aws_lb.ecs.zone_id
  description = "ALB zone ID (Route53 エイリアス用)"
}
