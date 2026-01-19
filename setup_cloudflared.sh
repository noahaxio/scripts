#!/bin/bash
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

set -e
read -p "What goes before .axioenergy.co: " PRECURSOR
echo "setting up cloudflared"
cd "$REAL_HOME"
sudo wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared-linux-arm64.deb
cloudflared tunnel login

sudo mkdir -p /home/debix/.cloudflared
sudo cp /root/.cloudflared/cert.pem /home/debix/.cloudflared/
sudo chown -R debix:debix /home/debix/.cloudflared

cloudflared tunnel create "$PRECURSOR"
sudo mkdir -p /etc/cloudflared

SRC_DIR="/home/debix/.cloudflared"
DEST_DIR="/etc/cloudflared"
FILE_PATH=$(find "$SRC_DIR" -maxdepth 1 -type f -name "*.json" | head -n 1)

if [ -z "$FILE_PATH" ]; then
    echo "No JSON file found in $SRC_DIR"
    exit 1
fi

Extract filename and ID (without extension)
FILENAME=$(basename "$FILE_PATH")
TUNNEL_ID="${FILENAME%.json}"
sudo cp "$FILE_PATH" "$DEST_DIR/$FILENAME"
echo "Copied: $FILENAME → $DEST_DIR"
echo "Tunnel ID: $TUNNEL_ID"

sudo tee /etc/cloudflared/config.yml > /dev/null << EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $PRECURSOR.axioenergy.co
    service: http://localhost:1881

  - service: http_status:404
EOF

echo "go to cloudflare and migrate to the online dashboard"
sudo cloudflared tunnel run