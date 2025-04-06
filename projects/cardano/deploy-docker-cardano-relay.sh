#!/bin/bash

# Define variables
DATA_DIR="/var/cardano/data"
IMAGE_NAME="cardanocommunity/cardano-node:latest"
CONTAINER_NAME="cardano-relay-node"

# Step 1: Pull the latest Docker image
echo "Pulling the latest Cardano node image..."
docker pull $IMAGE_NAME

# Step 2: Create the data directory if it doesn't exist
echo "Creating data directory at $DATA_DIR..."
mkdir -p $DATA_DIR

# Step 3: Download mainnet configuration files
echo "Downloading mainnet configuration files..."
cd $DATA_DIR
curl -O https://book.world.dev.cardano.org/environments/mainnet/config.json
curl -O https://book.world.dev.cardano.org/environments/mainnet/topology.json
curl -O https://book.world.dev.cardano.org/environments/mainnet/byron-genesis.json
curl -O https://book.world.dev.cardano.org/environments/mainnet/shelley-genesis.json
curl -O https://book.world.dev.cardano.org/environments/mainnet/alonzo-genesis.json
curl -O https://book.world.dev.cardano.org/environments/mainnet/conway-genesis.json

# Step 4: Run the Docker container
echo "Starting the Cardano relay node container..."
docker run -d \
  --name $CONTAINER_NAME \
  -v $DATA_DIR:/opt/cardano/data \
  -e NETWORK=mainnet \
  -p 3001:3001 \
  $IMAGE_NAME

# Step 5: Verify the node is running
echo "Checking if the container is running..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
  echo "Cardano relay node is running."
else
  echo "Failed to start the container. Check logs with 'docker logs $CONTAINER_NAME'."
  exit 1
fi

# Step 6: Monitor sync progress (optional, runs in a loop every 60 seconds)
echo "Monitoring sync progress (press Ctrl+C to stop)..."
while true; do
  SYNC_PROGRESS=$(docker exec $CONTAINER_NAME cardano-cli query tip --mainnet | grep syncProgress)
  echo "Sync Progress: $SYNC_PROGRESS"
  sleep 60
done