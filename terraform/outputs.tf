output "alb_dns_name" {
  description = "ALB DNS name — point your domain's CNAME here, or access the app directly via this"
  value       = module.compute.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint hostname"
  value       = module.database.db_endpoint
}

output "cloudtrail_bucket" {
  description = "S3 bucket name storing CloudTrail audit logs"
  value       = module.storage.cloudtrail_bucket_name
}

output "log_group_name" {
  description = "CloudWatch log group receiving Flask application logs"
  value       = module.monitoring.log_group_name
}

output "waf_acl_arn" {
  description = "ARN of the WAF Web ACL protecting the ALB"
  value       = module.compute.waf_acl_arn
}

output "secret_name" {
  description = "Secrets Manager secret name (reference this in your app config)"
  value       = aws_secretsmanager_secret.app.name
}
