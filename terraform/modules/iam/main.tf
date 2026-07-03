# =============================================================================
# Module: iam
# Purpose: Least-privilege IAM role and instance profile for EC2 app servers.
#
# Security design (Part A Risk 2 — Over-privileged, shared accounts):
#   - EC2 gets an instance profile, not hardcoded access keys
#   - Can ONLY read the one specific Secrets Manager secret
#   - Can ONLY write logs to the one specific CloudWatch log group
#   - SSM Session Manager replaces SSH (no port 22 needed — no SSH key to steal)
# =============================================================================

# Assume-role policy: allows EC2 to assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Role for EC2 instances
# -----------------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "Least-privilege role for Hardware Store app EC2 instances"

  tags = { Name = "${var.project_name}-ec2-role" }
}

# -----------------------------------------------------------------------------
# Inline policy: read ONE specific Secrets Manager secret only
# (Risk 2 mitigation — no admin access, scoped to exact resource ARN)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "secrets_read" {
  name = "SecretsManagerReadOne"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAppSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Scoped to the exact secret ARN — not secretsmanager:*
        Resource = [var.secret_arn]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Inline policy: write logs to ONE specific CloudWatch log group
# (Risk 6 mitigation — enables centralized audit logging)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "CloudWatchLogsWrite"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteAppLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        # Scoped to our log group and its streams only
        Resource = [
          var.log_group_arn,
          "${var.log_group_arn}:*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Managed policy: SSM Session Manager — enables secure shell access without
# opening port 22 or managing SSH keys (eliminates a common attack vector)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# -----------------------------------------------------------------------------
# Instance profile — attaches the role to EC2 instances via launch template
# -----------------------------------------------------------------------------
resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.app.name
  tags = { Name = "${var.project_name}-ec2-profile" }
}
