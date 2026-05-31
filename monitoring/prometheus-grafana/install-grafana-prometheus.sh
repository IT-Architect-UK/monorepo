#!/bin/bash

# Exit on any error
set -e

# Update system
echo "Updating system..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install prerequisites
echo "Installing prerequisites..."
sudo apt-get install -y software-properties-common curl

# Add Prometheus user and group
echo "Creating Prometheus user and group..."
sudo useradd --no-create-home --shell /bin/false prometheus

# Create directories and set permissions
echo "Setting up directories for Prometheus..."
sudo mkdir /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Download and unpack Prometheus
echo "Downloading and setting up Prometheus..."
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.32.0/prometheus-2.32.0.linux-amd64.tar.gz
tar xvf prometheus-2.32.0.linux-amd64.tar.gz
sudo cp prometheus-2.32.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.32.0.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
sudo cp -r prometheus-2.32.0.linux-amd64/consoles /etc/prometheus
sudo cp -r prometheus-2.32.0.linux-amd64/console_libraries /etc/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries
rm -rf prometheus-2.32.0.linux-amd64.tar.gz prometheus-2.32.0.linux-amd64

# Setup Prometheus configuration
echo "Configuring Prometheus..."
cat <<EOL | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
EOL
sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Setup Prometheus systemd service
echo "Setting up Prometheus as a service..."
cat <<EOL | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOL

# Start Prometheus
echo "Starting Prometheus..."
sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus

# Install Grafana
echo "Installing Grafana..."
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
curl https://packages.grafana.com/gpg.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/grafana.gpg add -
sudo apt-get update -y
sudo apt-get install grafana -y
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

echo "Installation complete!"
