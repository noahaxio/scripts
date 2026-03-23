#!/bin/bash
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

#set -e

DEVICE_NAME_FILE="/etc/axio-device-name"

# Check if the device name file already exists and is not empty
if [ -s "$DEVICE_NAME_FILE" ]; then
  # Read the existing value directly from the file
  PRECURSOR=$(cat "$DEVICE_NAME_FILE")
  echo "Found existing device name: $PRECURSOR"
else
  # File doesn't exist, prompt the user for the name
  read -p $'What goes before .axioenergy.co: / tailscale name / cockpit name: \n' PRECURSOR
  
  # Save the variable to a file so other scripts can read it later
  echo "$PRECURSOR" | sudo tee "$DEVICE_NAME_FILE" > /dev/null
fi

echo "=== Debix Setup Script Starting ==="

echo "Step Setting Correct Timezone..."
sudo ln -sf /usr/share/zoneinfo/Africa/Johannesburg /etc/localtime

# --- 1. Update & Reboot Notice ---
echo "Updating packages..."
sudo apt-get update -y

# --- 2. Install curl+git+cockpit ---
echo "Installing curl..."
sudo apt-get install -y curl

echo "Installing git..."
sudo apt-get install -y git

echo "Installing Cocopit..."
sudo apt-get install -y cockpit

echo "Installing mbpoll"
sudo apt-get install -y mbpoll

echo "Installing micro"
sudo apt-get install -y micro

echo "Installing vnstat..."
sudo apt-get install -y vnstat

echo "Installing nmap..."
sudo apt-get install -y nmap

# --- 3. Install Tailscale ---
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# --- 3.2 ---
echo "Installing Speedest..."
sudo apt install speedtest-cli

# --- 4. Upgrade & Install Node.js ---
echo "Upgrading system and installing Node.js..."
sudo apt-get upgrade -y

curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash
sudo apt-get install -y nodejs

# --- 5. Install Node-RED ---
echo "Installing Node-RED globally..."
sudo npm install -g --unsafe-perm node-red
sudo npm install -g npm-check-updates

# --- 6.5 Setting cockpit system name
echo "PRETTY_HOSTNAME=\"$PRECURSOR\"" > /etc/machine-info
systemctl restart systemd-hostnamed

# --- 7. Install nano ---
echo "Installing nano..."
sudo apt-get install -y nano

# --- Node-RED Autostart (systemd service) ---
echo "Setting up Node-RED to start automatically..."

sudo bash -c 'cat <<EOF >/etc/systemd/system/nodered.service
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

echo "Enabling Node-RED Projects..."
SETTINGS_FILE="/home/debix/.node-red/settings.js"
if [ -f "$SETTINGS_FILE" ]; then
    # Look for the block starting with 'projects: {' and ending with 'enabled: false'
    # Then replace 'enabled: false' with 'enabled: true' inside that block only.
    sudo sed -i '/projects: {/,/enabled: false/s/enabled: false/enabled: true/' "$SETTINGS_FILE"
    
    echo "Projects feature enabled in settings.js."
else
    echo "WARNING: $SETTINGS_FILE not found. Skipping Projects enable."
fi

sudo systemctl daemon-reload
sudo systemctl enable nodered.service
sudo systemctl start nodered.service

# --- Script to install the LATEST version of specified NPM packages and Node-RED modules ---
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

# 1. Install system dependencies for 'canvas' (Required for Chart.js rendering)
echo "## 1. Installing required system dependencies for 'canvas'..."
# Assuming a Debian-based system (like Debian, Ubuntu, or the debix distribution mentioned)
if command -v apt &> /dev/null; then
    echo "Updating package list and installing dependencies..."
    sudo apt update
    # These dependencies are required for node-gyp to compile canvas, which is needed by @napi-rs/canvas as a fallback or if not using the prebuilt binary.
    sudo apt install -y build-essential libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev
    echo "System dependencies installed successfully."
else
    echo "Warning: 'apt' command not found. Skipping system dependency installation. Please install required libraries manually if installation fails."
fi

echo "---"

# 2. Install global/main npm packages (LATEST versions)
echo "## 2. Installing main npm packages (latest versions)..."

# List of the first set of packages - version numbers removed
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
	"chartjs-node-canvas"
)

# Install packages
npm install "${MAIN_PACKAGES[@]}"
INSTALL_STATUS_MAIN=$?

if [ $INSTALL_STATUS_MAIN -eq 0 ]; then
    echo "Main packages installed successfully."
else
    echo "Error: Failed to install main npm packages (Exit code: $INSTALL_STATUS_MAIN)."
    # Exit script on failure for critical packages
    exit 1
fi

echo "---"

# 3. Install Node-RED packages in ~/.node-red (LATEST versions)
echo "## 3. Installing Node-RED packages (latest versions) in ~/.node-red..."

# Define the Node-RED directory
NODE_RED_DIR="$REAL_HOME/.node-red"

# Create the directory if it doesn't exist (e.g., if Node-RED hasn't been run yet)
if [ ! -d "$NODE_RED_DIR" ]; then
    echo "Creating Node-RED directory: $NODE_RED_DIR"
    mkdir -p "$NODE_RED_DIR"
fi

# Change directory to the Node-RED project folder
cd "$NODE_RED_DIR"
echo "Changed directory to: $PWD"

# List of Node-RED packages - version numbers removed
NODE_RED_PACKAGES=(
    "@flowfuse/node-red-dashboard"
    "@platmac/node-red-pdfbuilder"
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

# Install Node-RED packages
npm install "${NODE_RED_PACKAGES[@]}"
INSTALL_STATUS_NODERED=$?

# Return to the original directory (optional, but good practice)
cd - > /dev/null

if [ $INSTALL_STATUS_NODERED -eq 0 ]; then
    echo "Node-RED packages installed successfully (latest versions) in ~/.node-red."
else
    echo "Error: Failed to install Node-RED npm packages (Exit code: $INSTALL_STATUS_NODERED)."
    exit 1
fi

echo "Patching Node-RED settings.js to add fs and nodemailer..."
SETTINGS_FILE="/home/debix/.node-red/settings.js"

if [ -f "$SETTINGS_FILE" ]; then
    # Check and inject 'fs'
    if ! sudo grep -q "fs: require('fs')" "$SETTINGS_FILE"; then
        sudo sed -i "/functionGlobalContext: {/a\        fs: require('fs')," "$SETTINGS_FILE"
        echo "Inserted fs: require('fs') into functionGlobalContext."
    else
        echo "fs already exists in settings.js, skipping."
    fi

    # Check and inject 'nodemailer'
    if ! sudo grep -q "nodemailer: require('nodemailer')" "$SETTINGS_FILE"; then
        sudo sed -i "/functionGlobalContext: {/a\        nodemailer: require('nodemailer')," "$SETTINGS_FILE"
        echo "Inserted nodemailer: require('nodemailer') into functionGlobalContext."
    else
        echo "nodemailer already exists in settings.js, skipping."
    fi
else
    echo "WARNING: Node-RED settings.js not found at $SETTINGS_FILE"
    echo "Start Node-RED once manually so the file is created, then re-run this patch."
fi

echo "Disabling Dashboard 2 offline ready notification..."

NODE_RED_DIR="/home/debix/.node-red"
DASHBOARD2_DIR="$NODE_RED_DIR/node_modules/@flowfuse/node-red-dashboard"
DASHBOARD2_DIST="$DASHBOARD2_DIR/dist"

if [ -d "$DASHBOARD2_DIR" ] && [ -d "$DASHBOARD2_DIST" ]; then
    echo "Found Dashboard 2 at: $DASHBOARD2_DIR"
    
    PATCH_FILE="$DASHBOARD2_DIST/index.html"
    
    if [ -f "$PATCH_FILE" ]; then
        echo "Patching index.html to hide offline ready notification..."
        
        if ! grep -q "disable-offline-notification" "$PATCH_FILE"; then
            sudo sed -i '/<\/head>/i\    <style>\n      /* Hide offline ready notification while keeping PWA functionality */\n      [role="alert"] { display: none !important; }\n      .offline-notification { display: none !important; }\n    </style>' "$PATCH_FILE"
            echo "CSS patch applied to hide notifications."
        else
            echo "Notification hiding CSS already exists."
        fi
    else
        echo "WARNING: index.html not found at $PATCH_FILE"
    fi
fi

echo "pulling backend graphs from github"

git config --global user.email "noahg@axioenergy.co"
git config --global user.name "noahg"

echo "Setting up Scripts directory for user: $REAL_USER..."
mkdir -p "$REAL_HOME/Scripts"
cd "$REAL_HOME/Scripts" || exit

if [ -d ".git" ]; then
    echo "Scripts repo already exists. Pulling latest changes..."
    sudo -u "$REAL_USER" git pull
else
    sudo -u "$REAL_USER" git clone https://github.com/noahaxio/scripts .
fi

chmod +x *
chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Scripts"

echo "Setting up Renderers directory for user: $REAL_USER..."
mkdir -p "$REAL_HOME/Renderers"
cd "$REAL_HOME/Renderers" || exit

if [ -d ".git" ]; then
    echo "Renderers repo already exists. Pulling latest changes..."
    sudo -u "$REAL_USER" git pull
else
    sudo -u "$REAL_USER" git clone https://github.com/noahaxio/renderers .
fi

chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Renderers"
echo "Done. Renderers synced successfully."

echo "Dynamically adding all Renderers to Node-RED settings.js..."

RENDERERS_DIR="/home/debix/Renderers"
SETTINGS_FILE="/home/debix/.node-red/settings.js"

if [ -f "$SETTINGS_FILE" ] && [ -d "$RENDERERS_DIR" ]; then
    for filepath in "$RENDERERS_DIR"/*.js; do
        filename=$(basename "$filepath")
        basename="${filename%.*}"
        varName=$(echo "$basename" | sed -r 's/-([a-z])/\U\1/g')
        ENTRY="$varName: require(\"$filepath\"),"
        
        # Check if this specific variable is already injected
        if ! sudo grep -q "$varName: require" "$SETTINGS_FILE"; then
            sudo sed -i "/functionGlobalContext: {/a\        $ENTRY" "$SETTINGS_FILE"
            echo "  + Added $filename as global variable: $varName"
        else
            echo "  ~ $filename ($varName) is already in settings.js. Skipping."
        fi
    done
else
    echo "WARNING: Could not find Settings file or Renderers directory. Skipping dynamic injection."
fi

#ADD AUTO GIT / AUTO COMMIT USING .config.users.json and settings.js / AUTO PUSH TO GITHUB



#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

echo "Installing InfluxDB 2..."

# Add InfluxData repository signing key
curl --silent --location -O https://repos.influxdata.com/influxdata-archive.key
gpg --show-keys --with-fingerprint --with-colons ./influxdata-archive.key 2>&1 \
| grep -q '^fpr:\+24C975CBA61A024EE1B631787C3D57159FC2F927:$' \
&& cat influxdata-archive.key \
| gpg --dearmor \
| sudo tee /etc/apt/keyrings/influxdata-archive.gpg > /dev/null

# Add InfluxDB APT repository
echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' \
| sudo tee /etc/apt/sources.list.d/influxdata.list

# Install InfluxDB 2
sudo apt-get update
sudo apt-get install -y influxdb2

echo "InfluxDB 2 installation complete."

echo "fixing desktop zoom on startup"
sudo apt install -y curl jq unzip wget

# Notice the -H flag and the explicit exports
sudo -H -u debix bash << 'EOF'
export HOME=/home/debix
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DISPLAY=:0

echo "Starting GNOME 'no-overview' extension installation..."

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
  echo "Success: 'no-overview@fthx' added to enabled extensions."
else
  echo "Notice: 'no-overview@fthx' is already in the enabled list."
fi
EOF

echo "Adding restartdesktop alias for quick display manager restart..."

sudo -u debix bash << 'EOF'
TARGET_FILE="$HOME/.bashrc"
ALIAS_NAME="restartdesktop"
ALIAS_CMD="sudo systemctl restart gdm"

echo "Configuring alias '$ALIAS_NAME'..."

# Check if the alias already exists to prevent duplicates
if grep -q "alias $ALIAS_NAME=" "$TARGET_FILE"; then
    echo "Looks like the alias '$ALIAS_NAME' already exists in $TARGET_FILE."
else
    # Append the alias to the bottom of the file
    echo "" >> "$TARGET_FILE"
    echo "# Custom alias to restart GNOME Wayland" >> "$TARGET_FILE"
    echo "alias $ALIAS_NAME=\"$ALIAS_CMD\"" >> "$TARGET_FILE"
    
    echo "Successfully added '$ALIAS_NAME' to $TARGET_FILE."
fi
EOF

echo "Installing Nginx"

sudo apt install nginx -y
sudo systemctl start nginx

echo "=== Creating NGINX site file: /etc/nginx/sites-available/cloudflare-proxy ==="

sudo tee /etc/nginx/sites-available/cloudflare-proxy > /dev/null << EOF
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

echo "=== Creating symlink in /etc/nginx/sites-enabled ==="
sudo ln -sf /etc/nginx/sites-available/cloudflare-proxy /etc/nginx/sites-enabled/cloudflare-proxy

echo "=== Testing NGINX configuration ==="
sudo nginx -t

echo "=== Reloading NGINX ==="
sudo systemctl reload nginx
sudo systemctl enable nginx

echo "=== Done! ==="

echo "Setting up auto launch dashboard using systemd kiosk service"

sudo -H -u debix bash << 'EOF'
export HOME=/home/debix
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

echo "=== Converting Kiosk Autostart to systemd ==="

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
echo "Ensuring systemd user directory exists at $SYSTEMD_USER_DIR..."
mkdir -p "$SYSTEMD_USER_DIR"

SERVICE_FILE="$SYSTEMD_USER_DIR/kiosk.service"
echo "Creating systemd service file at $SERVICE_FILE..."

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
EOF

sudo chown -R debix:debix /home/debix/.node-red

# --- Daily Kiosk Restart via Cron ---
echo "=== Setting up Daily Kiosk Restart (3:00 AM) ==="

echo "Installing cron..."
sudo apt update
sudo apt install -y cron

echo "Enabling and starting the cron service..."
sudo systemctl enable cron
sudo systemctl start cron

echo "Enabling systemd user linger for debix (so kiosk restart works even when logged out)..."
sudo loginctl enable-linger debix || true

echo "Installing/updating cron entry for debix user (de-duplicated)..."
sudo -u debix bash <<'CRON_EOF'
CRON_JOB='0 3 * * * XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user restart kiosk.service'
(crontab -l 2>/dev/null | grep -vF 'systemctl --user restart kiosk.service'; echo "$CRON_JOB") | crontab -
CRON_EOF
echo "Cron job installed/updated."

# --- 6. Enable Tailscale ---
echo "Enabling & starting Tailscale service..."
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

echo "Setting up tailscale exit node routing..."
SYSCTL_FILE="/etc/sysctl.d/99-tailscale.conf"

# Ensure the sysctl file exists
sudo touch "$SYSCTL_FILE"

# Add routing rules only if they don't already exist to prevent duplicate lines
if ! grep -q "net.ipv4.ip_forward = 1" "$SYSCTL_FILE"; then
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a "$SYSCTL_FILE" > /dev/null
fi

if ! grep -q "net.ipv6.conf.all.forwarding = 1" "$SYSCTL_FILE"; then
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a "$SYSCTL_FILE" > /dev/null
fi

# Apply the network routing rules
sudo sysctl -p "$SYSCTL_FILE"

echo "Applying Tailscale Funnel and Network Settings..."
# Ensure funnel is running in the background for Node-RED port 1880
sudo tailscale funnel --bg 1880 

echo "You must manually authenticate Tailscale if not already logged in."
# Combine all state changes into a single 'up' command to prevent the non-default flags error
sudo tailscale up --advertise-exit-node --accept-routes --hostname="$PRECURSOR" --advertise-routes=10.0.0.0/24

echo "Autorun setup complete."

echo "---"
echo "All installations complete!"

echo "Performing Auto Cleanup"

sudo apt autoremove -y

echo "Removing unused home directories..."
rm -rf "$REAL_HOME/Video" "$REAL_HOME/Videos" "$REAL_HOME/Music" "$REAL_HOME/Pictures" "$REAL_HOME/Templates"

echo "=== Setup complete! ==="
echo "Reboot recomended with 'sudo reboot now, next steps would be to setup node red projects, then cloudflare, then run the influxdb backup setup and finally optionally athelia'"
#sudo reboot now

