# =============================================================================
# Module: security
# Purpose: Security Groups and NACLs for the three-tier architecture.
#
# Security design:
#   - Security Groups: stateful, instance-level allow-lists (deny-by-default)
#   - NACLs: stateless subnet-level backstop (defense-in-depth)
#
# Traffic flow enforced:
#   Internet → ALB SG (443/80) → App SG (5000) → DB SG (5432)
#   No path from internet directly to app or DB tiers.
# =============================================================================

# -----------------------------------------------------------------------------
# ALB Security Group — only allows HTTPS (443) and HTTP (80) from internet.
# HTTP is permitted here so we can redirect it to HTTPS at the listener level.
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "ALB: allow HTTP/HTTPS inbound from internet; forward to app tier"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirected to HTTPS by listener rule)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward traffic to app tier on port 5000"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-alb" }
}

# -----------------------------------------------------------------------------
# App Tier Security Group — only allows traffic from the ALB SG.
# EC2 instances cannot be reached directly from the internet.
# Egress: allows outbound to DB (5432) and HTTPS (443) for AWS API calls
# (Secrets Manager, CloudWatch).
# -----------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg-app"
  description = "App tier: allow port 5000 from ALB only; DB and AWS API egress"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Flask app port — from ALB only (least-privilege ingress)"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description     = "PostgreSQL to DB tier only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db.id]
  }

  egress {
    description = "HTTPS outbound for AWS API calls (Secrets Manager, CloudWatch, SSM)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-app" }
}

# -----------------------------------------------------------------------------
# DB Tier Security Group — only allows PostgreSQL traffic from the app tier.
# No egress rule means no outbound connections from RDS whatsoever.
# This is the tightest security group — database should never initiate outbound.
# -----------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.project_name}-sg-db"
  description = "DB tier: allow PostgreSQL (5432) from app tier only; no egress"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from app tier only (Risk 1 + Risk 2 mitigation)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # No egress rule = AWS default deny-all outbound for this SG

  tags = { Name = "${var.project_name}-sg-db" }
}

# =============================================================================
# NACLs — stateless subnet-level firewall (defense-in-depth layer 2)
# NACLs supplement Security Groups. Because they are stateless, both inbound
# AND return/ephemeral traffic rules are needed.
# Ephemeral port range: 1024–65535 (TCP client return traffic)
# =============================================================================

# -----------------------------------------------------------------------------
# Public NACL — permits web traffic in, ephemeral ports out
# -----------------------------------------------------------------------------
resource "aws_network_acl" "public" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  # Inbound: HTTPS
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Inbound: HTTP (for redirect)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Inbound: ephemeral ports (return traffic from NAT Gateway / internet responses)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound: HTTPS to app tier
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 5000
    to_port    = 5000
  }

  # Outbound: ephemeral ports to internet (response traffic back to clients)
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = { Name = "${var.project_name}-nacl-public" }
}

# -----------------------------------------------------------------------------
# App NACL — only VPC-internal traffic allowed
# -----------------------------------------------------------------------------
resource "aws_network_acl" "app" {
  vpc_id     = var.vpc_id
  subnet_ids = var.app_subnet_ids

  # Inbound: from ALB on port 5000
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 5000
    to_port    = 5000
  }

  # Inbound: ephemeral return traffic (AWS API responses, DB responses)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound: HTTPS to AWS APIs via NAT Gateway
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Outbound: PostgreSQL to DB tier
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 5432
    to_port    = 5432
  }

  # Outbound: ephemeral ports back to ALB
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  tags = { Name = "${var.project_name}-nacl-app" }
}

# -----------------------------------------------------------------------------
# DB NACL — strictest tier, only PostgreSQL from app subnets
# -----------------------------------------------------------------------------
resource "aws_network_acl" "db" {
  vpc_id     = var.vpc_id
  subnet_ids = var.db_subnet_ids

  # Inbound: PostgreSQL from app subnet 1 only
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.app_subnet_cidrs[0]
    from_port  = 5432
    to_port    = 5432
  }

  # Inbound: PostgreSQL from app subnet 2 (second AZ)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.app_subnet_cidrs[1]
    from_port  = 5432
    to_port    = 5432
  }

  # Outbound: ephemeral return traffic to app tier only
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  tags = { Name = "${var.project_name}-nacl-db" }
}
