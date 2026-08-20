#!/bin/bash

# Get the real user's home directory even if run with sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

echo "Removing unused home directories..."
rm -rf "$REAL_HOME/Video" "$REAL_HOME/Videos" "$REAL_HOME/Music" "$REAL_HOME/Pictures" "$REAL_HOME/Templates"

echo "Done!"
