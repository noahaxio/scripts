#!/bin/bash

# --- Prevent running as root or with sudo ---
if (( EUID == 0 )); then
  echo "Error: This script must NOT be run with sudo or as root." >&2
  echo "Please run it normally as your standard user." >&2
  exit 1
fi

echo "=== Setting up Daily Kiosk Restart ==="

# 1. Install and enable cron
echo "Installing cron (you may be prompted for your sudo password here)..."
sudo apt update
sudo apt install -y cron

echo "Enabling and starting the cron service..."
sudo systemctl enable cron
sudo systemctl start cron

# 2. Define the cron job exactly as needed
CRON_JOB="0 3 * * * XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user restart kiosk.service"

# 3. Safely add it to the user's crontab without opening an editor
echo "Adding the restart task to your user's crontab..."

# Idempotent: remove all existing entries for this command, then add exactly one.
(crontab -l 2>/dev/null | grep -vF "systemctl --user restart kiosk.service"; echo "$CRON_JOB") | crontab -
echo "Cron job installed/updated successfully (duplicates removed if present)."

echo "=== Done! Chromium will now flush and restart daily at 3:00 AM. ==="