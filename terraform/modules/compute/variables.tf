variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of public subnets for the ALB"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "IDs of private app subnets for EC2 instances"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "app_sg_id" {
  description = "Security Group ID for EC2 instances"
  type        = string
}

variable "instance_profile_arn" {
  description = "ARN of the IAM instance profile for EC2"
  type        = string
}

variable "secret_name" {
  description = "Name of the Secrets Manager secret (passed to app via user_data env var)"
  type        = string
}

variable "alb_logs_bucket_name" {
  description = "S3 bucket name for ALB access logs"
  type        = string
}

variable "acm_cert_arn" {
  description = "ARN of an existing ACM certificate. Leave empty to create a new one (DNS validation)."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for ACM certificate (only used when acm_cert_arn is empty)"
  type        = string
  default     = "hardwarestore.example.com"
}
