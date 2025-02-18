variable "name" {
  description = "Name of the message queue broker"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "mq_username" {
  description = "Username for the message queue"
  type        = string
}

variable "mq_password" {
  description = "Password for the message queue"
  type        = string
  sensitive   = true
}

variable "security_group_ids" {
  description = "Security group IDs for the message queue"
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnet IDs for the message queue"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
