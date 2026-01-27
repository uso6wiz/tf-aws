resource "aws_eip_association" "old_ubuntu" {
  instance_id   = aws_instance.old_ubuntu.id
  allocation_id = aws_eip.old_ubuntu.id
}
