output "alb_sg_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Security Group ID for EC2 app instances"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security Group ID for the RDS database"
  value       = aws_security_group.db.id
}
