resource "aws_eip_association" "mongo" {
  instance_id   = aws_instance.mongo.id
  allocation_id = aws_eip.mongo.id
}
