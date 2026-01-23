resource "aws_security_group" "ec2" {
  name        = "wiz-dev-ec2-sg"
  description = "Common EC2 security group (dev / validation)"
  vpc_id      = module.vpc.vpc_id

  # SSH（検証用：外部から）
  ingress {
    description = "SSH from anywhere (dev only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MongoDB（検証用：VPC内から）
  ingress {
    description = "MongoDB from VPC"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  # すべて外向き通信OK（SSM / apt / curl 等）
  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wiz-dev-ec2-sg"
    Project = "tf-aws"
    Env     = "dev"
    Purpose = "validation"
  }
}

