#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "================================================="
echo "   Authelia Credential Change Script              "
echo "================================================="

# --- 1. PRE-FLIGHT CHECKS ---
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (use sudo)."
  exit 1
fi

AUTHELIA_DIR="/opt/authelia"
USERS_FILE="$AUTHELIA_DIR/users_database.yml"

if [ ! -f "$USERS_FILE" ]; then
  echo "Error: $USERS_FILE not found. Run authelia_setup.sh first."
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo "Error: Docker is not installed. Run authelia_setup.sh first."
  exit 1
fi

# --- 2. BACK UP THE CURRENT USERS FILE ---
BACKUP_FILE="$USERS_FILE.bak.$(date +%Y%m%d%H%M%S)"
cp "$USERS_FILE" "$BACKUP_FILE"
echo "--> Backed up $USERS_FILE to $BACKUP_FILE"

# --- 3. FIND EXISTING USERS ---
# Users are keys directly under "users:", indented by exactly 2 spaces, e.g. "  admin:"
mapfile -t USERNAMES < <(awk 'match($0, /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) { line=$0; gsub(/^  /,"",line); gsub(/:[[:space:]]*$/,"",line); print line }' "$USERS_FILE")

if [ "${#USERNAMES[@]}" -eq 0 ]; then
  echo "Error: No users found in $USERS_FILE"
  exit 1
fi

if [ "${#USERNAMES[@]}" -eq 1 ]; then
  OLD_USERNAME="${USERNAMES[0]}"
  echo "--> Found user: $OLD_USERNAME"
else
  echo "--> Multiple users found:"
  for i in "${!USERNAMES[@]}"; do
    echo "    $((i+1))) ${USERNAMES[$i]}"
  done
  read -p "Select the user to update [1-${#USERNAMES[@]}]: " SELECTION
  if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#USERNAMES[@]}" ]; then
    echo "Error: Invalid selection."
    exit 1
  fi
  OLD_USERNAME="${USERNAMES[$((SELECTION-1))]}"
fi

# --- 4. READ EXISTING DISPLAYNAME / EMAIL FOR THE SELECTED USER ---
OLD_DISPLAYNAME=$(awk -v target="$OLD_USERNAME" '
  match($0, /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
    line=$0; gsub(/^  /,"",line); gsub(/:[[:space:]]*$/,"",line)
    in_block = (line == target)
    next
  }
  /^[^ ]/ { in_block=0 }
  in_block && /^    displayname:/ {
    val=$0; sub(/^    displayname:[[:space:]]*/,"",val); gsub(/^"|"$/,"",val); print val
  }
' "$USERS_FILE")

OLD_EMAIL=$(awk -v target="$OLD_USERNAME" '
  match($0, /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
    line=$0; gsub(/^  /,"",line); gsub(/:[[:space:]]*$/,"",line)
    in_block = (line == target)
    next
  }
  /^[^ ]/ { in_block=0 }
  in_block && /^    email:/ {
    val=$0; sub(/^    email:[[:space:]]*/,"",val); gsub(/^"|"$/,"",val); print val
  }
' "$USERS_FILE")

# --- 5. PROMPT FOR NEW VALUES ---
echo "-------------------------------------------------"
read -p "New username [$OLD_USERNAME]: " NEW_USERNAME
NEW_USERNAME="${NEW_USERNAME:-$OLD_USERNAME}"

read -p "New display name [$OLD_DISPLAYNAME]: " NEW_DISPLAYNAME
NEW_DISPLAYNAME="${NEW_DISPLAYNAME:-$OLD_DISPLAYNAME}"

read -p "New email [$OLD_EMAIL]: " NEW_EMAIL
NEW_EMAIL="${NEW_EMAIL:-$OLD_EMAIL}"

for VALUE in "$NEW_USERNAME" "$NEW_DISPLAYNAME" "$NEW_EMAIL"; do
  if [[ "$VALUE" == *'"'* ]]; then
    echo 'Error: Username, display name, and email cannot contain a double-quote (") character.'
    exit 1
  fi
done

read -s -p "Enter the new password for '$NEW_USERNAME': " NEW_PASSWORD
echo ""
read -s -p "Confirm password: " NEW_PASSWORD_CONFIRM
echo ""

if [ "$NEW_PASSWORD" != "$NEW_PASSWORD_CONFIRM" ]; then
  echo "Error: Passwords do not match. Exiting."
  exit 1
fi

# --- 6. GENERATE NEW ARGON2 HASH ---
echo "--> Pulling Authelia image and generating Argon2 hash..."
docker pull authelia/authelia:latest > /dev/null

RAW_HASH_OUTPUT=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$NEW_PASSWORD")
NEW_HASH=$(echo "$RAW_HASH_OUTPUT" | awk '/Digest:/ {print $2}' | tr -d '\r')

if [ -z "$NEW_HASH" ]; then
    echo "Error: Failed to extract password hash. Raw output was: $RAW_HASH_OUTPUT"
    exit 1
fi
echo "--> Hash generated successfully."

# --- 7. REWRITE users_database.yml IN PLACE ---
echo "--> Updating $USERS_FILE..."
TMP_FILE=$(mktemp)

awk -v target="$OLD_USERNAME" -v newuser="$NEW_USERNAME" -v newdisp="$NEW_DISPLAYNAME" -v newemail="$NEW_EMAIL" -v newhash="$NEW_HASH" '
  match($0, /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
    line=$0; gsub(/^  /,"",line); gsub(/:[[:space:]]*$/,"",line)
    if (line == target) {
      in_block=1
      print "  " newuser ":"
      next
    } else {
      in_block=0
    }
  }
  /^[^ ]/ { in_block=0 }
  in_block && /^    displayname:/ { print "    displayname: \"" newdisp "\""; next }
  in_block && /^    email:/       { print "    email: \"" newemail "\""; next }
  in_block && /^    password:/    { print "    password: \"" newhash "\""; next }
  { print }
' "$USERS_FILE" > "$TMP_FILE"

mv "$TMP_FILE" "$USERS_FILE"
echo "--> $USERS_FILE updated."

# --- 8. RESTART AUTHELIA ---
echo "--> Restarting Authelia..."
cd "$AUTHELIA_DIR"
if docker compose version &> /dev/null; then
  docker compose restart authelia
else
  docker-compose restart authelia
fi

echo "================================================="
echo " Credential change complete!"
echo " Username: $NEW_USERNAME"
echo " A backup of the previous file was saved to:"
echo " $BACKUP_FILE"
echo "================================================="
