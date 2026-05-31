#!/usr/bin/env bash
set -euo pipefail

# --- Helpers ---
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

# Check if a root directory is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <root_directory>"
  exit 1
fi

ROOT_DIR="$1"

# Find all .sh files and change their permissions to be executable
find "$ROOT_DIR" -type f -name "*.sh" -exec chmod +x {} \;

echo "Permissions for all .sh files under $ROOT_DIR have been modified to be executable."
