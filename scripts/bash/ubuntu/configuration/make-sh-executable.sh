#!/bin/bash

# Check if a root directory is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <root_directory>"
  exit 1
fi

ROOT_DIR="$1"

# Find all .sh files and change their permissions to be executable
find "$ROOT_DIR" -type f -name "*.sh" -exec chmod +x {} \;

echo "Permissions for all .sh files under $ROOT_DIR have been modified to be executable."
