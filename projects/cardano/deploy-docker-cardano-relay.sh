#!/bin/bash

# Define variables
IMAGE_NAME="cardanocommunity/cardano-node:latest"
CONTAINER_NAME="cardano-relay-node"
LOCAL_VOLUMES="/opt/cardano/cnode"
SOCKET_PATH="/opt/cardano/cnode/sockets/node.socket"
USER="guild"
GROUP="guild"

# Get UID and GID of the guild user
UID=$(id -u "$USER")
GID=$(id -g "$GROUP")

# Step 0: Ensure proper permissions on the local volumes
echo "Setting permissions for $LOCAL_VOLUMES..."
if [ ! -d "$LOCAL_VOLUMES" ]; then
  echo "Directory $LOCAL_VOLUMES does not exist, creating it..."
  sudo mkdir -p "$LOCAL_VOLUMES/priv" "$LOCAL_VOLUMES/db" "$LOCAL_VOLUMES/sockets" "$LOCAL_VOLUMES/files"
fi

# Change ownership to guild:guild and set full permissions
sudo chown -R "$USER:$GROUP" "$LOCAL_VOLUMES"
sudo chmod -R 770 "$LOCAL_VOLUMES"

# Step 1: Pull the latest Docker image
echo "Pulling the latest Cardano node image..."
docker pull "$IMAGE_NAME"

# Step 2: Stop and remove any existing container
docker stop "$CONTAINER_NAME" 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null

# Step 3: Run the Docker container with matching UID/GID
echo "Starting the Cardano relay node container..."
docker run --init -dit \
  --name "$CONTAINER_NAME" \
  --security-opt=no-new-privileges \
  --user "$UID:$GID" \
  -e NETWORK=mainnet \
  -e CNODE_HOME=/opt/cardano/cnode \
  -e CARDANO_NODE_SOCKET_PATH="$CNODE_HOME/sockets/node.socket" \
  -e MITHRIL_DOWNLOAD=Y \
  -e NWMAGIC="" \
  -p 6000:6000 \
  -v "$LOCAL_VOLUMES/priv:/opt/cardano/cnode/priv" \
  -v "$LOCAL_VOLUMES/db:/opt/cardano/cnode/db" \
  -v "$LOCAL_VOLUMES/sockets:/opt/cardano/cnode/sockets" \
  -v "$LOCAL_VOLUMES/files:/opt/cardano/cnode/files" \
  "$IMAGE_NAME"

# Step 4: Verify the container is running
echo "Checking if the container is running..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
  echo "Cardano relay node is running. Initial logs:"
  docker logs "$CONTAINER_NAME"
else
  echo "Failed to start the container. Check logs with 'docker logs $CONTAINER_NAME'."
  exit 1
fi

# Step 5: Wait for socket to be available
echo "Waiting for node socket to be available (timeout 10 minutes)..."
TIMEOUT=600
ELAPSED=0
until docker exec "$CONTAINER_NAME" test -S "$SOCKET_PATH"; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "Timeout waiting for socket. Check logs for details:"
    docker logs "$CONTAINER_NAME"
    echo "Checking running processes:"
    docker exec "$CONTAINER_NAME" ps aux
    exit 1
  fi
  echo "Socket not ready yet, waiting 10 seconds... (Elapsed: $ELAPSED seconds)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
echo "Node socket is available."

# Step 6: Wait for container to become healthy
echo "Waiting for container to become healthy (timeout 5 minutes)..."
TIMEOUT=300
ELAPSED=0
until [ "$(docker inspect --format='{{.State.Health.Status}}' $CONTAINER_NAME)" == "healthy" ]; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "Timeout waiting for container to become healthy. Check logs:"
    docker logs "$CONTAINER_NAME"
    exit 1
  fi
  echo "Container not healthy yet, waiting 10 seconds... (Elapsed: $ELAPSED seconds)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
echo "Container is healthy."

# Step 7: Monitor sync progress (optional, runs in a loop every 60 seconds)
echo "Monitoring sync progress (press Ctrl+C to stop)..."
while true; do
  SYNC_PROGRESS=$(docker exec "$CONTAINER_NAME" cardano-cli query tip --mainnet --socket-path "$SOCKET_PATH" | grep syncProgress)
  echo "Sync Progress: $SYNC_PROGRESS"
  sleep 60
done