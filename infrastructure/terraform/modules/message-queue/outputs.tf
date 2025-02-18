output "id" {
  description = "ID of the MQ Broker"
  value       = aws_mq_broker.trading_mq.id
}

output "arn" {
  description = "ARN of the MQ Broker"
  value       = aws_mq_broker.trading_mq.arn
}

output "instances" {
  description = "List of broker instances"
  value       = aws_mq_broker.trading_mq.instances
}

output "primary_endpoint" {
  description = "Primary endpoint of the MQ broker"
  value       = [for instance in aws_mq_broker.trading_mq.instances : instance.endpoints][0]
}

output "console_url" {
  description = "The URL of the broker's web console"
  value       = aws_mq_broker.trading_mq.instances[0].console_url
}
