#!/bin/bash

# Set the G_ACCOUNT variable
G_ACCOUNT="cardano-community"
export G_ACCOUNT

# Set Username Variable
NODE_USER=$(whoami)
echo "Current user: $NODE_USER"
export NODE_USER

echo "Cloning the Guild-Tools Repo ..."
cd ~/git
# Check if the 'guild-operators' directory already exists
if [ -d "guild-operators" ]; then
    echo "'guild-operators' directory exists. Removing it now."
    rm -rf guild-operators
fi
# Clone the repository
git clone https://github.com/cardano-community/guild-operators.git
cd ~/git/guild-operators/files/docker/node

echo "Set Cardano File System Permissions ..."
sudo chown -R ${NODE_USER}:${NODE_USER} /opt/cardano
sudo chmod -R 0774 /opt/cardano
sudo chown -R ${NODE_USER}:${NODE_USER} /home/${NODE_USER}
sudo chmod -R 0774 /home/${NODE_USER}

# Build the Docker image with the G_ACCOUNT build argument
docker build --build-arg G_ACCOUNT=$G_ACCOUNT -t cardanocommunity/cardano-node:latest - < dockerfile_bin

# Run the Docker container
docker run --init -dit \
--restart always \
--name Skint-Relay-1 \
-p 6000:6000 \
-e NETWORK=mainnet \
--security-opt=no-new-privileges \
-v /opt/cardano/cnode/sockets:/opt/cardano/cnode/sockets \
-v /opt/cardano/cnode/priv:/opt/cardano/cnode/priv \
-v /opt/cardano/cnode/db:/opt/cardano/cnode/db \
cardanocommunity/cardano-node

docker exec -it skint-relay1 bash
