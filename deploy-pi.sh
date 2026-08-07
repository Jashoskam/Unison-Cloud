#!/bin/bash
# ==============================================================================
# Unison OS - Raspberry Pi Centralized Neural Brain Deployment Script
# Target Architecture: ARM64 / ARMv7 Linux (Raspberry Pi OS, Ubuntu Server)
# ==============================================================================

set -e

echo "🧠 [UNISON_BRAIN] Starting Raspberry Pi Deployment Pipeline..."

# 1. Update package manager & install core prerequisites
echo "📦 Updating system packages..."
sudo apt-get update -y
sudo apt-get install -y curl build-essential git python3 lm-sensors htop

# 2. Check Node.js installation (v18+)
if ! command -v node &> /dev/null; then
    echo "⚡ Node.js not detected. Installing Node.js v20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
else
    echo "✓ Node.js $(node -v) detected."
fi

# 3. Install project dependencies
echo "📥 Installing npm packages..."
npm install --production=false

# 4. Generate systemd service file for 24/7 background operation
SERVICE_FILE="/etc/systemd/system/unison-brain.service"
CURRENT_DIR=$(pwd)
CURRENT_USER=$(whoami)

echo "🔧 Creating systemd daemon service: $SERVICE_FILE"

sudo bash -c "cat <<EOF > $SERVICE_FILE
[Unit]
Description=Unison OS Centralized Neural Brain Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$CURRENT_DIR
ExecStart=$(which npx) tsx server.ts
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF"

# 5. Reload systemd daemon & enable service
echo "🚀 Enabling and starting unison-brain.service..."
sudo systemctl daemon-reload
sudo systemctl enable unison-brain.service
sudo systemctl restart unison-brain.service

echo ""
echo "=============================================================================="
echo "🎉 Unison OS Centralized Neural Brain deployed successfully on Raspberry Pi!"
echo "📍 Access point: http://$(hostname -I | awk '{print $1}'):3000"
echo "📊 Systemd Status: sudo systemctl status unison-brain.service"
echo "📜 Log Feed: sudo journalctl -u unison-brain.service -f"
echo "=============================================================================="
