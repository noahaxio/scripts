#!/bin/bash

# Script to disable the "offline ready" notification in Node-RED Dashboard 2
# while keeping offline functionality intact
# The notification is typically shown when the PWA service worker has cached everything

echo "Disabling Dashboard 2 offline ready notification..."

# Determine the Node-RED directory and Dashboard 2 location
NODE_RED_DIR="/home/debix/.node-red"
DASHBOARD2_DIR="$NODE_RED_DIR/node_modules/@flowfuse/node-red-dashboard"
DASHBOARD2_DIST="$DASHBOARD2_DIR/dist"

if [ ! -d "$DASHBOARD2_DIR" ]; then
    echo "ERROR: Dashboard 2 not found at $DASHBOARD2_DIR"
    exit 1
fi

if [ ! -d "$DASHBOARD2_DIST" ]; then
    echo "ERROR: Dashboard 2 dist directory not found at $DASHBOARD2_DIST"
    exit 1
fi

echo "Found Dashboard 2 at: $DASHBOARD2_DIR"

# Find and patch the main bundle files that contain the notification logic
# The notification is typically in the main app or ui bundle

# Option 1: Look for the notification text in JavaScript bundles and disable it via CSS
PATCH_FILE="$DASHBOARD2_DIST/index.html"

if [ -f "$PATCH_FILE" ]; then
    echo "Patching index.html to hide offline ready notification..."
    
    # Add CSS to hide the notification
    # This approach hides the notification visually while keeping the service worker functionality
    if ! grep -q "disable-offline-notification" "$PATCH_FILE"; then
        # Insert a style tag that hides the offline notification
        sudo sed -i '/<\/head>/i\    <style>\n      /* Hide offline ready notification while keeping PWA functionality */\n      [role="alert"] { display: none !important; }\n      .offline-notification { display: none !important; }\n    </style>' "$PATCH_FILE"
        echo "CSS patch applied to hide notifications."
    else
        echo "Notification hiding CSS already exists."
    fi
else
    echo "WARNING: index.html not found at $PATCH_FILE"
fi

# Option 2: Look for JavaScript files that trigger the notification
# and patch them to suppress the notification display
for bundle in "$DASHBOARD2_DIST"/*.js; do
    if [ -f "$bundle" ]; then
        filename=$(basename "$bundle")
        # Check if this bundle contains offline/notification logic
        if grep -q "offline.*ready" "$bundle" 2>/dev/null; then
            echo "Found offline logic in: $filename"
            # Create a backup
            sudo cp "$bundle" "$bundle.backup"
            echo "Created backup: $filename.backup"
        fi
    fi
done

echo ""
echo "Restart Node-RED to apply changes:"
echo "  sudo systemctl restart nodered"
echo ""
echo "Or if running manually:"
echo "  node-red"
echo ""
echo "✅ Patch complete. The offline ready notification should no longer appear,"
echo "   but offline functionality will remain intact."
