#!/bin/bash

#######################################################################################################################################################
#                                                                                                                                                     #
# This script is used to install Grafana, Prometheus and Docker on a Ubuntu Server.                                                                   #
# It will install Docker, Docker Compose, Grafana and Prometheus.                                                                                     #
# It will also configure Prometheus to scrape the Node Exporter and Windows Exporter.                                                                 #
#                                                                                                                                                     #
#######################################################################################################################################################

apt-get update && sudo apt-get upgrade

#############################
echo "Installing Docker ..."
#############################
# Add Docker's GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
# Add Docker's repository to APT sources
sudo echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
# Add the repository to Apt sources:
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

#######################################################################################################################################################

################################
echo "Installing Prometheus ..."
################################

# Update package lists and install prerequisites
sudo apt-get update
sudo apt-get install -y curl

# Create a directory for Prometheus configuration
mkdir -p ~/prometheus

# Create a Prometheus configuration file
cat <<EOF > ~/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['node_exporter:9100']

  - job_name: 'windows_exporter'
    static_configs:
      - targets: ['windows_exporter:9182']

  - job_name: 'network_devices'
    static_configs:
      - targets: ['network_device_ip:snmp_port']
        params:
          module: [if_mib]
        relabel_configs:
          - source_labels: [__address__]
            regex: (.*)
            target_label: __param_target
            replacement: ${1}
          - source_labels: [__param_target]
            target_label: instance

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      # - "alertmanager:9093"
EOF

# Pull and run Prometheus Docker container
docker run -d \
  -p 9090:9090 \
  --name prometheus \
  -v ~/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

# Pull and run Node Exporter Docker container
docker run -d \
  -p 9100:9100 \
  --name node_exporter \
  prom/node-exporter

# Instructions for setting up Windows Exporter and SNMP Exporter (requires manual setup)
echo "To monitor Windows systems, install the windows_exporter on the target machine from https://github.com/prometheus-community/windows_exporter."
echo "To monitor network devices using SNMP, configure the SNMP Exporter by following the guide at https://github.com/prometheus/snmp_exporter."

#######################################################################################################################################################

##############################
echo "Installing Grafana ..."
##############################

docker volume create grafana-storage

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
  "url": "http://prometheus:9090",
  "basicAuth": false,
  "isDefault": true
}'

curl -X POST \
  -H "Content-Type: application/json" \
  -d "${GRAFANA_DATASOURCE}" \
  admin:admin@localhost:3000/api/datasources

# Print completion message
echo "Prometheus and Node Exporter have been set up and are running on Docker."
echo "Prometheus is accessible at http://localhost:9090"
echo "Node Exporter is accessible at http://localhost:9100"
echo "Grafana is accessible at http://localhost:3000 (default login: admin/admin)"
echo "Remember to configure Windows Exporter and SNMP Exporter as needed."