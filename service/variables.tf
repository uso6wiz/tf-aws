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
