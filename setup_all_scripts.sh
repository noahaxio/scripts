#!/bin/bash

# 1. Check for root
if (( EUID != 0 )); then
  echo "This script must be run with sudo." >&2
  exit 1
fi

# 2. Define variables
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

# --- Start of Block ---

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

echo "Done. Repository cloned and scripts made executable."