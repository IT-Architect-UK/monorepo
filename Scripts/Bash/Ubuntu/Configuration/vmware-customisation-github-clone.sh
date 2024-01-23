#!/bin/sh

if [ x$1 = x"precustomization" ]; then
    echo "Do Precustomization tasks"

elif [ x$1 = x"postcustomization" ]; then
    echo "Do Postcustomization tasks"

echo "Setting Variables"
LOG_FILE="/logs/vmware-customisation-github-clone.log"
SOURCE_FILES_DIR="/source-files"
REPO_URL="https://github.com/IT-Architect-UK/Monorepo.git"
REPO_NAME=$(basename -s .git "$REPO_URL")
TARGET_DIR="$SOURCE_FILES_DIR/github/$REPO_NAME"

echo "Creating Directories"
mkdir -p /logs
mkdir -p /source-files/github
mkdir -p /source-files/scripts

apt update

echo "Installing Git"
apt-get install git -y

echo "Cloning Monorepo"
mkdir -p "$TARGET_DIR"
git clone "$REPO_URL" "$TARGET_DIR"
cd /source-files/github/Monorepo/Scripts/Bash/Ubuntu/ServerRoles
chmod +x *.sh

reboot

fi