resource "aws_instance" "mongo" {
  subnet_id = module.vpc.public_subnets[0]

  launch_template {
    id      = aws_launch_template.mongo.id
    version = "$Latest"
  }

  tags = {
    Name    = "wiz-dev-mongo"
    Project = "tf-aws"
    Env     = "dev"
    Role    = "mongo"
  }
}
