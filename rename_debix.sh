#!/bin/bash
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

DEVICE_NAME_FILE="/etc/axio-device-name"

read -p $'New device name (goes before .axioenergy.co):\n' NEW_NAME
NEW_NAME=$(echo "$NEW_NAME" | tr '[:upper:]' '[:lower:]')

if [ -z "$NEW_NAME" ]; then
  echo "Error: name cannot be empty." >&2
  exit 1
fi

OLD_NAME=""
if [ -s "$DEVICE_NAME_FILE" ]; then
  OLD_NAME=$(cat "$DEVICE_NAME_FILE")
fi

echo "Renaming: '${OLD_NAME:-<none>}' → '$NEW_NAME'"

# 1. Source of truth
echo "$NEW_NAME" | tee "$DEVICE_NAME_FILE" > /dev/null
echo "  [1/4] Updated $DEVICE_NAME_FILE"

# 2. Cockpit / systemd-hostnamed
echo "PRETTY_HOSTNAME=\"$NEW_NAME\"" > /etc/machine-info
systemctl restart systemd-hostnamed
echo "  [2/4] Updated /etc/machine-info and restarted systemd-hostnamed"

# 3. Nginx
NGINX_CONF="/etc/nginx/sites-available/cloudflare-proxy"
if [ -f "$NGINX_CONF" ]; then
  sed -i "s/server_name .*/server_name $NEW_NAME.axioenergy.co;/" "$NGINX_CONF"
  nginx -t && systemctl reload nginx
  echo "  [3/4] Updated nginx server_name and reloaded"
else
  echo "  [3/4] SKIP: $NGINX_CONF not found"
fi

# 4. Tailscale
tailscale up --advertise-exit-node --accept-routes --hostname="$NEW_NAME" --advertise-routes=10.0.0.0/24
echo "  [4/4] Updated Tailscale hostname"

echo ""
echo "Done. Device is now: $NEW_NAME"
