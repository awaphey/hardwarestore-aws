variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret the app is allowed to read"
  type        = string
}

variable "log_group_arn" {
  description = "ARN of the CloudWatch log group the app writes to"
  type        = string
}
