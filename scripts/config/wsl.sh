#!/bin/bash

# Update and upgrade packages to ensure we have the latest versions and security patches.
sudo apt update -y && sudo apt upgrade -y

# Install common utilities
sudo apt install -y binfmt-support build-essential unzip zip sshpass libnss3-tools ripgrep btop neovim jq direnv

# sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /usr/lib/binfmt.d/WSLInterop.conf'
# sudo systemctl restart systemd-binfmt