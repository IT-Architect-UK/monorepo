#!/bin/bash

# Variables
DB_NAME=wordpress
DB_USER=wp_user
WP_DIR=/var/www/wordpress
LOG_DIR=/logs
LOG_FILE=$LOG_DIR/wordpress_installation.log

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Create log directory if it does not exist
mkdir -p $LOG_DIR

# Prompt for the WordPress database password
echo -n "Enter the WordPress database password: "
read -s DB_PASSWORD
echo

# Validate if password was entered
if [ -z "$DB_PASSWORD" ]; then
    echo "No password entered, exiting..."
    exit 1
fi

# Update System Packages
echo "Updating system packages..." | tee -a $LOG_FILE
apt-get update >> $LOG_FILE 2>&1

# Install Apache, MySQL, PHP, and required PHP extensions
echo "Installing Apache, MySQL, PHP..." | tee -a $LOG_FILE
apt-get install apache2 mysql-server php php-mysql libapache2-mod-php php-xml php-gd php-curl php-mbstring -y >> $LOG_FILE 2>&1

# Start Apache and MySQL
echo "Starting Apache and MySQL..." | tee -a $LOG_FILE
systemctl start apache2 >> $LOG_FILE 2>&1
systemctl enable apache2 >> $LOG_FILE 2>&1
systemctl start mysql >> $LOG_FILE 2>&1
systemctl enable mysql >> $LOG_FILE 2>&1

# Secure MySQL installation
echo "Securing MySQL installation..." | tee -a $LOG_FILE
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "FLUSH PRIVILEGES;"

# Create MySQL Database and User for WordPress
echo "Creating MySQL Database and User for WordPress..." | tee -a $LOG_FILE
mysql -u root -e "CREATE DATABASE $DB_NAME; CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD'; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" >> $LOG_FILE 2>&1

# Download and Install WordPress
echo "Downloading and Installing WordPress..." | tee -a $LOG_FILE
wget -q -O - "https://wordpress.org/latest.tar.gz" | tar xz -C /var/www/
mv /var/www/wordpress $WP_DIR
chown -R www-data:www-data $WP_DIR

# Configure Apache for WordPress
echo "Configuring Apache for WordPress..." | tee -a $LOG_FILE
cat << EOF > /etc/apache2/sites-available/wordpress.conf
<VirtualHost *:80>
    DocumentRoot $WP_DIR
    <Directory $WP_DIR>
        Options FollowSymLinks
        AllowOverride Limit Options FileInfo
        DirectoryIndex index.php
        Require all granted
    </Directory>
    <Directory $WP_DIR/wp-content>
        Options FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite wordpress.conf # Enable WordPress Site
a2enmod rewrite # Enable Apache Rewrite Module
a2dissite 000-default.conf # Disable Default Site
systemctl reload apache2 # Reload Apache

echo "WordPress installation completed." | tee -a $LOG_FILE
