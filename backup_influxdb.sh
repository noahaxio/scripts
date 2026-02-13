#!/bin/bash

# --- Configuration ---
git config --global user.email "noahg@axioenergy.co"
git config --global user.name "noahg"

INFLUX_ORG="Axio"
INFLUX_HOST="http://localhost:8086"

# Define where the token lives
TOKEN_FILE="/etc/axio-influx-token"

# Check if the token file exists before proceeding
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: Token file $TOKEN_FILE not found! Please create it and add your token."
    exit 1
fi

# Read the token
INFLUX_TOKEN=$(cat "$TOKEN_FILE")

# GitHub Details
REPO_URL="git@github.com:noahaxio/$(cat /etc/axio-device-name).git"
BRANCH_NAME="influxdb"

# Temporary workspace
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
WORK_DIR="/tmp/influx_backup_$TIMESTAMP"

# --- 1. Perform InfluxDB Backup ---
echo "Starting InfluxDB backup to $WORK_DIR..."
mkdir -p "$WORK_DIR"

# Run the backup
influx backup "$WORK_DIR" \
  --org "$INFLUX_ORG" \
  --token "$INFLUX_TOKEN" \
  --host "$INFLUX_HOST"

if [ $? -ne 0 ]; then
    echo "Error: InfluxDB backup failed."
    rm -rf "$WORK_DIR"
    exit 1
fi

# --- 2. Git Force Push (Snapshot) ---
echo "Initializing git and forcing update..."
cd "$WORK_DIR" || exit 1

# Initialize a fresh git repo in the backup folder
git init

# Create the branch name immediately
git checkout -b "$BRANCH_NAME"

# Add all backup files
git add .

# Commit as a snapshot
git commit -m "InfluxDB Snapshot: $(date +'%Y-%m-%d %H:%M:%S')"

# Add the remote URL
git remote add origin "$REPO_URL"

# FORCE PUSH (-f)
# This overwrites the remote branch completely, effectively 
# "deleting" the old content and replacing it with this new commit.
git push -f origin "$BRANCH_NAME"

# --- 3. Cleanup ---
echo "Cleaning up..."
cd ..
rm -rf "$WORK_DIR"

echo "Done! Remote branch '$BRANCH_NAME' has been overwritten with the latest backup."
