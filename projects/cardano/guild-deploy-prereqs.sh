#!/bin/bash

# Exit on any error
set -e

# Create guild user and group, add to sudo and docker groups
echo "Creating guild user and group, adding to sudo and docker..."
adduser --disabled-password --gecos '' guild
adduser guild sudo
adduser guild docker || { echo "Warning: docker group may not exist yet; ensure Docker is installed"; }
mkdir -pv /home/guild/.local/ /home/guild/.scripts/

# Switch to guild user (simulating USER in Dockerfile)
echo "Switching to guild user..."
su - guild -c "
  # Set working directory (simulating WORKDIR in Dockerfile)
  cd /home/guild || { echo 'Failed to switch to /home/guild'; exit 1; }

  # Create and enter temporary directory
  mkdir -p \$HOME/tmp || { echo 'Failed to create \$HOME/tmp'; exit 1; }
  cd \$HOME/tmp || { echo 'Failed to switch to \$HOME/tmp'; exit 1; }

  # Install curl
  sudo apt -y install curl || { echo 'Failed to install curl'; exit 1; }

  # Download the script
  curl -sS -o guild-deploy.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/guild-deploy.sh || { echo 'Failed to download guild-deploy.sh'; exit 1; }

  # Make it executable
  chmod 755 guild-deploy.sh || { echo 'Failed to set permissions on guild-deploy.sh'; exit 1; }

  # Run the script with options
  ./guild-deploy.sh -s pdlcowx || { echo 'Failed to execute guild-deploy.sh'; exit 1; }

  # Source the bashrc file
  . \"\${HOME}/.bashrc\" || { echo 'Failed to source .bashrc'; exit 1; }
"

echo "Script completed successfully."