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
STATIC_HOSTNAME="Axio-BlackBox-EMS"

# --- Authelia admin account (placeholders — edit before running on a fleet;
# avoid committing the real password to git) ---
AUTHELIA_ADMIN_USER="admin"
AUTHELIA_ADMIN_PASSWORD="CHANGE_ME"
AUTHELIA_ADMIN_EMAIL="noah@axioenergy.co"

# --- Node-RED editor admin account (guards the editor + admin API on :1880, which
# `tailscale funnel` publishes to the internet further down) ---
NODERED_ADMIN_USER="admin"
NODERED_ADMIN_PASSWORD="CHANGE_ME"
# Flipped to 1 once adminAuth actually lands in settings.js; reported in the final summary.
NODERED_AUTH_OK=0

# Checked up-front (not at the Authelia/Node-RED steps further down) so a forgotten
# password fails in seconds rather than after the full install.
if [ "$AUTHELIA_ADMIN_PASSWORD" = "CHANGE_ME" ]; then
  echo "Error: AUTHELIA_ADMIN_PASSWORD is still the placeholder value. Edit it at the top of this script before running." >&2
  exit 1
fi
if [ "$NODERED_ADMIN_PASSWORD" = "CHANGE_ME" ]; then
  echo "Error: NODERED_ADMIN_PASSWORD is still the placeholder value. Edit it at the top of this script before running." >&2
  exit 1
fi
# The username is written verbatim into a JS string literal in settings.js.
if [[ "$NODERED_ADMIN_USER" == *'"'* || "$NODERED_ADMIN_USER" == *'\'* ]]; then
  echo 'Error: NODERED_ADMIN_USER cannot contain a double-quote (") or a backslash (\).' >&2
  exit 1
fi

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
npm install -g --unsafe-perm node-red --verbose
npm install -g npm-check-updates

# --- 5. Hostname: static (/etc/hostname) + Cockpit pretty hostname ---
echo "Setting static hostname to $STATIC_HOSTNAME (network-visible, same on all boxes)..."
# Write /etc/hostname directly and set the running name via the classic `hostname`
# command. We deliberately avoid `hostnamectl set-hostname`, which also rewrites the
# pretty hostname in /etc/machine-info (the Cockpit name) and needs polkit — this keeps
# the per-device Cockpit/Tailscale names ($PRECURSOR) untouched.
echo "$STATIC_HOSTNAME" > /etc/hostname
hostname "$STATIC_HOSTNAME"
# Keep the 127.0.1.1 mapping in /etc/hosts in sync so sudo can always resolve the host.
if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    sed -i -E "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t$STATIC_HOSTNAME/" /etc/hosts
else
    printf '127.0.1.1\t%s\n' "$STATIC_HOSTNAME" >> /etc/hosts
fi

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
    # Not a Node-RED node - it hashes the admin password in section 8 below.
    "bcryptjs"
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

    # --- Node-RED editor login (adminAuth) ---
    # Stands in for `node-red admin hash-pw`, which only exists to prompt on a TTY (hence
    # the pexpect dance in the old ansible playbook). All it does is bcrypt.hashSync(pw, 8),
    # so we call that directly. Password goes via the environment, never argv, so it
    # cannot be read out of `ps`.
    echo "Configuring Node-RED admin authentication..."
    NODERED_HASH=$(NR_PW="$NODERED_ADMIN_PASSWORD" NODE_PATH="$NODE_RED_DIR/node_modules" \
        node -e 'console.log(require("bcryptjs").hashSync(process.env.NR_PW, 8))' 2>/dev/null) || true

    BCRYPT_RE='^\$2[aby]\$[0-9]{2}\$[A-Za-z0-9./]{53}$'
    if [[ ! "$NODERED_HASH" =~ $BCRYPT_RE ]]; then
        echo "############################################################" >&2
        echo "WARNING: could not generate a valid bcrypt hash (is bcryptjs installed in $NODE_RED_DIR?)." >&2
        echo "Node-RED adminAuth NOT applied - the editor on :1880 is UNPROTECTED." >&2
        echo "############################################################" >&2
    else
        cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak.$(date +%Y%m%d%H%M%S)"
        # Matches the adminAuth block whether it is the stock commented-out one or a live
        # block from an earlier run, so re-running this script rotates the credentials.
        # Anchored on the block's real terminator - a "}]" line followed by a "}," line,
        # each optionally //-prefixed. A lazy `.*?` hunt for that pair (as the ansible
        # playbook did) overshoots the end of the block and swallows unrelated settings.
        NR_USER="$NODERED_ADMIN_USER" NR_HASH="$NODERED_HASH" perl -0777 -i -pe '
            BEGIN { $u = $ENV{NR_USER}; $h = $ENV{NR_HASH} }
            s{^([ \t]*)(?://[ \t]*)?adminAuth:[ \t]*\{[^\n]*\n(?:[^\n]*\n)*?[ \t]*(?://[ \t]*)?\}\][ \t]*\r?\n[ \t]*(?://[ \t]*)?\},?[ \t]*\r?\n}
             {qq{$1adminAuth: \{\n$1    type: "credentials",\n$1    users: [\{\n$1        username: "$u",\n$1        password: "$h",\n$1        permissions: "*"\n$1    \}]\n$1\},\n}}me;
        ' "$SETTINGS_FILE" || true

        # The hash is freshly generated, so finding it proves *this* run wrote the block;
        # the second grep proves the block is live rather than still commented out.
        if grep -qF "$NODERED_HASH" "$SETTINGS_FILE" && grep -qE '^[ \t]*adminAuth:[ \t]*\{' "$SETTINGS_FILE"; then
            NODERED_AUTH_OK=1
            echo "Node-RED adminAuth configured for user '$NODERED_ADMIN_USER'."
        else
            echo "############################################################" >&2
            echo "WARNING: no adminAuth block was patched in $SETTINGS_FILE." >&2
            echo "Node-RED adminAuth NOT applied - the editor on :1880 is UNPROTECTED." >&2
            echo "############################################################" >&2
        fi
    fi

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
chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/Scripts"
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
chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/Renderers"
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

# --- 13b. GNOME single workspace (disable multi-finger swipe desktop switching) ---
# Forces one static workspace so touchscreen swipes have nowhere to go, and
# disables hot corners. Permanent fix is the gnome-kiosk package (see TODO_gnome_kiosk.txt).
echo "Forcing single GNOME workspace + disabling hot corners..."
sudo -H -u debix bash <<'EOF' || true
export HOME=/home/debix
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 1
gsettings set org.gnome.desktop.interface enable-hot-corners false
echo "Workspace/gesture settings applied."
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

# --- 15. Kiosk autostart (systemd user service) ---
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
# Remove any stale Chromium profile lock left by a prior unclean kill (killall -9 /
# session teardown) so it can't trip the "profile appears to be in use" dialog on next launch.
ExecStartPre=/bin/bash -c 'rm -f /home/debix/.config/chromium/Singleton*'
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

# --- 16. Daily kiosk restart via cron (cron binary already installed above) ---
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

# --- 17. Tailscale enable + routing + up (before funnel) ---
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

# --- 18. Authelia + Nginx (auth-gated reverse proxy in front of Node-RED) ---
# Runs last (after Tailscale) on purpose, mirroring the proven manual order where
# authelia_setup.sh was run *after* setup_debix.sh finished:
#  - Docker sets the iptables FORWARD policy to DROP on install; bringing Tailscale
#    up first keeps exit-node/subnet-route forwarding working.
#  - Under `set -e`, an Authelia failure here can no longer abort the run before
#    `tailscale up`, so a remote box always stays reachable to fix it.
echo "Setting up Authelia..."

echo "Ensuring Nginx is running..."
systemctl start nginx

if ! command -v docker &> /dev/null; then
  echo "--> Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
  echo "--> Docker installed successfully."
else
  echo "--> Docker is already installed. Skipping."
fi

echo "--> Ensuring iptables uses the nftables backend (required for Docker on this kernel)..."
update-alternatives --set iptables /usr/sbin/iptables-nft || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft || true
if systemctl is-active --quiet docker; then
  echo "--> Restarting Docker to apply networking changes..."
  systemctl restart docker
fi

echo "--> Pulling Authelia image and generating Argon2 hash..."
docker pull authelia/authelia:latest > /dev/null
RAW_HASH_OUTPUT=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$AUTHELIA_ADMIN_PASSWORD")
ADMIN_HASH=$(echo "$RAW_HASH_OUTPUT" | awk '/Digest:/ {print $2}' | tr -d '\r')
if [ -z "$ADMIN_HASH" ]; then
    echo "Error: Failed to extract password hash. Raw output was: $RAW_HASH_OUTPUT" >&2
    exit 1
fi
echo "--> Hash generated successfully."

echo "--> Setting up Authelia files in /opt/authelia..."
mkdir -p /opt/authelia
cd /opt/authelia

cat << 'EOF' > docker-compose.yml
version: '3.8'
services:
  authelia:
    image: authelia/authelia:latest
    container_name: authelia
    restart: unless-stopped
    volumes:
      - ./:/config
    ports:
      - "9091:9091"
    environment:
      - TZ=Africa/Johannesburg
  redis:
    image: redis:alpine
    container_name: authelia_redis
    restart: unless-stopped
EOF

cat << EOF > users_database.yml
users:
  $AUTHELIA_ADMIN_USER:
    displayname: "Admin User"
    email: "$AUTHELIA_ADMIN_EMAIL"
    password: "$ADMIN_HASH"
    groups:
      - admins
EOF

cat << EOF > configuration.yml
server:
  address: 'tcp://0.0.0.0:9091'

authentication_backend:
  file:
    path: /config/users_database.yml

access_control:
  default_policy: deny
  rules:
    - domain: "auth-${PRECURSOR}.axioenergy.co"
      policy: bypass
    - domain: "${PRECURSOR}.axioenergy.co"
      policy: one_factor

session:
  name: authelia_session
  domain: axioenergy.co
  expiration: 2h
  inactivity: 15m
  secret: 'super_secret_session_key_change_me'
  redis:
    host: authelia_redis
    port: 6379

storage:
  encryption_key: 'super_secret_storage_key_change_me'
  local:
    path: /config/db.sqlite3

notifier:
  filesystem:
    filename: /config/notification.txt

identity_validation:
  reset_password:
    jwt_secret: 'super_secret_jwt_key_change_me'
EOF

echo "--> Configuring Nginx..."
# Remove old plain (unauthenticated) proxy config from earlier runs of this script.
rm -f /etc/nginx/sites-available/cloudflare-proxy
rm -f /etc/nginx/sites-enabled/cloudflare-proxy

cat << EOF > /etc/nginx/sites-available/$PRECURSOR
# 1. The Login Portal
server {
    listen 1881;
    server_name auth-${PRECURSOR}.axioenergy.co;

    location / {
        proxy_pass http://127.0.0.1:9091;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# 2. The Protected App
server {
    listen 1881;
    server_name ${PRECURSOR}.axioenergy.co;

    location = / {
        rewrite ^ /dashboard last;
    }

    location / {
        auth_request /auth_verify;
        error_page 401 = @authelia_redirect;

        proxy_pass http://127.0.0.1:1880;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location = /auth_verify {
        internal;
        proxy_pass http://127.0.0.1:9091/api/verify;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI \$request_uri;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location @authelia_redirect {
        return 302 https://auth-${PRECURSOR}.axioenergy.co/?rd=https://\$http_host\$request_uri;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$PRECURSOR /etc/nginx/sites-enabled/
echo "Testing + reloading Nginx..."
nginx -t && systemctl reload nginx || echo "WARN: nginx config test failed"
systemctl enable nginx

echo "--> Starting Authelia containers..."
cd /opt/authelia
if docker compose version &> /dev/null; then
  docker compose up -d
else
  docker-compose up -d
fi
echo "--> Authelia and Redis are up."

# --- 19. Cleanup ---
echo "Performing auto cleanup..."
apt-get autoremove -y
echo "Removing unused home directories..."
rm -rf "$REAL_HOME/Video" "$REAL_HOME/Videos" "$REAL_HOME/Music" "$REAL_HOME/Pictures" "$REAL_HOME/Templates"

echo "=== Setup complete! ==="
echo "Reboot recommended ('sudo reboot now'). Next: set up Node-RED projects, then Cloudflare, then the InfluxDB backup setup."
echo "Authelia is live — remember to add auth-${PRECURSOR}.axioenergy.co and ${PRECURSOR}.axioenergy.co to Cloudflare."
if [ "$NODERED_AUTH_OK" -eq 1 ]; then
  echo "Node-RED editor login: username '$NODERED_ADMIN_USER' (adminAuth active on :1880)."
else
  echo "WARNING: Node-RED adminAuth was NOT applied — the editor on :1880 is UNPROTECTED. Scroll up for the reason." >&2
fi
#sudo reboot now
