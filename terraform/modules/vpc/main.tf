# =============================================================================
# Module: vpc
# Purpose: Creates the VPC and all subnets for a three-tier architecture.
#
# Security design (maps to Part A Risk 1 — Flat, unsegmented network):
#   - Public subnets: only ALB and NAT Gateway are here
#   - Private app subnets: EC2 instances, no direct internet route
#   - Private DB subnets: RDS, no internet route at all
# =============================================================================

# -----------------------------------------------------------------------------
# VPC — the network boundary for all resources
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true   # Required for RDS endpoint resolution
  enable_dns_hostnames = true   # Required for SSM Session Manager

  tags = { Name = "${var.project_name}-vpc" }
}

# -----------------------------------------------------------------------------
# Internet Gateway — allows ALB in the public subnet to receive internet traffic
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# -----------------------------------------------------------------------------
# Public subnets — one per AZ, hosts the ALB and NAT Gateway only
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # EC2 instances launched here do NOT get public IPs — only ALB/NAT Gateway
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-public-${count.index + 1}" }
}

# -----------------------------------------------------------------------------
# Private app subnets — EC2 instances, no direct internet inbound route
# -----------------------------------------------------------------------------
resource "aws_subnet" "app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-app-${count.index + 1}" }
}

# -----------------------------------------------------------------------------
# Private DB subnets — RDS only, completely isolated (no internet route)
# -----------------------------------------------------------------------------
resource "aws_subnet" "db" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-db-${count.index + 1}" }
}

# -----------------------------------------------------------------------------
# Elastic IP for NAT Gateway (static IP so app tier outbound can be allow-listed)
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

# -----------------------------------------------------------------------------
# NAT Gateway — in the first public subnet only (cost optimisation for assignment)
# Allows app tier EC2s to reach AWS APIs (Secrets Manager, CloudWatch) outbound,
# but no inbound internet traffic can reach the private subnets.
# -----------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-nat" }

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Route table: public subnets → Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Route table: app subnets → NAT Gateway (outbound only)
# No inbound route from the internet — all inbound goes through ALB in public subnet
# -----------------------------------------------------------------------------
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project_name}-rt-app" }
}

resource "aws_route_table_association" "app" {
  count          = length(aws_subnet.app)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# -----------------------------------------------------------------------------
# Route table: DB subnets — NO default route (completely isolated)
# The DB tier cannot initiate any outbound connections outside the VPC.
# -----------------------------------------------------------------------------
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  # No routes added — local VPC traffic only
  tags = { Name = "${var.project_name}-rt-db" }
}

resource "aws_route_table_association" "db" {
  count          = length(aws_subnet.db)
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
