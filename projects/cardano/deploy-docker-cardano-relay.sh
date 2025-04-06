#!/bin/bash

# Define variables
IMAGE_NAME="cardanocommunity/cardano-node:latest"
CONTAINER_NAME="cardano-relay-node"
LOCAL_VOLUMES="/opt/cardano/cnode"

# Step 1: Pull the latest Docker image
echo "Pulling the latest Cardano node image..."
docker pull $IMAGE_NAME

# Step 2: Run the Docker container
echo "Starting the Cardano relay node container..."
docker run --init -dit \
  --name $CONTAINER_NAME \
  --security-opt=no-new-privileges \
  -e NETWORK=mainnet \
  -p 6000:6000 \
  -v /opt/cardano/cnode/priv:/opt/cardano/cnode/priv \
  -v /opt/cardano/cnode/db:/opt/cardano/cnode/db \
  $IMAGE_NAME

# Step 3: Verify the container is running
echo "Checking if the container is running..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
  echo "Cardano relay node is running."
else
  echo "Failed to start the container. Check logs with 'docker logs $CONTAINER_NAME'."
  exit 1
fi

# Step 4: Monitor sync progress (optional, runs in a loop every 60 seconds)
echo "Monitoring sync progress (press Ctrl+C to stop)..."
echo "Note: Docker group changes may require logout/login to take effect for the current session"
while true; do
  SYNC_PROGRESS=$(docker exec $CONTAINER_NAME cardano-cli query tip --mainnet | grep syncProgress)
  echo "Sync Progress: $SYNC_PROGRESS"
  sleep 60
done