#!/bin/bash

echo "=== Converting Kiosk Autostart to systemd ==="

# 1. Remove the old desktop autostart entry if it exists
OLD_AUTOSTART="/etc/xdg/autostart/start-browser.desktop"

if [ -f "$OLD_AUTOSTART" ]; then
    echo "Found old autostart file at $OLD_AUTOSTART."
    echo "Removing it (you may be prompted for your sudo password)..."
    sudo rm "$OLD_AUTOSTART"
    echo "Old autostart removed."
else
    echo "Old autostart file not found. Skipping removal."
fi

# 2. Setup systemd user directory
SYSTEMD_USER_DIR="/home/debix/.config/systemd/user"
echo "Ensuring systemd user directory exists at $SYSTEMD_USER_DIR..."
mkdir -p "$SYSTEMD_USER_DIR"

# 3. Create the kiosk service file
SERVICE_FILE="$SYSTEMD_USER_DIR/kiosk.service"
echo "Creating systemd service file at $SERVICE_FILE..."

cat << 'EOF' > "$SERVICE_FILE"
[Unit]
Description=Kiosk Browser Watchdog
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
# Using chromium here, but change to google-chrome if that's what is installed
ExecStart=/usr/bin/chromium --kiosk --password-store=basic --noerrdialogs --disable-infobars --incognito "http://localhost:1880/dashboard"
Restart=always
RestartSec=5
Environment=DISPLAY=:0

[Install]
WantedBy=graphical-session.target
EOF

# 4. Reload, enable, and start the new service
echo "Reloading user systemd daemon..."
systemctl --user daemon-reload

echo "Enabling kiosk service to run on startup..."
systemctl --user enable kiosk.service

echo "Starting kiosk service..."
systemctl --user restart kiosk.service

echo "=== Migration Complete! ==="