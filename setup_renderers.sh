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