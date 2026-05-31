#!/bin/bash

# Define directories
TARGET_DIR="/source-files/cardano/cli"
TMP_DIR="/source-files/cardano/tmp"

# Create directories if they don't exist
mkdir -p "$TARGET_DIR" || { echo "Error: Failed to create $TARGET_DIR"; exit 1; }
mkdir -p "$TMP_DIR" || { echo "Error: Failed to create $TMP_DIR"; exit 1; }

# Clear out the cli directory to start fresh
rm -rf "$TARGET_DIR"/* || { echo "Error: Failed to remove contents of $TARGET_DIR"; exit 1; }

# Fetch the latest release information from GitHub
RELEASE_INFO=$(curl -s https://api.github.com/repos/IntersectMBO/cardano-cli/releases/latest)
[ -z "$RELEASE_INFO" ] && { echo "Error: Could not retrieve release info."; exit 1; }

# Extract the download URL for the Linux x86_64 tarball
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[] | select(.name | test("x86_64-linux\\.tar\\.gz$")) | .browser_download_url')
[ -z "$DOWNLOAD_URL" ] && { echo "Error: Could not find Linux x86_64 tarball."; exit 1; }

# Define the tarball filename and path
TARBALL_NAME=$(basename "$DOWNLOAD_URL")
TARBALL_PATH="$TMP_DIR/$TARBALL_NAME"

# Download the tarball to the tmp directory
curl -L -o "$TARBALL_PATH" "$DOWNLOAD_URL" || { echo "Error: Failed to download tarball."; exit 1; }

# Extract the tarball contents directly into the cli directory
tar -xzf "$TARBALL_PATH" -C "$TARGET_DIR" || { echo "Error: Failed to extract tarball."; exit 1; }

# Find the extracted file starting with 'cardano-cli'
CLI_FILE=$(find "$TARGET_DIR" -type f -name 'cardano-cli*' -print -quit)
[ -z "$CLI_FILE" ] && { echo "Error: No file starting with 'cardano-cli' found."; exit 1; }

# Rename the file to 'cardano-cli' for consistency
mv "$CLI_FILE" "$TARGET_DIR/cardano-cli" || { echo "Error: Failed to rename file."; exit 1; }

# Make the file executable
chmod +x "$TARGET_DIR/cardano-cli" || { echo "Error: Failed to set executable permission."; exit 1; }

# Clean up the tarball from the tmp directory
rm "$TARBALL_PATH" || { echo "Error: Failed to remove tarball."; exit 1; }

# Confirm success
echo "Successfully installed cardano-cli in $TARGET_DIR"