# -----------------------------------------------------------------------------
# EKS（マネージドノードグループ約2台 + 既存 ECR からの pull）
# ノード IAM に AmazonEC2ContainerRegistryReadOnly が付与され、同アカウントの ECR を pull 可能。
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

locals {
  eks_cluster_name = var.eks_cluster_name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = local.eks_cluster_name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Terraform 実行 IAM をクラスタ管理者として登録（既定 false だと kubectl が 401 になる）
  enable_cluster_creator_admin_permissions = true

  # PC の kubectl が Terraform と別 IAM（別ユーザー / SSO 等）のとき、その ARN を追加
  access_entries = {
    for idx, arn in var.eks_kubectl_admin_principal_arns : "kubectl_admin_${idx}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = var.eks_node_instance_types
    capacity_type  = "ON_DEMAND"
  }

  eks_managed_node_groups = {
    main = {
      name            = "main"
      use_name_prefix = true

      min_size     = var.eks_node_min_size
      max_size     = var.eks_node_max_size
      desired_size = var.eks_node_desired_size
    }
  }

  tags = {
    Name    = local.eks_cluster_name
    Project = "tf-aws"
    Env     = "dev"
  }
}

output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "kubectl 用クラスタ名"
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Kubernetes API エンドポイント"
}

output "eks_configure_kubectl" {
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks.cluster_name}"
  description = "kubeconfig を書き込むコマンド"
}

output "eks_sample_deploy_hint" {
  value       = "ECR にイメージを push 後: kubectl create deployment demo --image=${aws_ecr_repository.app.repository_url}:latest --replicas=2"
  description = "ECR イメージをそのまま使う最小デプロイ例（Service は別途 kubectl expose 等）"
}
