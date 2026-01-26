variable "db_password" {
  description = "Master password for RDS PostgreSQL (uso8-blog). Override via TF_VAR_db_password or -var."
  type        = string
  sensitive   = true
  default     = "password" # 開発用。本番では必ず上書きすること。
}

variable "db_instance_class" {
  description = "RDS instance class for blog DB"
  type        = string
  default     = "db.t3.micro"
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------
variable "ecs_container_image" {
  description = "ECS task のコンテナイメージ。ECR 利用時は <account>.dkr.ecr.<region>.amazonaws.com/wiz-dev-app:latest 等"
  type        = string
  default     = "public.ecr.aws/ecs-sample/amazon-ecs-sample:latest"
}

variable "ecs_container_port" {
  description = "ECS コンテナのリスニングポート（uso8-blog は 8080）"
  type        = number
  default     = 8080
}

variable "ecs_desired_count" {
  description = "ECS service の desired count"
  type        = number
  default     = 1
}

# uso8-blog デプロイ用 GitHub Actions OIDC ロール
variable "github_org_repo_blog" {
  description = "uso8-blog の GitHub org/repo (e.g. myorg/uso8-blog-03)。デプロイ用 OIDC の trust に使用。"
  type        = string
  default     = ""
}

variable "github_branch_blog" {
  description = "uso8-blog でデプロイを許可するブランチ"
  type        = string
  default     = "main"
}
