#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/../utils/functions.sh"

SSH_KEY_PATH=~/.ssh/id_rsa

git config --global init.defaultBranch main
git config --global core.hooksPath hooks

if [ -f "$SSH_KEY_PATH" ]; then
    echo "SSH key already exists at $SSH_KEY_PATH"
else
    echo "Copying SSH key from user ${WINDOWS_USER}..."
    cp -r /mnt/c/Users/${WINDOWS_USER}/.ssh ~/
    chmod 600 $SSH_KEY_PATH
fi

git config --list --show-origin