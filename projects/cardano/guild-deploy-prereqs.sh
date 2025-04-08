#!/bin/bash

# Exit on any error
set -e

# Use existing user (no user creation steps)
echo "Using current user: $USER"

# Ensure required directories exist
mkdir -pv "$HOME/.local/" "$HOME/.scripts/"

# Set working directory
cd "$HOME" || { echo 'Failed to switch to home directory'; exit 1; }

# Create and enter temporary directory
mkdir -p "$HOME/tmp" || { echo 'Failed to create $HOME/tmp'; exit 1; }
cd "$HOME/tmp" || { echo 'Failed to switch to $HOME/tmp'; exit 1; }

# Install curl (still requires sudo privileges)
sudo apt -y install curl || { echo 'Failed to install curl'; exit 1; }

# Download the script
curl -sS -o guild-deploy.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/guild-deploy.sh || { echo 'Failed to download guild-deploy.sh'; exit 1; }

# Make it executable
chmod 755 guild-deploy.sh || { echo 'Failed to set permissions on guild-deploy.sh'; exit 1; }

# Run the script with options
./guild-deploy.sh -s pdlcowx || { echo 'Failed to execute guild-deploy.sh'; exit 1; }

# Source the bashrc file
. "${HOME}/.bashrc" || { echo 'Failed to source .bashrc'; exit 1; }

echo "Script completed successfully."