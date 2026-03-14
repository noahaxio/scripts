#!/bin/bash

set -e  # Exit on error

# ==============================================================================
# GNOME Remote Desktop (RDP) Headless Setup Script for Wayland
# ==============================================================================

RDP_USER="debix"
RDP_PASS="debix"

echo "Starting headless RDP setup for $USER..."

if [ "$EUID" -eq 0 ]; then
  echo "Error: Do not run this script with sudo. Run it as your normal user."
  exit 1
fi

echo "Stopping GNOME Remote Desktop and Keyring daemon..."
systemctl --user stop gnome-remote-desktop.service 2>/dev/null || true
killall -9 gnome-keyring-daemon 2>/dev/null || true
sleep 1

echo "Generating TLS Certificates..."
CERT_DIR="$HOME"
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
  -subj "/O=Debix/CN=$(hostname)" \
  -keyout "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" 2>/dev/null

if [ ! -f "$HOME/.local/share/keyrings/login.keyring" ]; then
  echo "Setting up GNOME Keyring..."
  mkdir -p "$HOME/.local/share/keyrings"
  cat <<'EOF' > "$HOME/.local/share/keyrings/login.keyring"
[keyring]
display-name=login
ctime=0
mtime=0
lock-on-idle=false
lock-after=false
EOF
  echo "login" > "$HOME/.local/share/keyrings/default"
else
  echo "GNOME Keyring already exists."
fi

export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Start keyring daemon (non-blocking - ignore if it fails)
echo "Starting GNOME Keyring daemon..."
eval "$(timeout 5 gnome-keyring-daemon --start --components=secrets 2>/dev/null)" || true

echo "Starting GNOME Remote Desktop service..."
systemctl --user start gnome-remote-desktop.service
sleep 3  # Give service time to initialize

echo "Configuring GNOME Remote Desktop..."

# Use timeout for all grdctl commands (30 seconds each)
# If a command hangs, timeout will kill it and continue
timeout 30 grdctl rdp set-tls-key "$CERT_DIR/tls.key" || echo "Warning: grdctl rdp set-tls-key may have timed out"
timeout 30 grdctl rdp set-tls-cert "$CERT_DIR/tls.crt" || echo "Warning: grdctl rdp set-tls-cert may have timed out"
timeout 30 grdctl rdp set-credentials "$RDP_USER" "$RDP_PASS" || echo "Warning: grdctl rdp set-credentials may have timed out"
timeout 30 grdctl rdp disable-view-only || echo "Warning: grdctl rdp disable-view-only may have timed out"
timeout 30 grdctl rdp enable || echo "Warning: grdctl rdp enable may have timed out"

# Skip VNC in headless mode - it's not needed if you only want RDP
# timeout 30 grdctl vnc disable || true

echo "Restarting GNOME Remote Desktop service..."
systemctl --user restart gnome-remote-desktop.service
sleep 2

echo "Enabling GNOME Remote Desktop on boot..."
systemctl --user enable gnome-remote-desktop.service

echo "Setup Complete! Status:"
echo "------------------------------------------------"
systemctl --user status gnome-remote-desktop.service --no-pager || true
echo "------------------------------------------------"
echo "You can now connect via RDP."
echo ""
echo "For auto-start on boot without login, run:"
echo "  sudo loginctl enable-linger $USER"