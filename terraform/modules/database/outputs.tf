output "db_endpoint" {
  description = "RDS instance endpoint (hostname only, without port)"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for RDS encryption"
  value       = aws_kms_key.rds.arn
}

output "rds_identifier" {
  description = "RDS instance identifier (for CloudWatch alarms)"
  value       = aws_db_instance.main.identifier
}
