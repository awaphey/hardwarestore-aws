variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "rds_identifier" {
  description = "RDS instance identifier for CloudWatch metric namespace"
  type        = string
}

