variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
  default     = "trading-api"
}

variable "description" {
  description = "Description of the API Gateway"
  type        = string
  default     = "Trading Platform API Gateway"
}

variable "protocol_type" {
  description = "API protocol type (HTTP, WEBSOCKET, REST)"
  type        = string
  default     = "REST"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "endpoint_type" {
  description = "Endpoint type of the API Gateway (EDGE, REGIONAL, PRIVATE)"
  type        = string
  default     = "REGIONAL"
}

variable "stage_name" {
  description = "Name of the API Gateway stage"
  type        = string
  default     = "dev"
}

variable "logging_level" {
  description = "Logging level for API Gateway (OFF, ERROR, INFO)"
  type        = string
  default     = "INFO"
}

variable "metrics_enabled" {
  description = "Enable detailed CloudWatch metrics"
  type        = bool
  default     = true
}

variable "xray_tracing_enabled" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = false
}

variable "cache_enabled" {
  description = "Enable API caching"
  type        = bool
  default     = false
}

variable "cache_size" {
  description = "Size of the API cache (0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237)"
  type        = string
  default     = "0.5"
}
