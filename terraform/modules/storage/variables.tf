variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (used in CloudTrail S3 bucket policy)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in CloudTrail bucket policy)"
  type        = string
}
