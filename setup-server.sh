#!/bin/bash
# OpenWA - Server Setup Script (Ubuntu, no Docker)
# Run as root: sudo bash setup-server.sh
set -e

echo "=== OpenWA Server Setup ==="

# 1. System dependencies
echo ""
echo "[1/6] Installing system dependencies..."
apt update && apt upgrade -y
apt install -y \
  chromium-browser \
  fonts-liberation libappindicator3-1 libasound2 libatk-bridge2.0-0 \
  libatk1.0-0 libcups2 libdbus-1-3 libdrm2 libgbm1 libgtk-3-0 \
  libnspr4 libnss3 libx11-xcb1 libxcomposite1 libxdamage1 libxrandr2 \
  xdg-utils curl git \
  || { echo "ERROR: apt install failed"; exit 1; }

# 2. Node.js 22
echo ""
echo "[2/6] Installing Node.js 22..."
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt install -y nodejs
fi
echo "Node.js version: $(node -v)"

# 3. Find Chromium path
CHROMIUM_PATH=$(which chromium-browser 2>/dev/null || which chromium 2>/dev/null || echo "")
if [ -z "$CHROMIUM_PATH" ]; then
  echo "WARNING: Chromium not found. Install it manually and set PUPPETEER_EXECUTABLE_PATH in .env"
fi
echo "Chromium path: ${CHROMIUM_PATH:-not found}"

# 4. npm install
echo ""
echo "[3/6] Installing npm dependencies (this may take a few minutes)..."
npm install --omit=dev

# 5. Build
echo ""
echo "[4/6] Building API and dashboard..."
npm run build
npm run dashboard:install
npm run dashboard:build

# 6. Create .env if missing
echo ""
echo "[5/6] Creating .env file..."
if [ ! -f .env ]; then
  cat > .env << ENVEOF
# ===========================================
# OpenWA - Production Configuration
# ===========================================
NODE_ENV=production
PORT=2785

# Database (SQLite)
DATABASE_TYPE=sqlite
DATABASE_NAME=./data/openwa.sqlite
DATABASE_SYNCHRONIZE=true
DATABASE_LOGGING=false

# WhatsApp Engine
ENGINE_TYPE=whatsapp-web.js
SESSION_DATA_PATH=./data/sessions
PUPPETEER_HEADLESS=true
PUPPETEER_ARGS=--no-sandbox,--disable-setuid-sandbox,--disable-dev-shm-usage,--disable-gpu
PUPPETEER_EXECUTABLE_PATH=${CHROMIUM_PATH}

# Auto-start previously authenticated sessions on boot
AUTO_START_SESSIONS=true

# Storage (Local filesystem)
STORAGE_TYPE=local
STORAGE_LOCAL_PATH=./data/media

# Redis & Queue (disabled)
REDIS_ENABLED=false
REDIS_BUILTIN=false
QUEUE_ENABLED=false
CACHE_ENABLED=false

# Built-in services (disabled)
POSTGRES_BUILTIN=false
MINIO_BUILTIN=false
ENVEOF
  echo "Created .env with PUPPETEER_EXECUTABLE_PATH=${CHROMIUM_PATH}"
else
  echo ".env already exists — skipping. Make sure PUPPETEER_EXECUTABLE_PATH is set."
fi

# 7. Create data directories
echo ""
echo "[6/6] Creating data directories..."
mkdir -p data/sessions data/media data/plugins

# 8. Systemd service
echo ""
echo "Setting up systemd service..."
cat > /etc/systemd/system/openwa.service << 'SVCEOF'
[Unit]
Description=OpenWA WhatsApp API Gateway
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=INSTALL_DIR
EnvironmentFile=INSTALL_DIR/.env
ExecStart=/usr/bin/node dist/main
Restart=always
RestartSec=5
KillSignal=SIGTERM
TimeoutStopSec=45

[Install]
WantedBy=multi-user.target
SVCEOF

# Replace INSTALL_DIR with actual path
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
sed -i "s|INSTALL_DIR|${INSTALL_DIR}|g" /etc/systemd/system/openwa.service

systemctl daemon-reload
systemctl enable openwa

echo ""
echo "=========================================="
echo "  Setup complete!"
echo "=========================================="
echo ""
echo "  Start the app:   systemctl start openwa"
echo "  View logs:       journalctl -u openwa -f"
echo "  Stop the app:    systemctl stop openwa"
echo "  Restart:         systemctl restart openwa"
echo ""
echo "  The app runs on http://localhost:2785"
echo "  Set up Nginx reverse proxy to expose it on your domain."
echo ""
