variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs for the ALB"
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnet IDs where the ALB will be deployed"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate"
  type        = string
}
