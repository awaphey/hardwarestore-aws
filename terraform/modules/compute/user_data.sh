#!/bin/bash
# =============================================================================
# EC2 User Data Bootstrap Script
# Runs once on first boot to install and start the Hardware Store Flask app.
# Variables are injected by Terraform's templatefile() function.
# =============================================================================

set -euo pipefail
exec > /var/log/user-data.log 2>&1
echo "=== Bootstrap started: $(date) ==="

# --- System update and dependency install ---
dnf update -y
dnf install -y python3 python3-pip git

# --- Create app user and directory (don't run app as root) ---
useradd -r -s /sbin/nologin appuser 2>/dev/null || true
mkdir -p /opt/hardwarestore
chown appuser:appuser /opt/hardwarestore

# --- Clone app from GitHub (replace with your actual repo URL after pushing) ---
# git clone https://github.com/YOUR_ORG/hardwarestore-aws.git /opt/hardwarestore
# For now, install dependencies only (app files deployed separately via CodeDeploy or S3)

# --- Install Python dependencies ---
pip3 install flask==3.1.1 psycopg2-binary==2.9.10 boto3==1.38.0 \
             botocore==1.38.0 watchtower==3.3.1 gunicorn==23.0.0

# --- Write environment file (credentials fetched from Secrets Manager at runtime) ---
cat > /etc/hardwarestore.env << 'ENVFILE'
SECRET_NAME=${secret_name}
AWS_DEFAULT_REGION=${aws_region}
CW_LOG_GROUP=hardwarestore-app
CW_LOG_STREAM=app
ENVFILE

chmod 600 /etc/hardwarestore.env
chown appuser:appuser /etc/hardwarestore.env

# --- Write systemd service unit ---
cat > /etc/systemd/system/hardwarestore.service << 'SERVICE'
[Unit]
Description=Hardware Store Flask Application (gunicorn)
After=network.target

[Service]
Type=simple
User=appuser
WorkingDirectory=/opt/hardwarestore
EnvironmentFile=/etc/hardwarestore.env
ExecStart=/usr/local/bin/gunicorn \
    --workers 2 \
    --bind 0.0.0.0:5000 \
    --access-logfile /var/log/hardwarestore-access.log \
    --error-logfile /var/log/hardwarestore-error.log \
    app:app
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE

# --- Enable and start service ---
systemctl daemon-reload
systemctl enable hardwarestore
# Service will fully start once app code is deployed to /opt/hardwarestore
# systemctl start hardwarestore

echo "=== Bootstrap complete: $(date) ==="
