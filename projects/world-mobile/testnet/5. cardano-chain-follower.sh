#!/usr/bin/env bash

# Set Variables
aya_home=/opt/aya

# Prompt for ACCOUNT with a default value
read -p "Enter ACCOUNT (default: Skint-Earth-Node-1): " ACCOUNT
ACCOUNT=${ACCOUNT:-Skint-Earth-Node-1}
echo "Configured ACCOUNT: $ACCOUNT"

# Create Chain Follower File System
sudo mkdir -p /opt/aya/ccf
sudo chown -R ${USER}:${USER} /opt/aya/ccf

# Install Dependencies
sudo apt-get update
sudo apt install libpq-dev -y
sudo apt-get -q install unzip -y

# Download Chain Follower Binaries
mkdir -p ${HOME}/earthnode_installer/ccf
cd ${HOME}/earthnode_installer/ccf
wget https://cdn.discordapp.com/attachments/1072502970027081749/1144181313583186002/wm_230824_ccf_rev2.zip
unzip wm_230824_ccf_rev2.zip

# Copy Source Files to Chain Follower File System
cp ${HOME}/earthnode_installer/ccf/aya_chain_follower "${aya_home}"/ccf
cp ${HOME}/earthnode_installer/ccf/daemon_wm.toml "${aya_home}"/ccf

# Create systemd service file that describes the background service running the 'aya_chain_follower' daemon
sudo tee /etc/systemd/system/chain_follower.service > /dev/null <<EOF
# Create systemd service file that describes the background service running the 'aya_chain_follower' daemon.
[Unit]
Description=Cardano Chain Follower
After=network-online.target

[Service]
# Execute daemon from user account
User=${USER}
# Set working directory
WorkingDirectory=${aya_home}/ccf/
# Start the 'aya_chain_follower' daemon with providing configuration file path
ExecStart=${aya_home}/ccf/aya_chain_follower daemon --config ${aya_home}/ccf/daemon_wm.toml
# Restart the service if it fails
Restart=always
# Restart the service after 3 seconds if it fails
RestartSec=3

[Install]
# Start the service on system boot
WantedBy=multi-user.target
EOF

# Reload the Systemd daemon
sudo systemctl daemon-reload
# Enable the 'chain_follower' service to start on system boot
sudo systemctl enable chain_follower
sudo systemctl status chain_follower
sudo systemctl start chain_follower.service
sudo systemctl status chain_follower.service

ayad tx cce set-val-acc --home /opt/aya --from $ACCOUNT --chain-id aya_preview_501 -y
sleep 120 # wait for first transaction to complete
ayad tx chainfollower send-root --home /opt/aya --from $ACCOUNT --chain-id aya_preview_501 -y
sleep 120 # wait for second transaction to complete
operator_address=$(ayad tendermint show-address --home /opt/aya)
ayad query chainfollower list-root | grep $operator_address
