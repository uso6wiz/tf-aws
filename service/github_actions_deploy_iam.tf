# -----------------------------------------------------------------------------
# uso8-blog-03 の push → ECR push / ECS デプロイ用 IAM ロール（OIDC）
# github_org_repo_blog が空のときは作成しない
# -----------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  blog_oidc_sub = var.github_org_repo_blog != "" ? (
    var.github_branch_blog == "*" ? "repo:${var.github_org_repo_blog}:*" : "repo:${var.github_org_repo_blog}:ref:refs/heads/${var.github_branch_blog}"
  ) : ""
}

resource "aws_iam_role" "github_actions_blog_deploy" {
  count = var.github_org_repo_blog != "" ? 1 : 0

  name        = "github-actions-blog-deploy"
  description = "AssumeRoleWithWebIdentity for uso8-blog-03 deploy (ECR push, ECS update)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.blog_oidc_sub
        }
      }
    }]
  })
  tags = { Name = "github-actions-blog-deploy", Project = "tf-aws", Env = "dev" }
}

resource "aws_iam_role_policy" "github_actions_blog_deploy" {
  count = var.github_org_repo_blog != "" ? 1 : 0

  name = "ecr-ecs-deploy"
  role = aws_iam_role.github_actions_blog_deploy[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid    = "ECS"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:UpdateService"
        ]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_blog_deploy_role_arn" {
  value       = var.github_org_repo_blog != "" ? aws_iam_role.github_actions_blog_deploy[0].arn : null
  description = "uso8-blog デプロイ用 IAM ロール ARN。GitHub Secrets に AWS_ROLE_ARN として登録する。"
}
