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
sleep 5  # Give service time to initialize its D-Bus interface

echo "Configuring GNOME Remote Desktop..."

echo "Setting TLS certificates via dconf..."
gsettings set org.gnome.desktop.remote-desktop.rdp tls-key "$CERT_DIR/tls.key"
gsettings set org.gnome.desktop.remote-desktop.rdp tls-cert "$CERT_DIR/tls.crt"

echo "Enabling RDP and disabling view-only..."
gsettings set org.gnome.desktop.remote-desktop.rdp enable true
gsettings set org.gnome.desktop.remote-desktop.rdp view-only false

echo "Setting RDP credentials via D-Bus..."
# Use dbus-send to directly set credentials (bypasses Secret Service issues)
dbus-send --session \
  --dest=org.gnome.RemoteDesktop \
  --object-path=/org/gnome/RemoteDesktop \
  org.gnome.RemoteDesktop.Rdp.SetCredentials \
  string:"$RDP_USER" string:"$RDP_PASS" 2>&1 || echo "Note: Credentials may require manual setup if D-Bus method not available"

# Verify configuration was applied
echo ""
echo "Verifying RDP configuration..."
timeout 15 grdctl status || echo "Warning: Could not verify status"

echo "Restarting GNOME Remote Desktop service to apply all settings..."
systemctl --user restart gnome-remote-desktop.service
sleep 3

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