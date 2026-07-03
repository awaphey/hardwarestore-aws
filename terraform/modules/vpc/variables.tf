variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of two AZs for Multi-AZ deployment"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (ALB, NAT Gateway)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_subnet_cidrs" {
  description = "CIDRs for private app subnets (EC2 instances)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDRs for private DB subnets (RDS)"
  type        = list(string)
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
}
