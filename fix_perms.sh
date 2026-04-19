#!/bin/bash

# Ensure the script is run as root
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

echo "=== Fixing Permissions & Ownership ==="

# Define variables used in the original script
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
TARGET_USER="debix"
AUTORUN_DIR="$REAL_HOME/Autorun"
SCRIPT_PATH="$AUTORUN_DIR/setup_browser.sh"
DESKTOP_ENTRY="/etc/xdg/autostart/start-browser.desktop"

# 1. Scripts Directory
if [ -d "$REAL_HOME/Scripts" ]; then
    echo "Applying permissions to Scripts directory..."
    chmod +x "$REAL_HOME/Scripts"/*
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Scripts"
else
    echo "Directory $REAL_HOME/Scripts not found. Skipping."
fi

# 2. Renderers Directory
if [ -d "$REAL_HOME/Renderers" ]; then
    echo "Applying permissions to Renderers directory..."
    # The original script only had chown here, but it's crucial for access
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/Renderers"
else
    echo "Directory $REAL_HOME/Renderers not found. Skipping."
fi

# 3. Setup Browser Autorun Script
if [ -f "$SCRIPT_PATH" ]; then
    echo "Applying permissions to Browser Autorun script..."
    chmod +x "$SCRIPT_PATH"
    chown "$TARGET_USER":"$TARGET_USER" "$SCRIPT_PATH"
else
    echo "File $SCRIPT_PATH not found. Skipping."
fi

# 4. Desktop Autostart Entry
if [ -f "$DESKTOP_ENTRY" ]; then
    echo "Applying permissions to Desktop Autostart entry..."
    chmod 644 "$DESKTOP_ENTRY"
    chown root:root "$DESKTOP_ENTRY"
else
    echo "File $DESKTOP_ENTRY not found. Skipping."
fi

# 5. Node-RED Directory
if [ -d "/home/debix/.node-red" ]; then
    echo "Applying permissions to Node-RED directory..."
    chown -R "$TARGET_USER":"$TARGET_USER" "/home/debix/.node-red"
else
    echo "Directory /home/debix/.node-red not found. Skipping."
fi

echo "=== Permissions fix complete! ==="