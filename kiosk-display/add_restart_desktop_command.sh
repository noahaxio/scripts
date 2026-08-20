#!/bin/bash

# Define the alias and the command
ALIAS_NAME="restartdesktop"
ALIAS_CMD="sudo systemctl restart gdm" # Update to gdm3 if you are on Debian/Ubuntu

# Define the target configuration file
TARGET_FILE="$HOME/.bashrc"

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
    echo "Applying changes to the current session..."
    
    # Source the file to apply immediately 
    # (Note: this only applies to the terminal running the script)
    eval "$(cat "$TARGET_FILE")"
    
    echo "Done! You can now type '$ALIAS_NAME' to restart your display manager."
fi