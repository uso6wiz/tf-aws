# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------
variable "eks_cluster_name" {
  description = "EKS クラスタ名（VPC サブネットの kubernetes.io/cluster/* タグにも使用）"
  type        = string
  default     = "wiz-dev-eks"
}

variable "eks_cluster_version" {
  description = "EKS コントロールプレーンの Kubernetes バージョン"
  type        = string
  default     = "1.31"
}

variable "eks_node_desired_size" {
  description = "マネージドノードグループの desired 台数（約2台想定）"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "マネージドノードグループの最小台数"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "マネージドノードグループの最大台数"
  type        = number
  default     = 4
}

variable "eks_node_instance_types" {
  description = "ワーカーノードのインスタンスタイプ"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_kubectl_admin_principal_arns" {
  description = "kubectl 用にクラスタ管理者を付与する IAM の ARN（Terraform と別プリンシパルのとき指定。例: arn:aws:iam::123456789012:user/alice）"
  type        = list(string)
  default     = []
}

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
  default     = "uso6wiz/uso8-blog-03"
}

variable "github_branch_blog" {
  description = "uso8-blog でデプロイを許可するブランチ（現状 Trust は repo:* で全 ref 許可）"
  type        = string
  default     = "main"
}
