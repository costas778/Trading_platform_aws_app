output "endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "db_name" {
  description = "The name of the database"
  value       = aws_db_instance.main.db_name
}

output "port" {
  description = "The port the database is listening on"
  value       = aws_db_instance.main.port
}

output "arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "id" {
  description = "The ID of the RDS instance"
  value       = aws_db_instance.main.id
}
