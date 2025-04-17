#!/bin/bash

# Define variables
IMAGE_NAME="cardanocommunity/cardano-node:latest"
CONTAINER_NAME="cardano-relay-node"
LOCAL_VOLUMES="/opt/cardano/cnode"
SOCKET_PATH="/opt/cardano/cnode/sockets/node.socket"
USER="guild"
GROUP="guild"

# Get UID and GID of the guild user
GUILD_UID=$(id -u "$USER")
GUILD_GID=$(id -g "$GROUP")

# Step 0: Ensure proper permissions on the local volumes
echo "Setting permissions for $LOCAL_VOLUMES..."
if [ ! -d "$LOCAL_VOLUMES" ]; then
  echo "Directory $LOCAL_VOLUMES does not exist, creating it..."
  sudo mkdir -p "$LOCAL_VOLUMES/priv" "$LOCAL_VOLUMES/db" "$LOCAL_VOLUMES/sockets" "$LOCAL_VOLUMES/files"
fi

# Change ownership to guild:guild and set permissions
sudo chown -R "$USER:$GROUP" "$LOCAL_VOLUMES"
sudo chmod -R u=rwX,g=rwX,o= "$LOCAL_VOLUMES"

# Step 1: Pull the latest Docker image
echo "Pulling the latest Cardano node image..."
docker pull "$IMAGE_NAME"

# Step 2: Stop and remove any existing container
docker stop "$CONTAINER_NAME" 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null

# Step 3: Run the Docker container as guild user with permission fix
echo "Starting the Cardano relay node container..."
docker run --init -dit \
  --name "$CONTAINER_NAME" \
  --security-opt=no-new-privileges \
  -u "$GUILD_UID:$GUILD_GID" \
  -e NETWORK=mainnet \
  -e MITHRIL_DOWNLOAD=Y \
  -p 6000:6000 \
  -v "$LOCAL_VOLUMES/priv:/opt/cardano/cnode/priv" \
  -v "$LOCAL_VOLUMES/db:/opt/cardano/cnode/db" \
  "$IMAGE_NAME"


# Step 4: Verify the container is running
echo "Checking if the container is running..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
  echo "Cardano relay node is running. Initial logs:"
  docker logs "$CONTAINER_NAME" --tail 20
else
  echo "Failed to start the container. Check logs with 'docker logs $CONTAINER_NAME'."
  exit 1
fi

# Step 5: Wait for container to become healthy
echo "Waiting for container to become healthy (timeout 5 minutes)..."
TIMEOUT=300
ELAPSED=0
until [ "$(docker inspect --format='{{.State.Health.Status}}' $CONTAINER_NAME)" == "healthy" ]; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "Timeout waiting for container to become healthy. Check logs:"
    docker logs "$CONTAINER_NAME" --tail 50
    exit 1
  fi
  echo "Container not healthy yet, waiting 10 seconds... (Elapsed: $ELAPSED seconds)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
echo "Container is healthy."

exit 0