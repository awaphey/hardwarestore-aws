# =============================================================================
# Module: monitoring
# Purpose: CloudWatch log group, metric alarms, and SNS alerting.
#
# Security controls (Risk 6 mitigation — No centralized logging/monitoring):
#   - CloudWatch log group receives Flask app logs via watchtower
#   - Alarms on RDS CPU and ALB 5xx errors — enables incident detection
#   - SNS topic for alert notifications
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Group — receives Flask app logs from watchtower
# 30-day retention balances audit requirements with storage cost
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "hardwarestore-app"
  retention_in_days = 30

  tags = { Name = "${var.project_name}-log-group" }
}

# -----------------------------------------------------------------------------
# SNS Topic — receives alarm notifications
# Subscribe an email address after deployment: aws sns subscribe ...
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = { Name = "${var.project_name}-alerts" }
}

# -----------------------------------------------------------------------------
# Alarm: RDS high CPU — potential sign of a DoS or runaway query
# Fires when CPU exceeds 80% for two consecutive 5-minute periods
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project_name}-rds-cpu-high"
  alarm_description   = "RDS CPU utilisation exceeded 80% — potential performance or security issue"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.rds_identifier }
  statistic           = "Average"
  period              = 300   # 5 minutes
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-alarm-rds-cpu" }
}

# -----------------------------------------------------------------------------
# Alarm: ALB 5xx error rate — detects application errors or attack activity
# Fires when 5xx count exceeds 10 in a single 5-minute window
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx-high"
  alarm_description   = "ALB HTTP 5xx errors exceeded 10 — potential app failure or attack"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-alarm-alb-5xx" }
}
