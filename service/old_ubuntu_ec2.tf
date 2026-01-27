resource "aws_instance" "old_ubuntu" {
  subnet_id = module.vpc.public_subnets[0]

  launch_template {
    id      = aws_launch_template.old_ubuntu.id
    version = "$Latest"
  }

  tags = {
    Name    = "wiz-dev-old-ubuntu"
    Project = "tf-aws"
    Env     = "dev"
    Role    = "old_ubuntu"
  }
}
