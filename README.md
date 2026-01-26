# tf-aws
Terraform for AWS

## uso8-blog RDS (PostgreSQL)

`service/` に uso8-blog-03 用の RDS (PostgreSQL) を定義しています。

### 使い方

```bash
cd service
terraform init
terraform plan -var="db_password=YOUR_SECURE_PASSWORD"
terraform apply -var="db_password=YOUR_SECURE_PASSWORD"
```

パスワードは `TF_VAR_db_password` や `-var-file` でも指定できます。未指定時は `variables.tf` の default（開発用）が使われます。

### 出力

- `rds_blog_endpoint` / `rds_blog_port` / `rds_blog_database` … 接続情報
- `rds_blog_jdbc_url` … Spring `spring.datasource.url` 用の JDBC URL

RDS は **private サブネット** にあり `publicly_accessible = false` のため、VPC 内（例: EC2, ECS）から接続してください。ローカルから接続する場合は SSM ポートフォワードや Bastion 等が必要です。

## uso8-blog ECS デプロイ用 IAM（GitHub Actions OIDC）

uso8-blog-03 を push したときに ECR push / ECS 更新するための IAM ロールです。

```bash
cd service
terraform apply \
  -var="github_org_repo_blog=YOUR_ORG/uso8-blog-03" \
  -var="ecs_container_image=ACCOUNT.dkr.ecr.ap-southeast-1.amazonaws.com/wiz-dev-app:latest"
```

`terraform output github_actions_blog_deploy_role_arn` の ARN を、uso8-blog-03 リポジトリの GitHub Secrets **AWS_ROLE_ARN** に登録してください。
