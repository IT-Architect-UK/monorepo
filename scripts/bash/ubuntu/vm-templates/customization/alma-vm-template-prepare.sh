#!/bin/bash

# Update the system
sudo dnf makecache
sudo dnf upgrade -y

# Install necessary packages
sudo dnf install -y open-vm-tools perl git

# Enable and start VMware Tools service
sudo systemctl enable --now vmtoolsd

# Enable Template Customization
sudo mkdir -p /etc/vmware-tools
echo -e "[deployPkg]\nenable-custom-scripts = true" | sudo tee -a /etc/vmware-tools/tools.conf
sudo chmod 644 /etc/vmware-tools/tools.conf

# Clean up the system
sudo dnf autoremove -y
sudo dnf clean all

# Remove SSH host keys
sudo rm -f /etc/ssh/ssh_host_*

# Cleanup network configuration
sudo rm -f /etc/NetworkManager/system-connections/*
sudo truncate -s 0 /etc/hostname
sudo hostnamectl set-hostname ""

# Reset machine ID
sudo rm -f /etc/machine-id

# Clear logs
sudo truncate -s 0 /var/log/*.log
sudo rm -rf /var/log/vmware-imc/*
sudo rm -rf /var/log/vmware-customisation.log
sudo rm -rf /var/log/repo_refresh.log

# Clear temporary files
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Clear command history
sudo truncate -s 0 ~/.bash_history

# Ensure SSH allows password authentication
sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sshd -t
sudo systemctl restart sshd

# Shutdown the system
sudo systemctl poweroff