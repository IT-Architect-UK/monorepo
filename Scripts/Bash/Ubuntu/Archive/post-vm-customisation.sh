#!/bin/sh

echo "Updating Package Lists"

apt-get update

# Install Webmin

echo "Installing Webmin..."
# Add Webmin repository and install
wget -qO- http://www.webmin.com/jcameron-key.asc | apt-key add -
echo "deb http://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list.d/webmin.list
apt update
apt install -y webmin
systemctl restart webmin

echo "Disabling IPv6"

echo net.ipv6.conf.all.disable_ipv6=1 >> /etc/sysctl.conf
echo net.ipv6.conf.default.disable_ipv6=1 >> /etc/sysctl.conf
echo net.ipv6.conf.lo.disable_ipv6=1 >> /etc/sysctl.conf
sysctl -p

echo "Extending Disk Partitions If Space Is Available"

# Use growpart to extend the partition - it will use the available space
echo "Resizing partition /dev/sda3..."
growpart /dev/sda 3
# Part 2: Update the system's view of disk partitions
echo "Updating the system's view of disk partitions..."
partprobe /dev/sda
# Part 3: Resize the physical volume
echo "Resizing the LVM physical volume on /dev/sda3..."
pvresize /dev/sda3
# Part 4: Get the volume group name associated with the physical volume
VG_NAME=$(pvs --noheading -o vg_name /dev/sda3 | tr -d ' ')
echo "Volume group name obtained: $VG_NAME"
# Part 5: Extend the logical volume to occupy all of the free space in the volume group
# We assume there is only one logical volume in the volume group
LV_PATH=$(lvdisplay -C -o lv_path --noheading $VG_NAME | tr -d ' ')
echo "Logical volume path obtained: $LV_PATH"
# Part 6: Extend the logical volume
echo "Extending the logical volume to use all available space..."
lvextend -l +100%FREE $LV_PATH
# Part 7: Resize the filesystem
# This command works for ext4 filesystems, which can be online resized.
echo "Resizing the filesystem on $LV_PATH..."
resize2fs $LV_PATH
echo "Disk resize operations have completed successfully."

echo "Configuring Firewall Rules"

# Flush existing rules and set chain policies to DROP
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
# Allow all outbound traffic
iptables -A OUTPUT -j ACCEPT
# Allow established and related incoming connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Allow essential traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -s 192.168.0.0/16 -j ACCEPT
iptables -A INPUT -s 192.168.0.0/16 -p icmp -j ACCEPT
# Allow ICMP (Ping) from the 192.168.0.0/16 subnet
iptables -A INPUT -s 192.168.0.0/16 -p icmp -j ACCEPT

# Install iptables-persistent
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
# Save the rules
iptables-save | tee /etc/iptables/rules.v4 > /dev/null

echo "Configuring NTP"

apt-get install chrony -y
tee /etc/chrony/chrony.conf > /dev/null << EOF
pool pool.ntp.org iburst minpoll 1 maxpoll 2 maxsources 3
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 5.0
rtcsync
makestep 0.1 -1
EOF
# Restart the correct chrony service
systemctl restart --no-ask-password chrony.service
chronyc sources

# Set the default Gateway IP

# Get the host's primary IP address
host_ip=$(hostname -I | awk '{print $1}')
if [ -z "$host_ip" ]; then
    echo "Failed to retrieve the host IP address."
    exit 1
fi
# Extract subnet from host IP and set new default gateway and nameserver IP
subnet=$(echo $host_ip | cut -d '.' -f1-3)
new_gateway_and_nameserver_ip="${subnet}.1"
# Update resolv.conf: Remove all nameserver entries, then add the new gateway and nameserver IP
{
    # Retain non-nameserver lines
    awk '!/nameserver/ {print}' /etc/resolv.conf;
    # Add the new gateway and nameserver IP as the nameserver
    echo "nameserver $new_gateway_and_nameserver_ip";
} | sudo tee /etc/resolv.conf.tmp > /dev/null
# Rename the temporary file to resolv.conf
sudo mv /etc/resolv.conf.tmp /etc/resolv.conf
echo "Done!"

echo "Customisation Complete"

reboot

fi
