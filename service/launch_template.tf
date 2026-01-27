resource "aws_launch_template" "old_ubuntu" {
  name_prefix   = "wiz-dev-old-ubuntu-"
  image_id      = "ami-0950bf7d28f290092"
  instance_type = "t3.small"
  key_name      = aws_key_pair.default.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  metadata_options {
    http_tokens = "required"
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "wiz-dev-old-ubuntu"
      Project = "tf-aws"
      Env     = "dev"
      Role    = "old_ubuntu"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Project = "tf-aws"
      Env     = "dev"
      Role    = "old_ubuntu"
    }
  }
}

