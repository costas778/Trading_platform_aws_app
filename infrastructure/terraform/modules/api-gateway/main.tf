# Create IAM role for API Gateway CloudWatch logging
resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.project_name}-${var.environment}-api-gateway-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach CloudWatch policy to the role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Update API Gateway account settings with the CloudWatch role ARN
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

# Rest of your existing resources...
resource "aws_api_gateway_rest_api" "trading_api" {
  name        = "${var.project_name}-${var.environment}"
  description = var.description

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = var.tags
}

# Add a dummy root method to allow deployment
resource "aws_api_gateway_method" "dummy" {
  rest_api_id   = aws_api_gateway_rest_api.trading_api.id
  resource_id   = aws_api_gateway_rest_api.trading_api.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "dummy" {
  rest_api_id = aws_api_gateway_rest_api.trading_api.id
  resource_id = aws_api_gateway_rest_api.trading_api.root_resource_id
  http_method = aws_api_gateway_method.dummy.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "dummy" {
  rest_api_id = aws_api_gateway_rest_api.trading_api.id
  resource_id = aws_api_gateway_rest_api.trading_api.root_resource_id
  http_method = aws_api_gateway_method.dummy.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "dummy" {
  rest_api_id = aws_api_gateway_rest_api.trading_api.id
  resource_id = aws_api_gateway_rest_api.trading_api.root_resource_id
  http_method = aws_api_gateway_method.dummy.http_method
  status_code = aws_api_gateway_method_response.dummy.status_code

  response_templates = {
    "application/json" = jsonencode({
      message = "API Gateway is ready"
    })
  }
}

resource "aws_api_gateway_deployment" "trading_api" {
  rest_api_id = aws_api_gateway_rest_api.trading_api.id

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.dummy,
    aws_api_gateway_integration_response.dummy
  ]
}

resource "aws_api_gateway_stage" "trading_api" {
  deployment_id = aws_api_gateway_deployment.trading_api.id
  rest_api_id  = aws_api_gateway_rest_api.trading_api.id
  stage_name   = var.environment

  xray_tracing_enabled = var.xray_tracing_enabled
  cache_cluster_enabled = var.cache_enabled
  cache_cluster_size   = var.cache_enabled ? var.cache_size : null

  depends_on = [aws_api_gateway_account.main]

  dynamic "access_log_settings" {
    for_each = var.logging_level != "OFF" ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
      format         = jsonencode({
        requestId      = "$context.requestId"
        ip            = "$context.identity.sourceIp"
        caller        = "$context.identity.caller"
        user          = "$context.identity.user"
        requestTime   = "$context.requestTime"
        httpMethod    = "$context.httpMethod"
        resourcePath  = "$context.resourcePath"
        status        = "$context.status"
        protocol      = "$context.protocol"
        responseLength = "$context.responseLength"
      })
    }
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  count = var.logging_level != "OFF" ? 1 : 0
  name  = "/aws/api-gateway/${var.project_name}-${var.environment}"

  retention_in_days = 7
  tags             = var.tags
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.trading_api.id
  stage_name  = aws_api_gateway_stage.trading_api.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = var.metrics_enabled
    logging_level     = var.logging_level
    data_trace_enabled = var.logging_level == "INFO"
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
  }
}

resource "aws_api_gateway_gateway_response" "cors" {
  rest_api_id = aws_api_gateway_rest_api.trading_api.id
  response_type = "DEFAULT_4XX"
  status_code = "400"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT,DELETE'"
  }
}
