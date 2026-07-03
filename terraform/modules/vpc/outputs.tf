output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB, NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "IDs of the private app subnets (EC2)"
  value       = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  description = "IDs of the private DB subnets (RDS)"
  value       = aws_subnet.db[*].id
}
