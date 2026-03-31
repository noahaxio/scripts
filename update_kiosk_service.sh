#!/bin/bash

# Ensure script is run with sudo privileges
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

echo "Checking for existing Kiosk Browser Watchdog..."

# Execute as the debix user to maintain correct permissions
sudo -H -u debix bash << 'EOF'
export HOME=/home/debix
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

SERVICE_FILE="$HOME/.config/systemd/user/kiosk.service"

if [ -f "$SERVICE_FILE" ]; then
    echo "Found existing kiosk.service. Patching to prevent headless crash loops..."
    
    # Overwrite the existing file with the new display-aware version
    cat > "$SERVICE_FILE" << 'INNER_EOF'
[Unit]
Description=Kiosk Browser Watchdog
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'if grep -q "^connected" /sys/class/drm/card*-*/status 2>/dev/null; then exec /usr/bin/chromium --kiosk --password-store=basic --noerrdialogs --disable-infobars --incognito --enable-features=UseOzonePlatform --ozone-platform=wayland --disable-crash-reporter --no-crash-upload --disk-cache-dir=/dev/null "http://localhost:1880/dashboard"; else echo "No display attached. Skipping Chromium launch."; sleep 30; exit 0; fi'
KillMode=mixed
ExecStopPost=-/usr/bin/killall -9 chromium
Restart=always
RestartSec=15
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0

[Install]
WantedBy=graphical-session.target
INNER_EOF

    echo "Reloading systemd user daemon..."
    systemctl --user daemon-reload
    
    echo "Restarting kiosk.service..."
    systemctl --user restart kiosk.service
    
    # Optional cleanup of the massive Chromium cache if it exists
    CHROMIUM_DIR="$HOME/.config/chromium"
    if [ -d "$CHROMIUM_DIR" ]; then
        echo "Clearing out bloated Chromium config/crash dump directory..."
        rm -rf "$CHROMIUM_DIR"
    fi
    
    echo "Update complete. The watchdog is now Wayland and headless-safe."
else
    echo "kiosk.service not found on this machine at $SERVICE_FILE. No update required."
fi
EOF