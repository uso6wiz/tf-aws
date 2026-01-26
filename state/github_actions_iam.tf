# -----------------------------------------------------------------------------
# GitHub Actions から Terraform apply するための IAM ロール（OIDC）
# aws-actions/configure-aws-credentials で AssumeRoleWithWebIdentity に使用
# -----------------------------------------------------------------------------

data "tls_certificate" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_oidc.certificates[0].sha1_fingerprint]

  tags = merge(local.tags, { Name = "github-actions-oidc" })
}

locals {
  # Trust policy の sub 条件: environment 指定時は environment、それ以外は ref
  github_oidc_sub = var.github_environment != null ? "repo:${var.github_org_repo}:environment:${var.github_environment}" : (
    var.github_branch == "*" ? "repo:${var.github_org_repo}:*" : "repo:${var.github_org_repo}:ref:refs/heads/${var.github_branch}"
  )
}

resource "aws_iam_role" "github_actions_terraform" {
  name        = "github-actions-terraform"
  description = "AssumeRoleWithWebIdentity for GitHub Actions (Terraform apply)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_oidc_sub
          }
        }
      }
    ]
  })

  tags = merge(local.tags, { Name = "github-actions-terraform" })
}

# -----------------------------------------------------------------------------
# Terraform バックエンド用: S3 state + DynamoDB lock
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "terraform_backend" {
  name = "terraform-backend"
  role = aws_iam_role.github_actions_terraform.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3State"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
      },
      {
        Sid    = "DynamoDBLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem",
          "dynamodb:DescribeTable"
        ]
        Resource = aws_dynamodb_table.tflock.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Terraform apply 用: service/* が作成するリソース（VPC, EC2, RDS, IAM 等）の操作
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "terraform_apply" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# Outputs（GitHub Actions ワークフローで使用）
# -----------------------------------------------------------------------------
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_terraform.arn
  description = "ARN of IAM role for GitHub Actions. Use as AWS_ROLE_ARN with configure-aws-credentials."
}

output "github_actions_role_name" {
  value       = aws_iam_role.github_actions_terraform.name
  description = "IAM role name for GitHub Actions"
}
