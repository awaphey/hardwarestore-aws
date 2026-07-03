variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "db_subnet_ids" {
  description = "IDs of the private DB subnets"
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security Group ID for the RDS instance"
  type        = string
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
}

variable "db_password" {
  description = "Master password for RDS (sensitive)"
  type        = string
  sensitive   = true
}

variable "availability_zones" {
  description = "AZs for Multi-AZ deployment"
  type        = list(string)
}
