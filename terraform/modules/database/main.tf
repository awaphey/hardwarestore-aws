# =============================================================================
# Module: database
# Purpose: RDS PostgreSQL with encryption, Multi-AZ, and automated backups.
#
# Security controls demonstrated:
#   - StorageEncrypted = true + KMS (Risk 4 — No encryption at rest)
#   - Multi-AZ deployment (Risk 5 — Single-copy backups)
#   - 7-day automated backups with PITR (Risk 5)
#   - Isolated in private DB subnet with no internet route (Risk 1)
# =============================================================================

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# KMS Key — encrypts RDS storage at rest (Risk 4 mitigation)
# Customer-managed key gives full auditability via CloudTrail.
# -----------------------------------------------------------------------------
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS PostgreSQL encryption at rest - ${var.project_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true   # Automatic annual key rotation (security best practice)
  multi_region            = false

  tags = { Name = "${var.project_name}-kms-rds" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# -----------------------------------------------------------------------------
# DB Subnet Group — places RDS in the isolated private DB subnets
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Subnet group for ${var.project_name} RDS - private DB subnets only"
  subnet_ids  = var.db_subnet_ids

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL Instance
#
# Key security settings:
#   - multi_az = true              (Risk 5: availability + failover)
#   - storage_encrypted = true     (Risk 4: encryption at rest)
#   - kms_key_id                   (Risk 4: customer-managed key)
#   - publicly_accessible = false  (Risk 1: no internet route to DB)
#   - backup_retention_period = 7  (Risk 5: 7-day PITR window)
#   - deletion_protection = false  (set true in real prod; off for assignment teardown)
#   - skip_final_snapshot = true   (set false in real prod)
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-rds"

  # Engine
  engine               = "postgres"
  engine_version       = "15"
  instance_class       = "db.t3.micro"   # Free-tier eligible for assignment

  # Storage — encrypted with KMS key (Risk 4 mitigation)
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  # Database identity
  db_name  = "hardwarestore"
  username = var.db_username
  password = var.db_password

  # Networking — private, no internet access (Risk 1 mitigation)
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false

  # High availability — Multi-AZ synchronous standby (Risk 5 mitigation)
  multi_az = true

  # Backups — 7-day retention with Point-in-Time Recovery (Risk 5 mitigation)
  backup_retention_period   = 7
  backup_window             = "02:00-03:00"   # Off-peak UTC
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true

  # Performance and monitoring
  performance_insights_enabled = true
  monitoring_interval          = 0    # Enhanced monitoring disabled (no monitoring role configured)

  # Lifecycle — set deletion_protection=true and skip_final_snapshot=false in production
  deletion_protection       = false
  skip_final_snapshot       = true
  apply_immediately         = true

  tags = { Name = "${var.project_name}-rds" }
}
