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
