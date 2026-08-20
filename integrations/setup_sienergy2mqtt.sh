#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (use sudo)."
  exit 1
fi

# Dynamically find the home directory of the user who invoked sudo
# Fall back to the current user if sudo wasn't used
ACTUAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$ACTUAL_USER)

# Define the installation directory in the user's home folder
BASE_DIR="$USER_HOME/sigenergy-mqtt"

# Check for Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

# --- UPDATE PATH ---
# If the directory and compose file already exist, treat this as an update.
if [ -d "$BASE_DIR" ] && [ -f "$BASE_DIR/docker-compose.yml" ]; then
    echo "Found existing installation at $BASE_DIR."
    echo "Pulling latest images and updating stack..."
    cd "$BASE_DIR" || exit
    
    docker compose pull
    docker compose up -d
    
    echo "Update complete. The containers are running."
    exit 0
fi

# --- NEW INSTALLATION PATH ---
echo "Starting new Sigenergy MQTT Bridge setup in $BASE_DIR..."

# Prompt for the inverter IP address
read -p "Enter the IP address of your Sigenergy inverter: " SIG_IP

if [ -z "$SIG_IP" ]; then
    echo "Error: IP address cannot be empty. Exiting."
    exit 1
fi

# Create directory structure
echo "Creating directories..."
mkdir -p "$BASE_DIR/mosquitto/config"
mkdir -p "$BASE_DIR/mosquitto/data"
mkdir -p "$BASE_DIR/mosquitto/log"
mkdir -p "$BASE_DIR/sigenergy2mqtt"

# Fix permissions for Mosquitto (The internal mosquitto user runs as UID 1883)
# But ensure the base directory is owned by the actual user
chown -R "$ACTUAL_USER:$ACTUAL_USER" "$BASE_DIR"
chown -R 1883:1883 "$BASE_DIR/mosquitto"

# Generate Mosquitto configuration
echo "Writing Mosquitto config..."
cat <<EOF > "$BASE_DIR/mosquitto/config/mosquitto.conf"
listener 1883
allow_anonymous true
EOF

# Generate sigenergy2mqtt configuration
echo "Writing Sigenergy bridge config..."
cat <<EOF > "$BASE_DIR/sigenergy2mqtt/sigenergy2mqtt.yaml"
mqtt:
  broker: mosquitto
  anonymous: true

modbus:
  - host: $SIG_IP
    inverters: [ 1 ]
EOF

# Generate Docker Compose file
echo "Writing Docker Compose file..."
cat <<EOF > "$BASE_DIR/docker-compose.yml"
version: '3.8'

services:
  mosquitto:
    image: eclipse-mosquitto:latest
    container_name: mosquitto_broker
    restart: unless-stopped
    ports:
      - "1883:1883"
    volumes:
      - ./mosquitto/config:/mosquitto/config
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log

  sigenergy2mqtt:
    image: seud0nym/sigenergy2mqtt:latest
    container_name: sigenergy_bridge
    restart: unless-stopped
    depends_on:
      - mosquitto
    volumes:
      - ./sigenergy2mqtt/sigenergy2mqtt.yaml:/data/sigenergy2mqtt.yaml
EOF

# Ensure all newly created config files are owned by the user, not root
chown -R "$ACTUAL_USER:$ACTUAL_USER" "$BASE_DIR/sigenergy2mqtt"
chown "$ACTUAL_USER:$ACTUAL_USER" "$BASE_DIR/docker-compose.yml"

# Start the stack
echo "Pulling images and starting containers..."
cd "$BASE_DIR" || exit
docker compose pull
docker compose up -d

echo "----------------------------------------------------"
echo "Setup complete! Services are running in $BASE_DIR."
echo "Mosquitto is listening on port 1883."
echo "You can check the bridge logs using:"
echo "  cd $BASE_DIR && docker compose logs -f sigenergy2mqtt"
echo "----------------------------------------------------"