#!/bin/bash

# Update the system
sudo apt update
sudo apt upgrade -y

# Clean up the system
sudo apt autoremove -y
sudo apt clean
sudo apt-get clean

# Remove SSH host keys
sudo rm /etc/ssh/ssh_host_*

# Reset machine ID
sudo rm /etc/machine-id
sudo systemd-machine-id-setup

# Clear logs
sudo truncate -s 0 /var/log/*.log

# Clear temporary files
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Clear command history
sudo cat /dev/null > ~/.bash_history

# Shutdown the system
sudo shutdown now