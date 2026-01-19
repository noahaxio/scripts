#!/bin/bash
if (( EUID != 0 )); then
  echo "This script must be run with sudo or as root." >&2
  exit 1
fi

#set -e

# 1. Identify the real user (since sudo changes $HOME to /root)
if [ $SUDO_USER ]; then
    REAL_USER=$SUDO_USER
    REAL_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
else
    echo "Error: Could not detect the original user. Please run with sudo."
    exit 1
fi

read -p "What is the project name?: " PRECURSOR

# 2. Define the path using the Real User's home directory
TARGET_DIR="$REAL_HOME/.node-red/projects/$PRECURSOR/.git/hooks"

# Check if the directory actually exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    echo "Double-check the project name."
    exit 1
fi

cd "$TARGET_DIR" || exit

echo "Setting up hook in: $(pwd)"

# 3. Create the post-commit file
# We use 'cat <<EOF' to write the content cleanly
cat <<EOF > post-commit
#!/bin/bash
# Automatically detect the current branch (main or master)
BRANCH=\$(git rev-parse --abbrev-ref HEAD)

# Push the current branch to origin
git push origin "\$BRANCH"
EOF

# 4. Make it executable
chmod +x post-commit

# 5. Fix ownership
# Since this script runs as root, the file is created as root.
# Node-RED (running as the user) needs to own it to execute it.
chown "$REAL_USER":"$REAL_USER" post-commit

echo "------------------------------------------------"
echo "Success! Auto-push enabled for project: $PRECURSOR"
echo "------------------------------------------------"