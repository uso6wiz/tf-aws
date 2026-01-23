terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1" # Singapore
}

data "aws_caller_identity" "me" {}

locals {
  region_short   = "apse1"
  tfstate_bucket = "tfstate-${data.aws_caller_identity.me.account_id}-${local.region_short}"
  lock_table     = "terraform-lock"
  tags = {
    Project = "tf-aws"
    Purpose = "terraform-state"
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.tfstate_bucket
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tflock" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  tags         = local.tags

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "tfstate_bucket" {
  value       = aws_s3_bucket.tfstate.bucket
  description = "S3 bucket name for Terraform remote state"
}

output "lock_table" {
  value       = aws_dynamodb_table.tflock.name
  description = "DynamoDB table name for Terraform state locking"
}

