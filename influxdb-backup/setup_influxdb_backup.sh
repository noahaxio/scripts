#!/bin/bash

# Prompt for the token (-s hides the keystrokes for security)
read -s -p "Please enter your InfluxDB Token: " INFLUX_TOKEN
echo "" # Add a newline since -s suppresses the enter key output

# Safety check to ensure it isn't empty
if [ -z "$INFLUX_TOKEN" ]; then
  echo "Error: Token cannot be empty. Exiting."
  exit 1
fi

# Write the token to the file using sudo
echo "$INFLUX_TOKEN" | sudo tee /etc/axio-influx-token > /dev/null

# Change ownership so root owns it, but the 'debix' group is attached
sudo chown root:debix /etc/axio-influx-token

# Set permissions: root (6 = read/write), debix group (4 = read), others (0 = none)
sudo chmod 640 /etc/axio-influx-token

echo "Success! Token securely saved to /etc/axio-influx-token."