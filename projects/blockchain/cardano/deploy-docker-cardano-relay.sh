#!/bin/bash

# This script deploys a Cardano node and Prometheus using Docker on Ubuntu 24.
# It also configures IPTABLES to allow inbound traffic on port 3001 for the Cardano node.

# Ensure the script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo."
  exit 1
fi

# Configure IPTABLES for Cardano node
echo "Configuring IPTABLES..."
if ! dpkg -s iptables-persistent > /dev/null 2>&1; then
  echo "iptables-persistent is not installed. Installing and configuring..."
  # Add the IPTABLES rule for Cardano node
  iptables -A INPUT -p tcp --dport 3001 -j ACCEPT
  # Set debconf selections to autosave rules
  echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
  echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
  # Install iptables-persistent
  apt-get install -y iptables-persistent
else
  echo "iptables-persistent is already installed."
  # Check if the rule already exists
  if ! iptables -C INPUT -p tcp --dport 3001 -j ACCEPT > /dev/null 2>&1; then
    echo "Adding IPTABLES rule for port 3001..."
    iptables -A INPUT -p tcp --dport 3001 -j ACCEPT
    # Save the rules
    netfilter-persistent save
  else
    echo "IPTABLES rule for port 3001 already exists."
  fi
fi

# Pull the Cardano node Docker image
echo "Pulling Cardano node Docker image..."
docker pull ghcr.io/blinklabs-io/cardano-node

# Create Docker volumes for Cardano data and IPC
echo "Creating Docker volumes..."
docker volume create cardano-data
docker volume create cardano-ipc

# Create a Docker network for the containers
echo "Creating Docker network..."
docker network create cardano-network

# Run the Cardano node container with Mithril enabled for faster initial download
echo "Running Cardano node container..."
docker run --detach --name cardano-node \
  --network cardano-network \
  -e NETWORK=mainnet \
  -v cardano-data:/opt/cardano/data \
  -v cardano-ipc:/opt/cardano/ipc \
  -p 3001:3001 \
  -p 12798:12798 \
  ghcr.io/blinklabs-io/cardano-node

# Pull the Prometheus Docker image for monitoring
echo "Pulling Prometheus Docker image..."
docker pull prom/prometheus

# Create a prometheus.yml configuration file to scrape metrics from the Cardano node
echo "Creating Prometheus configuration..."
cat <<EOF > prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'cardano-node'
    static_configs:
      - targets: ['cardano-node:12798']
EOF

# Run the Prometheus container
echo "Running Prometheus container..."
docker run --detach --name prometheus \
  --network cardano-network \
  -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
  -p 9090:9090 \
  prom/prometheus

echo "Cardano node and Prometheus are running."
echo "Access Prometheus at http://localhost:9090"