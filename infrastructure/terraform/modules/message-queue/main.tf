resource "aws_mq_broker" "trading_mq" {
  broker_name = var.name

  engine_type        = "RabbitMQ"
  engine_version     = "3.9.16"
  host_instance_type = "mq.t3.micro"

  user {
    username = var.mq_username
    password = var.mq_password
  }

  security_groups = var.security_group_ids
  subnet_ids      = var.subnet_ids

  tags = var.tags
}
