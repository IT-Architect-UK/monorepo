#!/bin/bash

: '
.SYNOPSIS
This script executes a series of scripts for server baseline configuration.

.DESCRIPTION
- This script is used to install Grafana, Prometheus, and Docker on a Ubuntu Server.
- It will install Docker, Docker Compose, Grafana, and Prometheus.
- It will also configure Prometheus to scrape the Node Exporter.

.NOTES
Version:            1.0
Author:             Darren Pilkington
Modification Date:  31-05-2024
'

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/install-grafana-prometheus-docker.log"

# Ensure log directory exists
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
    echo "Created log directory: ${LOG_DIR}"
fi

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE"
}

write_log "Starting update and upgrade of the system"
sudo apt-get update && sudo apt-get upgrade -y

##############################################################################################################################################################################################################
write_log "Installing Docker ..."

# Add Docker's GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker's repository to APT sources
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

write_log "Docker installed and started"

##############################################################################################################################################################################################################

write_log "Installing Node Exporter ..."

# Download Node Exporter
cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.3.1.linux-amd64.tar.gz
sudo cp node_exporter-1.3.1.linux-amd64/node_exporter /usr/local/bin/
sudo useradd -rs /bin/false node_exporter

# Create Node Exporter service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

# Start and enable Node Exporter service
sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

write_log "Node Exporter installed and started"

##############################################################################################################################################################################################################

write_log "Installing Prometheus ..."

# Create a directory for Prometheus configuration
sudo mkdir -p /etc/prometheus

# Get the FQDN of the server
FQDN=$(hostname -f)

# Create a Prometheus configuration file
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['$FQDN:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['$FQDN:9100']

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - "alertmanager:9093"
EOF

# Pull and run Prometheus Docker container using Ubuntu image
docker run -d \
  -p 9090:9090 \
  --name prometheus \
  -v /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  ubuntu/prometheus

write_log "Prometheus installed and started"

# Instructions for setting up Windows Exporter and SNMP Exporter (requires manual setup)
echo "To monitor Windows systems, install the windows_exporter on the target machine from https://github.com/prometheus-community/windows_exporter."
echo "To monitor network devices using SNMP, configure the SNMP Exporter by following the guide at https://github.com/prometheus/snmp_exporter."

##############################################################################################################################################################################################################

write_log "Installing Grafana ..."

docker volume create grafana-storage

# Pull and run Grafana Docker container using official Grafana image
docker run -d \
  -p 3000:3000 \
  --name=grafana \
  -v grafana-storage:/var/lib/grafana \
  grafana/grafana

# Wait for Grafana to start
sleep 10

# Configure Grafana datasource
GRAFANA_DATASOURCE='{
  "name": "Prometheus",
  "type": "prometheus",
  "access": "proxy",
  "url": "http://'"$FQDN"':9090",
  "basicAuth": false,
  "isDefault": true
}'

curl -X POST \
  -H "Content-Type: application/json" \
  -d "${GRAFANA_DATASOURCE}" \
  admin:admin@localhost:3000/api/datasources

write_log "Grafana installed and datasource configured"

# Configure Firewall using iptables
write_log "Configuring firewall"
sudo iptables -A INPUT -p tcp --dport 9090 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9100 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
# Save the rules
if sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null; then
    write_log "IPTables rules saved successfully."
else
    write_log "Error occurred while saving IPTables rules."
    exit 1
fi

# Print completion message
echo "Prometheus and Node Exporter have been set up and are running on Docker."
echo "Prometheus is accessible at http://$FQDN:9090"
echo "Node Exporter is accessible at http://$FQDN:9100"
echo "Grafana is accessible at http://$FQDN:3000 (default login: admin/admin)"
echo "Remember to configure Windows Exporter and SNMP Exporter as needed."

write_log "Script execution completed"
