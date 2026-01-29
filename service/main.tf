terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "tfstate-127214177449-apse1" #Change Real Name
    key            = "service/dev/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_caller_identity" "me" {}

output "whoami" {
  value = data.aws_caller_identity.me.arn
}

