resource "aws_eip" "mongo" {
  domain = "vpc"

  tags = {
    Name    = "wiz-dev-mongo-eip"
    Project = "tf-aws"
    Env     = "dev"
  }
}

