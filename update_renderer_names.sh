#!/bin/bash

# 1. Check for root (required to edit settings.js if owned by root, or just for consistency)
if (( EUID != 0 )); then
  echo "This script must be run with sudo." >&2
  exit 1
fi

# 2. Define variables based on the real user
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

RENDERERS_DIR="$REAL_HOME/Renderers"
SETTINGS_FILE="$REAL_HOME/.node-red/settings.js"

echo "=== Injecting Renderers into Node-RED Settings ==="
echo "Target User: $REAL_USER"
echo "Renderers Dir: $RENDERERS_DIR"
echo "Settings File: $SETTINGS_FILE"
echo "---"

# 3. Check if files/folders exist
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "ERROR: Node-RED settings.js not found at $SETTINGS_FILE"
    exit 1
fi

if [ ! -d "$RENDERERS_DIR" ]; then
    echo "ERROR: Renderers directory not found at $RENDERERS_DIR"
    exit 1
fi

# 4. Loop through every .js file
count=0
for filepath in "$RENDERERS_DIR"/*.js; do
    # Check if glob expansion failed (i.e. no JS files found)
    [ -e "$filepath" ] || continue

    # Get filename (e.g. "chart-renderer.js")
    filename=$(basename "$filepath")
    
    # Remove extension (e.g. "chart-renderer")
    basename="${filename%.*}"
    
    # Convert kebab-case to camelCase (e.g. "chart-renderer" -> "chartRenderer")
    varName=$(echo "$basename" | sed -r 's/-([a-z])/\U\1/g')
    
    # Construct the require line
    # Result: chartRenderer: require("/home/debix/Renderers/chart-renderer.js"),
    ENTRY="$varName: require(\"$filepath\"),"

    # check if it is already there to avoid duplicates
    if grep -Fq "$ENTRY" "$SETTINGS_FILE"; then
        echo "  - Skipping $varName (already exists in settings.js)"
    else
        # Insert into functionGlobalContext
        sudo sed -i "/functionGlobalContext: {/a\        $ENTRY" "$SETTINGS_FILE"
        echo "  + Injected $varName"
        ((count++))
    fi
done

echo "---"
if [ $count -eq 0 ]; then
    echo "No new renderers were added."
else
    echo "Success! Added $count new renderers to functionGlobalContext."
fi