#!/bin/bash

# Get the currently logged-in user
current_user=$(whoami)
echo "Current user: $current_user"
export current_user

echo "Disabling Non-Root Users Excluding the Logged on User"
# Get the username of the user executing the script (even if using sudo)
logged_in_user=$(who am i | awk '{print $1}')
# Disable all non-root users except the user executing the script
getent passwd | while IFS=: read -r username _ uid _; do
    if [ "$uid" -ge 1000 ] && [ "$username" != "root" ] && [ "$username" != "nobody" ] && [ "$username" != "$logged_in_user" ]; then
        sudo passwd -l "$username"
        echo "User $username has been disabled."
    fi
done

echo "Updating the system ..."
sudo apt update && sudo apt upgrade -y

echo "Installing prerequisites ..."
sudo apt install apt-transport-https ca-certificates curl software-properties-common git rsync tmux htop -y

echo "Installing Docker ..."
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

echo "Downloading Guild Operator Tools ..."
mkdir "$HOME/tmp";cd "$HOME/tmp"
curl -sS -o guild-deploy.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/guild-deploy.sh
chmod 755 guild-deploy.sh

echo "Running the Guild Operators Pre-reqs Installation Script ..."
./guild-deploy.sh -b master -n mainnet -t cnode -s pbld
source ~/.bashrc

echo "Set Cardano File System Permissions ..."
sudo chown -R ${current_user}:${current_user} /opt/cardano
sudo chmod -R 0774 /opt/cardano

echo "Cloning the IOHK Cardano Node Repo ..."
mkdir "$HOME/git";cd "$HOME/git"
cd ~/git
git clone https://github.com/input-output-hk/cardano-node

# Add the current user to the docker group (to run Docker without sudo)
sudo usermod -aG docker ${current_user}
newgrp docker
