#!/bin/bash

# Use existing user (no user creation steps)
echo "Using current user: $USER"
cd "${HOME}" || { echo 'Failed to change directory to HOME'; exit 1; }

# Install curl (still requires sudo privileges)
sudo apt -y install curl || { echo 'Failed to install curl'; exit 1; }

# Download the script
curl -sS -o guild-deploy.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/guild-deploy.sh || { echo 'Failed to download guild-deploy.sh'; exit 1; }

# Make it executable
chmod +x guild-deploy.sh || { echo 'Failed to set permissions on guild-deploy.sh'; exit 1; }

# Run the script with options
./guild-deploy.sh -s pdlcowx || { echo 'Failed to execute guild-deploy.sh'; exit 1; }

# Source the bashrc file
. "${HOME}/.bashrc" || { echo 'Failed to source .bashrc'; exit 1; }

echo "Script completed successfully."