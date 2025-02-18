variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "secrets" {
  description = "Map of secrets to create"
  type = map(object({
    description = string
    value       = map(string)
  }))
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption"
  type        = string
}

variable "allowed_role_arns" {
  description = "List of IAM role ARNs allowed to access the secrets"
  type        = list(string)
}
