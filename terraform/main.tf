# =============================================================================
# Root Terraform Configuration
# CCS6344 Assignment 2 — Part D: Secure AWS Implementation
# Group 1: Mohamad Omar Naim, Adam Imtiyaz, Adam Wafiy
#
# Architecture: VPC → Security Groups/NACLs → RDS (encrypted, Multi-AZ)
#               → EC2 Auto Scaling → ALB (HTTPS, WAF) → Secrets Manager
#               → CloudTrail → CloudWatch
# =============================================================================

data "aws_caller_identity" "current" {}

# Random password for Flask SECRET_KEY (stored in Secrets Manager, not code)
resource "random_password" "flask_secret" {
  length  = 32
  special = true
}

# =============================================================================
# MODULE: VPC — Three-tier network segmentation (Risk 1 mitigation)
# =============================================================================
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = var.availability_zones
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  app_subnet_cidrs    = ["10.0.3.0/24", "10.0.4.0/24"]
  db_subnet_cidrs     = ["10.0.5.0/24", "10.0.6.0/24"]
}

# =============================================================================
# MODULE: Security — Security Groups and NACLs (Risk 1 mitigation)
# =============================================================================
module "security" {
  source = "./modules/security"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  public_subnet_ids = module.vpc.public_subnet_ids
  app_subnet_ids    = module.vpc.app_subnet_ids
  db_subnet_ids     = module.vpc.db_subnet_ids
  app_subnet_cidrs  = ["10.0.3.0/24", "10.0.4.0/24"]
}

# =============================================================================
# MODULE: Monitoring — CloudWatch log group (needed before IAM for its ARN)
# (Risk 6 mitigation)
# =============================================================================
module "monitoring" {
  source = "./modules/monitoring"

  project_name   = var.project_name
  environment    = var.environment
  rds_identifier = module.database.rds_identifier
  alb_arn_suffix = module.compute.alb_arn_suffix

  depends_on = [module.database, module.compute]
}

# =============================================================================
# MODULE: IAM — Least-privilege EC2 role (Risk 2 mitigation)
# Depends on Secrets Manager secret and CloudWatch log group ARNs.
# =============================================================================
module "iam" {
  source = "./modules/iam"

  project_name  = var.project_name
  environment   = var.environment
  secret_arn    = aws_secretsmanager_secret.app.arn
  log_group_arn = module.monitoring.log_group_arn

  depends_on = [module.monitoring]
}

# =============================================================================
# MODULE: Database — RDS PostgreSQL, encrypted, Multi-AZ (Risks 4 + 5)
# =============================================================================
module "database" {
  source = "./modules/database"

  project_name       = var.project_name
  environment        = var.environment
  db_subnet_ids      = module.vpc.db_subnet_ids
  db_sg_id           = module.security.db_sg_id
  db_username        = var.db_username
  db_password        = var.db_password
  availability_zones = var.availability_zones
}

# =============================================================================
# MODULE: Storage — S3 for ALB logs and CloudTrail (Risks 4 + 6)
# =============================================================================
module "storage" {
  source = "./modules/storage"

  project_name   = var.project_name
  environment    = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region
}

# =============================================================================
# MODULE: Compute — ALB, WAF, EC2 Auto Scaling (Risks 1, 3, 4)
# =============================================================================
module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  public_subnet_ids    = module.vpc.public_subnet_ids
  app_subnet_ids       = module.vpc.app_subnet_ids
  alb_sg_id            = module.security.alb_sg_id
  app_sg_id            = module.security.app_sg_id
  instance_profile_arn = module.iam.instance_profile_arn
  secret_name          = aws_secretsmanager_secret.app.name
  alb_logs_bucket_name = module.storage.alb_logs_bucket_name
  acm_cert_arn         = var.acm_cert_arn
  domain_name          = var.domain_name

  depends_on = [module.iam, module.storage]
}

# =============================================================================
# Secrets Manager — stores DB credentials and Flask secret key
# (Risk 2 mitigation — no hardcoded credentials anywhere in codebase)
# =============================================================================
resource "aws_secretsmanager_secret" "app" {
  name        = "${var.project_name}/db"
  description = "Database credentials and Flask secret for Hardware Store app"

  # Automatic rotation every 30 days would be configured here in production
  # rotation_lambda_arn = ...

  tags = { Name = "${var.project_name}-secret" }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  # JSON value — the Flask app reads these keys at runtime via boto3
  secret_string = jsonencode({
    host         = module.database.db_endpoint
    port         = tostring(module.database.db_port)
    dbname       = module.database.db_name
    username     = var.db_username
    password     = var.db_password
    flask_secret = random_password.flask_secret.result
  })

  depends_on = [module.database]
}
