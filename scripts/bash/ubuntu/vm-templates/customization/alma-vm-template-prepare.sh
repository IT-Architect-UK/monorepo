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

# Disable IPv6
# Add GRUB parameters
sudo sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# Set sysctl to disable IPv6
echo -e "net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1" | sudo tee /etc/sysctl.d/99-disable-ipv6.conf
sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf

# Disable IPv6 in NetworkManager
sudo nmcli connection modify "$(nmcli -t -f UUID,TYPE connection show | grep ethernet | cut -d: -f1)" ipv6.method disabled
sudo systemctl restart NetworkManager

# Clear machine ID (safely)
sudo truncate -s 0 /etc/machine-id
sudo touch /etc/machine-id

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

# Ensure dbus-broker starts after dependencies
sudo sed -i '/^After=/ s/$/ network.target systemd-udev.service/' /usr/lib/systemd/system/dbus-broker.service
sudo systemctl daemon-reload

# Disable cloud-init to prevent loops
sudo systemctl disable cloud-init cloud-init-local --now
sudo rm -rf /var/lib/cloud/*
sudo rm -f /var/log/cloud-init*

# Shutdown the system
sudo systemctl poweroff