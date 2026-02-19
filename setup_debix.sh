#!/bin/bash
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

#set -e
read -p $'What goes before .axioenergy.co: / tailscale name / cockpit name: \n' PRECURSOR

# Save the variable to a file so other scripts can read it later
echo "$PRECURSOR" | sudo tee /etc/axio-device-name > /dev/null

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
sudo apt-get install vnstat

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

echo "Patching Node-RED settings.js to add fs require..."
SETTINGS_FILE="/home/debix/.node-red/settings.js"

# Make sure the file exists (Node-RED must have run once to create it)
if [ -f "$SETTINGS_FILE" ]; then
    sudo sed -i "/functionGlobalContext: {/a\        fs: require('fs')," "$SETTINGS_FILE"
    echo "Inserted fs: require('fs') into functionGlobalContext."
else
    echo "WARNING: Node-RED settings.js not found at $SETTINGS_FILE"
    echo "Start Node-RED once manually so the file is created, then re-run this patch."
fi

echo "Adding nodemailer to Node-RED settings.js..."

if [ -f "$SETTINGS_FILE" ]; then
    sudo sed -i "/functionGlobalContext: {/a\        nodemailer: require('nodemailer')," "$SETTINGS_FILE"
    echo "Inserted nodemailer: require('nodemailer') into functionGlobalContext."
else
    echo "WARNING: Node-RED settings.js not found at $SETTINGS_FILE"
    echo "Start Node-RED once manually so the file is created, then re-run this patch."
fi

echo "pulling backend graphs from github"

git config --global user.email "noahg@axioenergy.co"
git config --global user.name "noahg"

echo "Setting up Scripts directory for user: $REAL_USER..."

# Create the Scripts directory
mkdir -p "$REAL_HOME/Scripts"

# Move into that directory
cd "$REAL_HOME/Scripts" || exit

# Clone the repository into the CURRENT directory (.)
git clone https://github.com/noahaxio/scripts .

# Make all files in the directory executable
chmod +x *

# Fix permissions so the user owns the folder and files
chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Scripts"

echo "Setting up Renderers directory for user: $REAL_USER..."

# Create the Renderers directory
mkdir -p "$REAL_HOME/Renderers"

# Move into that directory
cd "$REAL_HOME/Renderers" || exit

# Clone the repository into the CURRENT directory (.)
git clone https://github.com/noahaxio/renderers .

# Fix permissions so the user owns the folder and files
chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Renderers"

echo "Done. Renderers cloned successfully."

echo "Dynamically adding all Renderers to Node-RED settings.js..."

RENDERERS_DIR="/home/debix/Renderers"
SETTINGS_FILE="/home/debix/.node-red/settings.js"

if [ -f "$SETTINGS_FILE" ] && [ -d "$RENDERERS_DIR" ]; then
    # Loop through every .js file in the Renderers directory
    for filepath in "$RENDERERS_DIR"/*.js; do
        # 1. Get the filename (e.g., "chart-renderer.js")
        filename=$(basename "$filepath")
        
        # 2. Remove the extension to get the base name (e.g., "chart-renderer")
        basename="${filename%.*}"
        
        # 3. Convert kebab-case to camelCase (e.g., "chart-renderer" -> "chartRenderer")
        # This ensures your variable names match what you had manually before.
        varName=$(echo "$basename" | sed -r 's/-([a-z])/\U\1/g')
        
        # 4. Construct the line to insert
        # Result: chartRenderer: require("/home/debix/Renderers/chart-renderer.js"),
        ENTRY="$varName: require(\"$filepath\"),"
        
        # 5. Insert the line into settings.js
        # We search for "functionGlobalContext: {" and append the new line after it
        sudo sed -i "/functionGlobalContext: {/a\        $ENTRY" "$SETTINGS_FILE"
        
        echo "  + Added $filename as global variable: $varName"
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

echo "forcing desktop on startup"

sudo apt install -y curl jq unzip

# 2. Define the Extension ID
UUID="no-overview@fthx"

# 3. Get your GNOME Shell version
SHELL_VERSION=$(gnome-shell --version | cut -d ' ' -f 3)

# 4. Fetch the download URL for the extension
DOWNLOAD_URL=$(curl -s "https://extensions.gnome.org/extension-info/?uuid=$UUID&shell_version=$SHELL_VERSION" | jq -r '.download_url')

# 5. Download and install the extension
curl -L "https://extensions.gnome.org$DOWNLOAD_URL" -o extension.zip
gnome-extensions install extension.zip --force

# 6. Clean up
rm extension.zip

# 7. Enable the extension
gnome-extensions enable no-overview@fthx

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

echo "Setting up auto launch dashboard"

USER="debix"
AUTORUN_DIR="$REAL_HOME/Autorun"
SCRIPT_PATH="$AUTORUN_DIR/setup_browser.sh"
DESKTOP_ENTRY="/etc/xdg/autostart/start-browser.desktop"

# Create Autorun directory
mkdir -p "$AUTORUN_DIR"

# Create the browser startup script
cat <<EOF > "$SCRIPT_PATH"
#!/bin/bash
xset s noblank
xset s off
xset -dpms

sleep 10

/usr/bin/chromium --kiosk --password-store=basic --noerrdialogs --disableinforbars --incognito http://localhost:1880/dashboard
EOF

# Make the script executable
chmod +x "$SCRIPT_PATH"
chown $USER:$USER "$SCRIPT_PATH"

#ADD FULLSCREEN
# Create the desktop autostart entry
sudo bash -c "cat <<EOF > $DESKTOP_ENTRY
[Desktop Entry]
Type=Application
Exec=$SCRIPT_PATH 
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Start Browser
Comment=Open Node-RED Dashboard on Login
EOF"

# Set proper permissions
sudo chmod 644 "$DESKTOP_ENTRY"
sudo chown root:root "$DESKTOP_ENTRY"
sudo chown -R debix:debix /home/debix/.node-red

# --- 6. Enable Tailscale ---
echo "Enabling & starting Tailscale service..."
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

echo "You must manually authenticate Tailscale:"
sudo tailscale up

echo "Setting up tailscale exit node and funnel"
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo tailscale funnel --bg 1880 
sudo tailscale up --advertise-exit-node --accept-routes --hostname=$PRECURSOR
sudo tailscale set --advertise-routes=10.0.0.0/24

echo "Autorun setup complete."

echo "---"
echo "✅ All installations complete!"

echo "Performing Auto Cleanup"

sudo apt autoremove -y

echo "=== Setup complete! ==="
echo "Reboot recomended with 'sudo reboot now, next steps would be to setup node red projects, then cloudflare, then run the influxdb backup setup and finally optionally athelia'"
#sudo reboot now

