# =============================================================================
# Module: storage
# Purpose: Encrypted S3 buckets for ALB logs and CloudTrail audit logs,
#          plus the CloudTrail trail itself.
#
# Security controls:
#   - S3 public access blocked (Risk 1 + Risk 4)
#   - Server-side encryption (AES-256) on both buckets (Risk 4)
#   - CloudTrail for API audit logging across all regions (Risk 6)
#   - Log file integrity validation (tamper detection)
#   - 90-day lifecycle expiry on ALB logs
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# ALB Access Logs Bucket
# =============================================================================
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-alb-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true   # Allow destroy for assignment teardown; remove in production

  tags = { Name = "${var.project_name}-alb-logs" }
}

# Block all public access — logs must never be publicly readable
resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encryption at rest (Risk 4 mitigation)
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning — retains history of log objects
resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

# Lifecycle — expire logs after 90 days to manage storage costs
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-alb-logs"
    status = "Enabled"
    expiration { days = 90 }
  }
}

# Bucket policy — allow the ALB service to write access logs
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowALBLogging"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb-logs/AWSLogs/*"
      }
    ]
  })
}

# =============================================================================
# CloudTrail Logs Bucket
# =============================================================================
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = { Name = "${var.project_name}-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

# Bucket policy — required by CloudTrail service to write logs
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.aws_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# =============================================================================
# CloudTrail — full API audit logging (Risk 6 mitigation)
# Records every AWS API call: who, what, when, from where.
# =============================================================================
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  s3_key_prefix                 = ""
  include_global_service_events = true   # Captures IAM, STS events
  is_multi_region_trail         = true   # Catches activity in all regions
  enable_log_file_validation    = true   # SHA-256 digest for tamper detection

  tags = { Name = "${var.project_name}-trail" }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
