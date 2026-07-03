variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short identifier used in resource names and tags"
  type        = string
  default     = "hardwarestore"
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
  default     = "production"
}

variable "availability_zones" {
  description = "Two AZs for Multi-AZ resilience (Risk 5 mitigation)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "db_username" {
  description = "Master username for the RDS PostgreSQL instance"
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "Master password for the RDS PostgreSQL instance (sensitive — never commit plaintext)"
  type        = string
  sensitive   = true
  # No default — must be supplied via TF_VAR_db_password env var or tfvars file
}

variable "domain_name" {
  description = "Domain name for the ACM TLS certificate (must be a domain you control or use a pre-issued cert ARN)"
  type        = string
  default     = "hardwarestore.example.com"
}

variable "acm_cert_arn" {
  description = "ARN of an existing ACM certificate. If provided, skips certificate creation. Recommended for real deployments."
  type        = string
  default     = ""
}
