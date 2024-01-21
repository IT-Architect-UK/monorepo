#!/bin/sh

if [ x$1 = x"precustomization" ]; then
    echo "Do Precustomization tasks"

elif [ x$1 = x"postcustomization" ]; then
    echo "Do Postcustomization tasks"

echo "Updating Package Lists"

apt-get update

echo "Checking if Git is installed..."

if ! command -v git &> /dev/null; then
    echo "Git could not be found, installing now..."
    sudo apt-get install git -y
    echo "Git has been installed."
else
    echo "Git is already installed."
fi

echo "Creating Source-Files Directory"
mkdir -p /source-files
SOURCE_FILES_DIR=/source-files

echo "Cloning GitHub Repository"
REPO_URL="https://github.com/IT-Architect-UK/Monorepo.git"
REPO_NAME=$(basename -s .git "$REPO_URL")
TARGET_DIR=$SOURCE_FILES_DIR/github/$REPO_NAME

echo "Preparing to clone repository..."

if [ -d "$TARGET_DIR" ]; then
    echo "Target directory already exists, cloning repository..."
    git clone $REPO_URL $TARGET_DIR
    echo "Repository cloned successfully."
else
    echo "Creating target directory..."
    mkdir -p $TARGET_DIR
    git clone $REPO_URL $TARGET_DIR
    echo "Repository cloned successfully."
fi

fi
