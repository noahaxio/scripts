#!/bin/bash

# Prevent the script from being run as root/sudo because this is a user-level service
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: This script configures user-level services and must NOT be run with sudo."
    echo "Please run it as your normal user (e.g., ./update-kiosk.sh)."
    exit 1
fi

echo "=== Updating Kiosk Autostart Service ==="

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/kiosk.service"

echo "Ensuring systemd user directory exists at $SYSTEMD_USER_DIR..."
mkdir -p "$SYSTEMD_USER_DIR"

echo "Writing new kiosk service file at $SERVICE_FILE..."

cat > "$SERVICE_FILE" << 'INNER_EOF'
[Unit]
Description=Kiosk Browser Watchdog
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
# Added Ozone Wayland flags for native Wayland rendering (prevents XWayland lockups)
ExecStart=/usr/bin/chromium --kiosk --password-store=basic --noerrdialogs --disable-infobars --incognito --enable-features=UseOzonePlatform --ozone-platform=wayland "http://localhost:1880/dashboard"

# Forces systemd to send a SIGTERM to all child processes (GPU, renderers) to ensure they die
KillMode=mixed
# Optional: forcefully kill lingering processes before starting a new one
ExecStopPost=/usr/bin/killall -9 chromium

Restart=always
# Increased slightly to give GNOME time to unmap the previous window and release the GPU
RestartSec=3

Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0

[Install]
WantedBy=graphical-session.target
INNER_EOF

echo "Reloading user systemd daemon..."
systemctl --user daemon-reload

echo "Enabling kiosk service to run on startup..."
systemctl --user enable kiosk.service

echo "Restarting kiosk service to apply changes..."
systemctl --user restart kiosk.service

echo "=== Update Complete! ==="
echo "You can check the status at any time by running: systemctl --user status kiosk.service"