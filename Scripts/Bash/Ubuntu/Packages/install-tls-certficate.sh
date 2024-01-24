#!/bin/bash

# Variables
LOG_DIR=/logs
LOG_FILE=$LOG_DIR/certbot_installation.log

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Create log directory if it does not exist
mkdir -p $LOG_DIR

# Prompt for the domain name
echo -n "Enter the domain name for the SSL certificate: "
read DOMAIN_NAME

# Validate if domain name was entered
if [ -z "$DOMAIN_NAME" ]; then
    echo "No domain name entered, exiting..."
    exit 1
fi

# Prompt for the email address
echo -n "Enter your email address for certificate notifications: "
read EMAIL

# Validate if email was entered
if [ -z "$EMAIL" ]; then
    echo "No email address entered, exiting..."
    exit 1
fi

# Update System Packages
echo "Updating system packages..." | tee -a $LOG_FILE
apt-get update >> $LOG_FILE 2>&1

# Install Certbot
echo "Installing Certbot..." | tee -a $LOG_FILE
apt-get install software-properties-common -y >> $LOG_FILE 2>&1
add-apt-repository ppa:certbot/certbot -y >> $LOG_FILE 2>&1
apt-get update >> $LOG_FILE 2>&1
apt-get install certbot python-certbot-apache -y >> $LOG_FILE 2>&1

# Obtain and Install Let's Encrypt Certificate
echo "Obtaining and Installing Let's Encrypt Certificate for $DOMAIN_NAME..." | tee -a $LOG_FILE
certbot --apache -m $EMAIL --agree-tos --no-eff-email -d $DOMAIN_NAME >> $LOG_FILE 2>&1

echo "SSL certificate installation completed." | tee -a $LOG_FILE
