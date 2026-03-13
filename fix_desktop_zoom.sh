#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

if [ "$EUID" -eq 0 ]; then
  echo "Error: Please do not run this script as root or with sudo."
  exit 1
fi

echo "Starting GNOME 'no-overview' extension installation..."

# Ensure unzip is installed (crucial for a fresh machine)
if ! command -v unzip &> /dev/null; then
    echo "'unzip' is not installed. Installing it now..."
    sudo apt-get update && sudo apt-get install -y unzip
fi

echo "Cleaning up any existing extension directories..."
rm -rf ~/.local/share/gnome-shell/extensions/no-overview@fthx

echo "Creating the extension directory..."
mkdir -p ~/.local/share/gnome-shell/extensions/no-overview@fthx

echo "Downloading the extension zip..."
wget -qO /tmp/ext.zip "https://extensions.gnome.org/extension-data/no-overviewfthx.v14.shell-extension.zip"

echo "Extracting the extension..."
unzip -q /tmp/ext.zip -d ~/.local/share/gnome-shell/extensions/no-overview@fthx

echo "Removing the temporary zip file..."
rm /tmp/ext.zip

echo "Enabling user extensions globally..."
gsettings set org.gnome.shell disable-user-extensions false

echo "Updating the GNOME dconf database..."
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

echo "All done! Please reboot the board to apply the changes."