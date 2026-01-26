# -----------------------------------------------------------------------------
# Bastion EC2（Amazon Linux 2023 / 小さいインスタンス）
# パブリックサブネット配置。SSH で踏み台→ VPC 内 RDS 等へ接続用。
# -----------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "wiz-dev-bastion-sg"
  description = "Bastion EC2 (SSH)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wiz-dev-bastion-sg"
    Project = "tf-aws"
    Env     = "dev"
    Purpose = "bastion"
  }
}

resource "aws_launch_template" "bastion" {
  name_prefix   = "wiz-dev-bastion-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.default.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }

  vpc_security_group_ids = [aws_security_group.bastion.id]

  metadata_options {
    http_tokens = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "wiz-dev-bastion"
      Project = "tf-aws"
      Env     = "dev"
      Role    = "bastion"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Project = "tf-aws"
      Env     = "dev"
      Role    = "bastion"
    }
  }
}

resource "aws_instance" "bastion" {
  subnet_id = module.vpc.public_subnets[0]

  launch_template {
    id      = aws_launch_template.bastion.id
    version = "$Latest"
  }

  tags = {
    Name    = "wiz-dev-bastion"
    Project = "tf-aws"
    Env     = "dev"
    Role    = "bastion"
  }
}

resource "aws_eip" "bastion" {
  domain = "vpc"
  tags = {
    Name    = "wiz-dev-bastion-eip"
    Project = "tf-aws"
    Env     = "dev"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

output "bastion_public_ip" {
  value       = aws_eip.bastion.public_ip
  description = "Bastion のパブリック IP（ssh -i keys/wiz-dev ec2-user@<this>）"
}

output "bastion_instance_id" {
  value       = aws_instance.bastion.id
  description = "Bastion の Instance ID（SSM 接続用）"
}
