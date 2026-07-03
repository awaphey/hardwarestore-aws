variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to create security groups in"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (used in NACL rules)"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets (for NACL association)"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "IDs of the private app subnets (for NACL association)"
  type        = list(string)
}

variable "db_subnet_ids" {
  description = "IDs of the private DB subnets (for NACL association)"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "CIDRs of app subnets (used in DB NACL to restrict source)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}
