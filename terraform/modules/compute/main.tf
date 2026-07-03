# =============================================================================
# Module: compute
# Purpose: ALB (with HTTPS + WAF), EC2 Auto Scaling Group, ACM certificate.
#
# Security controls:
#   - ALB enforces HTTPS/TLS via ACM certificate (Risk 4 — No encryption in transit)
#   - HTTP → HTTPS redirect (Risk 4)
#   - AWS WAF on ALB blocks SQLi/XSS/OWASP Top 10 (Risk 3 — Unpatched software)
#   - EC2 in private subnets — no direct internet access (Risk 1)
#   - IAM instance profile attached (Risk 2 — least-privilege)
# =============================================================================

# Latest Amazon Linux 2023 AMI — kept updated by AWS, reduces patch burden
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# -----------------------------------------------------------------------------
# ACM Certificate — TLS for the ALB (Risk 4 mitigation: encryption in transit)
# IMPORTANT: After terraform apply, you must add the DNS CNAME record shown in
# the AWS console (or run: aws acm describe-certificate ...) to validate ownership.
# If you already have a cert ARN, set var.acm_cert_arn and this is skipped.
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "app" {
  count             = var.acm_cert_arn == "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-acm-cert" }
}

locals {
  # Use existing cert ARN if provided, otherwise use the one we just created
  cert_arn = var.acm_cert_arn != "" ? var.acm_cert_arn : aws_acm_certificate.app[0].arn
}

# -----------------------------------------------------------------------------
# Application Load Balancer — public-facing, HTTPS only
# ALB is the single entry point; EC2 instances are not reachable directly.
# -----------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  # Access log to S3 (Risk 6 — centralised logging)
  access_logs {
    bucket  = var.alb_logs_bucket_name
    prefix  = "alb-logs"
    enabled = true
  }

  tags = { Name = "${var.project_name}-alb" }
}

# -----------------------------------------------------------------------------
# Target Group — routes traffic to EC2 instances on port 5000
# Health check on /health endpoint (defined in app.py)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = data.aws_subnet.app_first.vpc_id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project_name}-tg" }
}

data "aws_subnet" "app_first" {
  id = var.app_subnet_ids[0]
}

# -----------------------------------------------------------------------------
# ALB Listener: HTTP (80) → Redirect to HTTPS (Risk 4 mitigation)
# No plaintext HTTP traffic ever reaches the application.
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = { Name = "${var.project_name}-listener-http" }
}

# -----------------------------------------------------------------------------
# ALB Listener: HTTPS (443) — TLS termination, forwards to app target group
# SSL policy: ELBSecurityPolicy-TLS13-1-2-2021-06 (TLS 1.2+ only)
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = { Name = "${var.project_name}-listener-https" }
}

# -----------------------------------------------------------------------------
# AWS WAF v2 — blocks OWASP Top 10 (SQL injection, XSS, etc.)
# Attached to the ALB so malicious traffic is filtered before reaching EC2.
# (Risk 3 mitigation — compensating control for unpatched software)
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "WAF for Hardware Store ALB — blocks OWASP Top 10 threats"
  scope       = "REGIONAL"   # ALB uses REGIONAL scope (CLOUDFRONT uses GLOBAL)

  default_action {
    allow {}   # Allow by default; rules below block known-bad patterns
  }

  # Rule 1: AWS Managed Rules — Core Rule Set (SQLi, XSS, command injection)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: SQL Database rules — targets SQL injection specifically
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known bad inputs (log4j, SSRF, etc.)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-waf-badinputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.project_name}-waf" }
}

# Associate WAF with the ALB
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# -----------------------------------------------------------------------------
# EC2 Launch Template
# Bootstraps the Flask app via user_data on first boot.
# Instance profile grants least-privilege AWS API access (Risk 2 mitigation).
# No public IP — instance is in private subnet (Risk 1 mitigation).
# -----------------------------------------------------------------------------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  description   = "Hardware Store Flask app — Amazon Linux 2023"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  # Attach IAM instance profile (not hardcoded keys — Risk 2 mitigation)
  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  # Place in app security group (private, no direct internet access)
  vpc_security_group_ids = [var.app_sg_id]

  # No public IP — traffic only enters via ALB (Risk 1 mitigation)
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.app_sg_id]
  }

  # Encrypt EBS root volume (Risk 4 mitigation)
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # User data: bootstraps the Flask app on first boot
  # Base64 encoding is handled automatically by Terraform's templatefile
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    secret_name = var.secret_name
    aws_region  = var.aws_region
    project     = var.project_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-app-server"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group — maintains 1 instance (min), scales to 2 under load
# Spans both private app subnets for AZ resilience
# -----------------------------------------------------------------------------
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = var.app_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app-server"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
