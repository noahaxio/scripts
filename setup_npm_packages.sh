#!/bin/bash

# Ensure the script is run as root
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

# --- 5. Fix Permissions ---
echo "## 5. Fixing ownership and permissions..."

# Ensure the user owns their home directory node_modules
# (Fixes issues where 'sudo npm install' or 'audit fix' creates root-owned files)
if [ -d "$REAL_HOME/node_modules" ]; then
    echo "Fixing permissions for $REAL_HOME/node_modules..."
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/node_modules"
    chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/package-lock.json" 2>/dev/null
    chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/package.json" 2>/dev/null
fi

# Ensure the user owns the .node-red directory
if [ -d "$NODE_RED_DIR" ]; then
    echo "Fixing permissions for $NODE_RED_DIR..."
    chown -R "$REAL_USER":"$REAL_USER" "$NODE_RED_DIR"
fi

echo "=== NPM Package & Dependency Installer ==="

# Identify the real user (who called sudo) to install packages for them, not root
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
echo "Detected User: $REAL_USER"
echo "User Home: $REAL_HOME"

# --- 1. Install System Dependencies for Canvas ---
# Required for 'canvas', 'chartjs-node-canvas' and Chart.js rendering
echo "## 1. Installing required system dependencies..."

if command -v apt &> /dev/null; then
    apt-get update -y
    apt-get install -y build-essential libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev
    echo "System dependencies installed successfully."
else
    echo "Warning: 'apt' not found. Skipping system dependency installation."
fi

echo "---"

# --- 2. Install Main NPM Packages (User Home) ---
# These are installed in the user's root (~/node_modules) so external scripts/renderers can find them.
echo "## 2. Installing main npm packages in $REAL_HOME..."

cd "$REAL_HOME" || exit 1

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

# Install packages as root (permissions fixed later)
npm install "${MAIN_PACKAGES[@]}"

if [ $? -eq 0 ]; then
    echo "Main packages installed successfully."
else
    echo "Error: Failed to install main npm packages."
    exit 1
fi

echo "---"

# --- 3. Install Node-RED Packages (~/.node-red) ---
# These are installed specifically for the Node-RED runtime.
echo "## 3. Installing Node-RED packages in $REAL_HOME/.node-red..."

NODE_RED_DIR="$REAL_HOME/.node-red"

# Ensure the directory exists
if [ ! -d "$NODE_RED_DIR" ]; then
    echo "Creating Node-RED directory: $NODE_RED_DIR"
    mkdir -p "$NODE_RED_DIR"
fi

cd "$NODE_RED_DIR" || exit 1

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

npm install "${NODE_RED_PACKAGES[@]}"

if [ $? -eq 0 ]; then
    echo "Node-RED packages installed successfully."
else
    echo "Error: Failed to install Node-RED npm packages."
    exit 1
fi

echo "---"

# --- 4. Run NPM Audit Fix ---
echo "## 4. Running 'npm audit fix --force'..."

# Fix in User Home
echo "Running audit fix in $REAL_HOME..."
cd "$REAL_HOME" || exit 1
npm audit fix --force

# Fix in Node-RED Directory
echo "Running audit fix in $NODE_RED_DIR..."
cd "$NODE_RED_DIR" || exit 1
npm audit fix --force

echo "Audit fix complete."
echo "---"

echo "=== Installation Complete ==="