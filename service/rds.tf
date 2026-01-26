# -----------------------------------------------------------------------------
# uso8-blog-03 用 PostgreSQL RDS
# application.properties と整合: blogdb / uso8
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "blog" {
  name       = "wiz-dev-blog-db-subnet"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name    = "wiz-dev-blog-db-subnet"
    Project = "tf-aws"
    Env     = "dev"
  }
}

resource "aws_security_group" "rds_blog" {
  name        = "wiz-dev-rds-blog-sg"
  description = "PostgreSQL RDS for uso8-blog (VPC only)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wiz-dev-rds-blog-sg"
    Project = "tf-aws"
    Env     = "dev"
  }
}

resource "aws_db_instance" "blog" {
  identifier     = "wiz-dev-blog-db"
  engine         = "postgres"
  engine_version = "15"

  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "blogdb"
  username = "uso8"
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.blog.name
  vpc_security_group_ids = [aws_security_group.rds_blog.id]
  multi_az               = false
  publicly_accessible    = false

  skip_final_snapshot       = true
  deletion_protection       = false
  backup_retention_period   = 7
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"

  tags = {
    Name    = "wiz-dev-blog-db"
    Project = "tf-aws"
    Env     = "dev"
    App     = "uso8-blog"
  }
}

# -----------------------------------------------------------------------------
# Outputs（application.properties や接続確認用）
# -----------------------------------------------------------------------------
output "rds_blog_endpoint" {
  description = "RDS PostgreSQL endpoint (host only, no port)"
  value       = aws_db_instance.blog.address
}

output "rds_blog_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.blog.port
}

output "rds_blog_database" {
  description = "RDS database name"
  value       = aws_db_instance.blog.db_name
}

output "rds_blog_jdbc_url" {
  description = "JDBC URL for Spring Datasource (VPC内から接続する場合の例)"
  value       = "jdbc:postgresql://${aws_db_instance.blog.address}:${aws_db_instance.blog.port}/${aws_db_instance.blog.db_name}"
}
