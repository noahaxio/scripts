#!/bin/bash

# ==============================================================================
# GNOME Remote Desktop (RDP) Headless Setup Script for Wayland
# ==============================================================================

# 1. Set your desired RDP credentials here
RDP_USER="debix"
RDP_PASS="debix"

echo "Starting headless RDP setup for $USER..."

# Ensure the script is NOT run as root (grdctl is a user-level service)
if [ "$EUID" -eq 0 ]; then
  echo "Error: Do not run this script with sudo. Run it as your normal user."
  exit 1
fi

# 2. Stop running services that might interfere
echo "Stopping GNOME Remote Desktop and Keyring daemon..."
systemctl --user stop gnome-remote-desktop.service
killall -9 gnome-keyring-daemon 2>/dev/null

# 3. Generate TLS Certificates with absolute paths
echo "Generating TLS Certificates..."
CERT_DIR="$HOME"
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
  -subj "/O=Debix/CN=$(hostname)" \
  -keyout "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" 2>/dev/null

# 4. Handle the GNOME Keyring (Inject unencrypted keyring to bypass GUI prompts)
if [ ! -f "$HOME/.local/share/keyrings/login.keyring" ]; then
  echo "Setting up GNOME Keyring to prevent headless hangs..."
  mkdir -p "$HOME/.local/share/keyrings"

  cat <<EOF > "$HOME/.local/share/keyrings/login.keyring"
[keyring]
display-name=login
ctime=0
mtime=0
lock-on-idle=false
lock-after=false
EOF

  echo "login" > "$HOME/.local/share/keyrings/default"
else
  echo "GNOME Keyring already exists, reusing it."
fi

# 5. Export session variables so the terminal can talk to the graphical bus
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# 6. Configure grdctl
echo "Configuring GNOME Remote Desktop..."
grdctl vnc disable
grdctl rdp set-tls-key "$CERT_DIR/tls.key"
grdctl rdp set-tls-cert "$CERT_DIR/tls.crt"
grdctl rdp set-credentials "$RDP_USER" "$RDP_PASS"
grdctl rdp disable-view-only
grdctl rdp enable

# 7. Restart the service to apply everything
echo "Restarting services..."
systemctl --user restart gnome-remote-desktop.service
sleep 2

# 8. Enable the service to start on boot
echo "Enabling GNOME Remote Desktop to start on boot..."
systemctl --user enable gnome-remote-desktop.service

echo "Setup Complete! Current Status:"
echo "------------------------------------------------"
grdctl status
echo "------------------------------------------------"
echo "You can now connect to this device via Windows Remote Desktop."
echo ""
echo "Note: For the service to start automatically on system boot (even without user login),"
echo "run the following command as root or with sudo:"
echo "  sudo loginctl enable-linger $USER"