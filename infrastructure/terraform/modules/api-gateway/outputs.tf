output "id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.trading_api.id
}

output "arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.trading_api.arn
}

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_api_gateway_stage.trading_api.invoke_url
}

output "execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.trading_api.execution_arn
}

output "stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.trading_api.stage_name
}

output "root_resource_id" {
  description = "Root resource ID of the REST API"
  value       = aws_api_gateway_rest_api.trading_api.root_resource_id
}

output "stage_arn" {
  description = "ARN of the API Gateway stage"
  value       = aws_api_gateway_stage.trading_api.arn
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for API Gateway"
  value       = var.logging_level != "OFF" ? aws_cloudwatch_log_group.api_gateway[0].arn : null
}
