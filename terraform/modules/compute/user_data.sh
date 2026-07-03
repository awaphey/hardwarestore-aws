#!/bin/bash
# =============================================================================
# EC2 User Data Bootstrap Script
# Runs once on first boot to install and start the Hardware Store Flask app.
# Variables are injected by Terraform's templatefile() function.
# =============================================================================

exec > /var/log/user-data.log 2>&1
echo "=== Bootstrap started: $(date) ==="

# --- System update and dependency install ---
dnf update -y
dnf install -y python3 python3-pip git postgresql15

# --- Clone app from GitHub ---
mkdir -p /opt/hardwarestore
git clone https://github.com/awaphey/hardwarestore-aws.git /opt/hardwarestore

# --- Install Python dependencies ---
pip3 install flask==3.1.1 psycopg2-binary==2.9.10 boto3==1.38.0 \
             botocore==1.38.0 watchtower==3.3.1 gunicorn==23.0.0

# --- Write systemd service unit ---
cat > /etc/systemd/system/hardwarestore.service << 'SERVICE'
[Unit]
Description=Hardware Store Flask Application (gunicorn)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/hardwarestore/app
Environment=SECRET_NAME=${secret_name}
Environment=AWS_DEFAULT_REGION=${aws_region}
Environment=CW_LOG_GROUP=hardwarestore-app
Environment=CW_LOG_STREAM=app
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
systemctl start hardwarestore

echo "=== Bootstrap complete: $(date) ==="
