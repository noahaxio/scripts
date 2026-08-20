#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "================================================="
echo "   Authelia & Nginx Installation Script          "
echo "================================================="

# --- 1. PRE-FLIGHT CHECKS ---
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (use sudo)."
  exit 1
fi

DEVICE_NAME_FILE="/etc/axio-device-name"
if [ ! -f "$DEVICE_NAME_FILE" ]; then
  echo "Error: $DEVICE_NAME_FILE not found. Cannot determine device name."
  exit 1
fi

# Read the device name and remove any accidental whitespace or newlines
DEVICE_NAME=$(cat "$DEVICE_NAME_FILE" | tr -d '[:space:]')
echo "--> Detected Device Name: $DEVICE_NAME"


# --- 2. INSTALL DOCKER (IF MISSING) ---
if ! command -v docker &> /dev/null; then
  echo "--> Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
  echo "--> Docker installed successfully."
else
  echo "--> Docker is already installed. Skipping."
fi

# --- FIX IPTABLES BACKEND FOR DOCKER ---
echo "--> Ensuring iptables uses the nftables backend (required for Docker on this kernel)..."

# Switch iptables and ip6tables to use the nftables wrapper
update-alternatives --set iptables /usr/sbin/iptables-nft || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft || true

# If Docker is already active, it needs a restart to pick up the new iptables configuration
if systemctl is-active --quiet docker; then
  echo "--> Restarting Docker to apply networking changes..."
  systemctl restart docker
fi

# --- 3. GENERATE AUTHELIA PASSWORD HASH ---
echo "-------------------------------------------------"
read -s -p "Enter the new password for Authelia 'admin': " ADMIN_PASSWORD
echo ""
read -s -p "Confirm password: " ADMIN_PASSWORD_CONFIRM
echo ""

if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
  echo "Error: Passwords do not match. Exiting."
  exit 1
fi

echo "--> Pulling Authelia image and generating Argon2 hash..."
# Pulling silently first so the hash output isn't cluttered with download logs
docker pull authelia/authelia:latest > /dev/null

# Generate the hash. Authelia outputs "Digest: $argon2id$...", so we use awk to grab just the hash.
RAW_HASH_OUTPUT=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$ADMIN_PASSWORD")
ADMIN_HASH=$(echo "$RAW_HASH_OUTPUT" | awk '/Digest:/ {print $2}' | tr -d '\r')

if [ -z "$ADMIN_HASH" ]; then
    echo "Error: Failed to extract password hash. Raw output was: $RAW_HASH_OUTPUT"
    exit 1
fi
echo "--> Hash generated successfully."

# --- 4. CREATE AUTHELIA DIRECTORIES & FILES ---
echo "--> Setting up Authelia files in /opt/authelia..."
mkdir -p /opt/authelia
cd /opt/authelia

# 4a. docker-compose.yml (Quoted 'EOF' means no variables are expanded here)
cat << 'EOF' > docker-compose.yml
version: '3.8'
services:
  authelia:
    image: authelia/authelia:latest
    container_name: authelia
    restart: unless-stopped
    volumes:
      - ./:/config
    ports:
      - "9091:9091"
    environment:
      - TZ=Africa/Johannesburg
  redis:
    image: redis:alpine
    container_name: authelia_redis
    restart: unless-stopped
EOF

# 4b. users_database.yml (Unquoted EOF so $ADMIN_HASH expands)
cat << EOF > users_database.yml
users:
  admin:
    displayname: "Admin User"
    email: "noah@axioenergy.co"
    password: "$ADMIN_HASH"
    groups:
      - admins
EOF

# 4c. configuration.yml (Unquoted EOF so $DEVICE_NAME expands)
cat << EOF > configuration.yml
server:
  address: 'tcp://0.0.0.0:9091'

authentication_backend:
  file:
    path: /config/users_database.yml

access_control:
  default_policy: deny
  rules:
    - domain: "auth-${DEVICE_NAME}.axioenergy.co"
      policy: bypass
    - domain: "${DEVICE_NAME}.axioenergy.co"
      policy: one_factor

session:
  name: authelia_session
  domain: axioenergy.co
  expiration: 2h
  inactivity: 15m
  secret: 'super_secret_session_key_change_me'
  redis:
    host: authelia_redis
    port: 6379

storage:
  encryption_key: 'super_secret_storage_key_change_me'
  local:
    path: /config/db.sqlite3

notifier:
  filesystem:
    filename: /config/notification.txt

identity_validation:
  reset_password:
    jwt_secret: 'super_secret_jwt_key_change_me'
EOF


# --- 5. CONFIGURE NGINX ---
echo "--> Configuring Nginx..."

# Remove old cloudflare proxy configs if they exist
rm -f /etc/nginx/sites-available/cloudflare-proxy
rm -f /etc/nginx/sites-enabled/cloudflare-proxy

# Create the new Nginx block. 
# Notice the backslashes (\) before Nginx variables like \$host. This stops bash from deleting them.
cat << EOF > /etc/nginx/sites-available/$DEVICE_NAME
# 1. The Login Portal
server {
    listen 1881; # Changed from 80
    server_name auth-${DEVICE_NAME}.axioenergy.co;

    location / {
        proxy_pass http://127.0.0.1:9091;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# 2. The Protected App
server {
    listen 1881; # Changed from 80
    server_name ${DEVICE_NAME}.axioenergy.co;

    # ADDED: This keeps your "go straight to dashboard" logic
    location = / {
        rewrite ^ /dashboard last;
    }

    location / {
        auth_request /auth_verify;
        error_page 401 = @authelia_redirect;

        proxy_pass http://127.0.0.1:1880;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location = /auth_verify {
        internal;
        proxy_pass http://127.0.0.1:9091/api/verify;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI \$request_uri;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location @authelia_redirect {
        return 302 https://auth-${DEVICE_NAME}.axioenergy.co/?rd=https://\$http_host\$request_uri;
    }
}
EOF

# Enable the new site and restart Nginx
ln -sf /etc/nginx/sites-available/$DEVICE_NAME /etc/nginx/sites-enabled/
systemctl restart nginx
echo "--> Nginx restarted with new configuration."


# --- 6. START AUTHELIA ---
echo "--> Starting Authelia containers..."
cd /opt/authelia
# Use "docker compose" (V2) as standard, fallback to "docker-compose" (V1) just in case
if docker compose version &> /dev/null; then
  docker compose up -d
else
  docker-compose up -d
fi

echo "================================================="
echo " Setup Complete!"
echo " Authelia and Redis are spinning up, remeber to add auth-${DEVICE_NAME}.axioenergy.co and ${DEVICE_NAME}.axioenergy.co to your Cloudflare"
echo "================================================="