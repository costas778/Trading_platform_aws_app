output "secret_arns" {
  description = "ARNs of the created secrets"
  value       = {
    for key, secret in aws_secretsmanager_secret.secret :
    key => secret.arn
  }
}

output "secret_names" {
  description = "Names of the created secrets"
  value       = {
    for key, secret in aws_secretsmanager_secret.secret :
    key => secret.name
  }
}
