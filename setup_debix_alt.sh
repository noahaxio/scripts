#!/bin/bash
# setup_debix_alt.sh — optimised variant of setup_debix.sh
# Changes vs original: strict mode + guards, consolidated apt, Node LTS, fixed
# Node-RED start/settings/restart ordering, npm install location + dedupe,
# InfluxData key hygiene, Tailscale up-before-funnel. Original left untouched.

if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

set -euo pipefail

# --- Shared vars (single definition, hoisted to top) ---
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
NODE_RED_DIR="$REAL_HOME/.node-red"
SETTINGS_FILE="$NODE_RED_DIR/settings.js"
DEVICE_NAME_FILE="/etc/axio-device-name"

# --- Device name ---
if [ -s "$DEVICE_NAME_FILE" ]; then
  PRECURSOR=$(cat "$DEVICE_NAME_FILE")
  echo "Found existing device name: $PRECURSOR"
else
  read -p $'What goes before .axioenergy.co: / tailscale name / cockpit name: \n' PRECURSOR
  PRECURSOR=$(echo "$PRECURSOR" | tr '[:upper:]' '[:lower:]')
  echo "$PRECURSOR" | tee "$DEVICE_NAME_FILE" > /dev/null
fi

echo "=== Debix Setup Script Starting ==="

echo "Step: Setting correct timezone..."
ln -sf /usr/share/zoneinfo/Africa/Johannesburg /etc/localtime

# --- 1. Update + base packages (single update + single install) ---
echo "Updating and upgrading packages..."
apt-get update -y
apt-get upgrade -y

echo "Installing base packages (one shot)..."
# Everything available from the default Debian repos. Third-party-repo packages
# (nodejs, influxdb2) are installed separately after their repos are added.
# Includes canvas build deps (build-essential + lib*-dev) and nginx/cron so the
# later sections only need to *configure* them.
apt-get install -y \
  curl git cockpit mbpoll micro vnstat nmap ncdu nano speedtest-cli \
  jq unzip wget cron nginx \
  build-essential libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev

# --- 2. Tailscale (own repo via install script) ---
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# --- 3. Node.js (LTS channel) ---
echo "Installing Node.js (LTS)..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
apt-get install -y nodejs

# --- 4. Node-RED (global) ---
echo "Installing Node-RED globally..."
npm install -g --unsafe-perm node-red
npm install -g npm-check-updates

# --- 5. Cockpit pretty hostname ---
echo "Setting Cockpit pretty hostname..."
echo "PRETTY_HOSTNAME=\"$PRECURSOR\"" > /etc/machine-info
systemctl restart systemd-hostnamed

# --- 6. Node-RED autostart service ---
echo "Setting up Node-RED systemd service..."
bash -c 'cat <<EOF >/etc/systemd/system/nodered.service
[Unit]
Description=Node-RED
After=network.target

[Service]
ExecStart=/usr/bin/env node-red
WorkingDirectory=/home/debix/
User=debix
Group=debix
Nice=10
Environment="NODE_OPTIONS=--max_old_space_size=256"
KillSignal=SIGINT
Restart=on-failure
SyslogIdentifier=Node-RED

[Install]
WantedBy=multi-user.target
EOF'

systemctl daemon-reload
systemctl enable nodered.service
# Start first so Node-RED generates ~/.node-red/settings.js before we patch it.
systemctl start nodered.service

echo "Waiting for Node-RED to create settings.js..."
for i in {1..30}; do
    if [ -f "$SETTINGS_FILE" ]; then break; fi
    sleep 1
done

# --- 7. NPM packages ---
# Main packages live in $REAL_HOME so external scripts/Renderers can resolve them.
echo "Installing main npm packages in $REAL_HOME..."
cd "$REAL_HOME"
MAIN_PACKAGES=(
    "@flowfuse/node-red-dashboard"
    "@napi-rs/canvas"
    "@platmac/node-red-pdfbuilder"
    "canvas"
    "chart.js"
    "chartjs-adapter-date-fns"
    "chartjs-adapter-moment"
    "chartjs-node-canvas"
    "chartjs-plugin-zoom"
    "date-fns"
    "moment"
    "node-red-contrib-boolean-logic-ultimate"
    "node-red-contrib-cpu"
    "node-red-contrib-fs-ops"
    "node-red-contrib-influxdb"
    "node-red-contrib-modbus"
    "node-red-contrib-os"
    "node-red-contrib-pdfmake"
    "node-red-contrib-unit-converter"
    "node-red-node-email"
)
if ! npm install "${MAIN_PACKAGES[@]}"; then
    echo "Error: Failed to install main npm packages." >&2
    exit 1
fi
echo "Main packages installed."

# Node-RED runtime packages live in ~/.node-red.
echo "Installing Node-RED packages in $NODE_RED_DIR..."
mkdir -p "$NODE_RED_DIR"
cd "$NODE_RED_DIR"
NODE_RED_PACKAGES=(
    "@flowfuse/node-red-dashboard"
    "@platmac/node-red-pdfbuilder"
    "@mschaeffler/node-red-tcping"
    "node-red-contrib-boolean-logic-ultimate"
    "node-red-contrib-cpu"
    "node-red-contrib-fs-ops"
    "node-red-contrib-influxdb"
    "node-red-contrib-modbus"
    "node-red-contrib-os"
    "node-red-contrib-pdfmake"
    "node-red-contrib-unit-converter"
    "node-red-node-email"
    "nodemailer"
    "node-red-contrib-socketcan"
    "chartjs-node-canvas"
    "node-red-contrib-oauth2"
)
if ! npm install "${NODE_RED_PACKAGES[@]}"; then
    echo "Error: Failed to install Node-RED npm packages." >&2
    exit 1
fi
echo "Node-RED packages installed."

# --- 8. Patch settings.js (projects + fs + nodemailer) in one place ---
echo "Patching Node-RED settings.js (projects, fs, nodemailer)..."
if [ -f "$SETTINGS_FILE" ]; then
    # Enable Projects feature (inside the projects: { ... } block only)
    sed -i '/projects: {/,/enabled: false/s/enabled: false/enabled: true/' "$SETTINGS_FILE"
    echo "Projects feature enabled."

    if ! grep -q "fs: require('fs')" "$SETTINGS_FILE"; then
        sed -i "0,/^[[:space:]]*functionGlobalContext: {/s/functionGlobalContext: {/functionGlobalContext: {\n        fs: require('fs'),/" "$SETTINGS_FILE"
        echo "Inserted fs: require('fs')."
    else
        echo "fs already present, skipping."
    fi

    if ! grep -q "nodemailer: require('nodemailer')" "$SETTINGS_FILE"; then
        sed -i "0,/^[[:space:]]*functionGlobalContext: {/s/functionGlobalContext: {/functionGlobalContext: {\n        nodemailer: require('nodemailer'),/" "$SETTINGS_FILE"
        echo "Inserted nodemailer: require('nodemailer')."
    else
        echo "nodemailer already present, skipping."
    fi
else
    echo "WARNING: $SETTINGS_FILE not found after Node-RED start; skipping settings patch." >&2
fi

# --- 9. Hide Dashboard 2 offline-ready notification ---
echo "Disabling Dashboard 2 offline ready notification..."
DASHBOARD2_DIR="$NODE_RED_DIR/node_modules/@flowfuse/node-red-dashboard"
DASHBOARD2_DIST="$DASHBOARD2_DIR/dist"
if [ -d "$DASHBOARD2_DIR" ] && [ -d "$DASHBOARD2_DIST" ]; then
    PATCH_FILE="$DASHBOARD2_DIST/index.html"
    if [ -f "$PATCH_FILE" ]; then
        # Guard string lives inside the injected comment so re-runs are idempotent.
        if ! grep -q "disable-offline-notification" "$PATCH_FILE"; then
            sed -i '/<\/head>/i\    <style>\n      /* disable-offline-notification: hide offline-ready notice, keep PWA */\n      [role="alert"] { display: none !important; }\n      .offline-notification { display: none !important; }\n    </style>' "$PATCH_FILE"
            echo "CSS patch applied to hide notifications."
        else
            echo "Notification hiding CSS already exists."
        fi
    else
        echo "WARNING: index.html not found at $PATCH_FILE"
    fi
fi

# --- 10. Fix ownership, then restart so patched settings + nodes load now ---
chown -R debix:debix "$NODE_RED_DIR"
echo "Restarting Node-RED to load patched settings and new nodes..."
systemctl restart nodered.service

# --- 11. Pull backend graphs / scripts / renderers ---
echo "Configuring git and pulling repos..."
git config --global user.email "noahg@axioenergy.co"
git config --global user.name "noahg"

echo "Setting up Scripts directory for user: $REAL_USER..."
mkdir -p "$REAL_HOME/Scripts"
cd "$REAL_HOME/Scripts" || exit
if [ -d ".git" ]; then
    echo "Scripts repo exists. Pulling latest..."
    sudo -u "$REAL_USER" git pull || true
else
    sudo -u "$REAL_USER" git clone https://github.com/noahaxio/scripts .
fi
chmod +x *
chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Scripts"

echo "Setting up Renderers directory for user: $REAL_USER..."
mkdir -p "$REAL_HOME/Renderers"
cd "$REAL_HOME/Renderers" || exit
if [ -d ".git" ]; then
    echo "Renderers repo exists. Pulling latest..."
    sudo -u "$REAL_USER" git pull || true
else
    sudo -u "$REAL_USER" git clone https://github.com/noahaxio/renderers .
fi
chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Renderers"
echo "Renderers synced."

# --- 12. InfluxDB 2 (verified key, tmp download, cleaned up) ---
echo "Installing InfluxDB 2..."
mkdir -p /etc/apt/keyrings
curl -fsSL -o /tmp/influxdata-archive.key https://repos.influxdata.com/influxdata-archive.key
if gpg --show-keys --with-fingerprint --with-colons /tmp/influxdata-archive.key 2>&1 \
   | grep -q '^fpr:\+24C975CBA61A024EE1B631787C3D57159FC2F927:$'; then
    gpg --dearmor < /tmp/influxdata-archive.key | tee /etc/apt/keyrings/influxdata-archive.gpg > /dev/null
    echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' \
        | tee /etc/apt/sources.list.d/influxdata.list > /dev/null
    apt-get update
    apt-get install -y influxdb2
    echo "InfluxDB 2 installation complete."
else
    echo "WARNING: InfluxData key fingerprint mismatch — skipping InfluxDB install." >&2
fi
rm -f /tmp/influxdata-archive.key

# --- 13. GNOME 'no-overview' (fix desktop zoom on startup) ---
# Runs in a child shell (no parent set -e); guarded so failures don't abort the run.
echo "Installing GNOME 'no-overview' extension..."
sudo -H -u debix bash <<'EOF' || true
export HOME=/home/debix
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DISPLAY=:0

rm -rf ~/.local/share/gnome-shell/extensions/no-overview@fthx
mkdir -p ~/.local/share/gnome-shell/extensions/no-overview@fthx

wget -qO /tmp/ext.zip "https://extensions.gnome.org/extension-data/no-overviewfthx.v13.shell-extension.zip"
unzip -q /tmp/ext.zip -d ~/.local/share/gnome-shell/extensions/no-overview@fthx
rm -f /tmp/ext.zip

gsettings set org.gnome.shell disable-user-extensions false
CURRENT_EXT=$(gsettings get org.gnome.shell enabled-extensions)
if [[ "$CURRENT_EXT" != *"no-overview@fthx"* ]]; then
  if [ "$CURRENT_EXT" = "@as []" ]; then
    gsettings set org.gnome.shell enabled-extensions "['no-overview@fthx']"
  else
    NEW_EXT=$(echo $CURRENT_EXT | sed "s/]/, 'no-overview@fthx']/")
    gsettings set org.gnome.shell enabled-extensions "$NEW_EXT"
  fi
  echo "Success: 'no-overview@fthx' enabled."
else
  echo "Notice: 'no-overview@fthx' already enabled."
fi
EOF

# --- 14. restartdesktop alias ---
echo "Adding restartdesktop alias..."
sudo -u debix bash <<'EOF' || true
TARGET_FILE="$HOME/.bashrc"
ALIAS_NAME="restartdesktop"
ALIAS_CMD="sudo systemctl restart gdm"
if grep -q "alias $ALIAS_NAME=" "$TARGET_FILE"; then
    echo "Alias '$ALIAS_NAME' already exists."
else
    echo "" >> "$TARGET_FILE"
    echo "# Custom alias to restart GNOME Wayland" >> "$TARGET_FILE"
    echo "alias $ALIAS_NAME=\"$ALIAS_CMD\"" >> "$TARGET_FILE"
    echo "Added '$ALIAS_NAME'."
fi
EOF

# --- 15. Nginx Cloudflare proxy (binary already installed above) ---
echo "Configuring Nginx..."
systemctl start nginx

echo "Creating /etc/nginx/sites-available/cloudflare-proxy..."
tee /etc/nginx/sites-available/cloudflare-proxy > /dev/null << EOF
server {
    listen 1881;
    server_name $PRECURSOR.axioenergy.co;

	location = / {
		rewrite ^ /dashboard last;
	}

	location / {
		proxy_pass http://localhost:1880;
	}
}
EOF

ln -sf /etc/nginx/sites-available/cloudflare-proxy /etc/nginx/sites-enabled/cloudflare-proxy
echo "Testing + reloading Nginx..."
nginx -t && systemctl reload nginx || echo "WARN: nginx config test failed"
systemctl enable nginx

# --- 16. Kiosk autostart (systemd user service) ---
echo "Setting up kiosk systemd user service..."
sudo -H -u debix bash <<'EOF' || true
export HOME=/home/debix
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
SERVICE_FILE="$SYSTEMD_USER_DIR/kiosk.service"

cat > "$SERVICE_FILE" << 'INNER_EOF'
[Unit]
Description=Kiosk Browser Watchdog
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
# Checks for a physical display connection. If true, launches Chromium with crash-reporting disabled. If false, sleeps and exits cleanly.
ExecStart=/bin/bash -c 'if grep -q "^connected" /sys/class/drm/card*-*/status 2>/dev/null; then exec /usr/bin/chromium --kiosk --password-store=basic --noerrdialogs --disable-infobars --incognito --enable-features=UseOzonePlatform --ozone-platform=wayland --disable-crash-reporter --no-crash-upload --disk-cache-dir=/dev/null "http://localhost:1880/dashboard"; else echo "No display attached. Skipping Chromium launch."; sleep 30; exit 0; fi'

KillMode=mixed
# The minus (-) tells systemd to ignore the exit code if Chromium isn't running
ExecStopPost=-/usr/bin/killall -9 chromium

Restart=always
RestartSec=15

Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0

[Install]
WantedBy=graphical-session.target
INNER_EOF

systemctl --user daemon-reload
systemctl --user enable kiosk.service
EOF

# --- 17. Daily kiosk restart via cron (cron binary already installed above) ---
echo "Setting up daily kiosk restart (3:00 AM)..."
systemctl enable cron
systemctl start cron

echo "Enabling systemd user linger for debix..."
loginctl enable-linger debix || true

echo "Installing/updating cron entry for debix (de-duplicated)..."
sudo -u debix bash <<'CRON_EOF' || true
CRON_JOB='0 3 * * * XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user restart kiosk.service'
(crontab -l 2>/dev/null | grep -vF 'systemctl --user restart kiosk.service'; echo "$CRON_JOB") | crontab -
CRON_EOF
echo "Cron job installed/updated."

# --- 18. Tailscale enable + routing + up (before funnel) ---
echo "Enabling & starting Tailscale service..."
systemctl enable tailscaled
systemctl start tailscaled

echo "Setting up Tailscale exit-node routing..."
SYSCTL_FILE="/etc/sysctl.d/99-tailscale.conf"
touch "$SYSCTL_FILE"
if ! grep -q "net.ipv4.ip_forward = 1" "$SYSCTL_FILE"; then
    echo 'net.ipv4.ip_forward = 1' | tee -a "$SYSCTL_FILE" > /dev/null
fi
if ! grep -q "net.ipv6.conf.all.forwarding = 1" "$SYSCTL_FILE"; then
    echo 'net.ipv6.conf.all.forwarding = 1' | tee -a "$SYSCTL_FILE" > /dev/null
fi
sysctl -p "$SYSCTL_FILE"

echo "You must manually authenticate Tailscale if not already logged in."
# 'up' before 'funnel' — funnel needs the node to be up. Both guarded (auth is manual/async).
tailscale up --advertise-exit-node --accept-routes --hostname="$PRECURSOR" --advertise-routes=10.0.0.0/24 || true
echo "Applying Tailscale Funnel for Node-RED port 1880..."
tailscale funnel --bg 1880 || true

echo "Autorun setup complete."

# --- 19. Cleanup ---
echo "Performing auto cleanup..."
apt-get autoremove -y
echo "Removing unused home directories..."
rm -rf "$REAL_HOME/Video" "$REAL_HOME/Videos" "$REAL_HOME/Music" "$REAL_HOME/Pictures" "$REAL_HOME/Templates"

echo "=== Setup complete! ==="
echo "Reboot recommended ('sudo reboot now'). Next: set up Node-RED projects, then Cloudflare, then the InfluxDB backup setup, and finally optionally Authelia."
#sudo reboot now
