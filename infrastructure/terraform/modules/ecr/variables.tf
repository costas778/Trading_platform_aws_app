variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "repository_names" {
  description = "List of repository names to create"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption"
  type        = string
}
