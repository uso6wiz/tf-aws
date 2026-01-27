resource "aws_eip" "old_ubuntu" {
  domain = "vpc"

  tags = {
    Name    = "wiz-dev-old-ubuntu-eip"
    Project = "tf-aws"
    Env     = "dev"
  }
}

