#!/bin/bash

# 1. Check for root
if (( EUID != 0 )); then
  echo "This script must be run with sudo." >&2
  exit 1
fi

# 2. Define variables
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
TARGET_DIR="$REAL_HOME/Scripts"
REPO_URL="https://github.com/noahaxio/scripts"

# --- Start of Block ---

echo "Setting up Scripts directory for user: $REAL_USER..."

# Check if the directory exists AND is a git repository
if [ -d "$TARGET_DIR/.git" ]; then
    echo "Directory exists. Discarding local changes and updating..."
    cd "$TARGET_DIR" || exit
    
    # Force git to forget local changes to tracked files
    git reset --hard HEAD
    
    # Pull the latest version
    git pull

# Check if directory exists but is NOT a git repository (safety check)
elif [ -d "$TARGET_DIR" ] && [ "$(ls -A "$TARGET_DIR")" ]; then
    echo "Error: $TARGET_DIR exists but is not empty and not a git repository."
    echo "Please back up or remove this folder manually."
    exit 1

# Otherwise, create and clone
else
    echo "Cloning repository..."
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR" || exit
    git clone "$REPO_URL" .
fi

# Make all files in the directory executable
chmod +x *

# Fix permissions so the user owns the folder and files
# (This ensures the .git folder and scripts belong to Noah, not root)
chown -R "$REAL_USER":"$REAL_USER" "$TARGET_DIR"

echo "Done. Scripts directory is up to date and executable."