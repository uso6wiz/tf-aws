resource "aws_key_pair" "default" {
  key_name   = "wiz-dev-keypair"
  public_key = file("~/.ssh/wiz-dev.pub")

  tags = {
    Name    = "wiz-dev-keypair"
    Project = "tf-aws"
    Env     = "dev"
    Purpose = "ssh"
  }
}

output "keypair_name" {
  value = aws_key_pair.default.key_name
}
