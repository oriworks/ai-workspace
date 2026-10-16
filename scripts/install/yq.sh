#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/../utils/functions.sh"

VERSION=v4.2.0

if ! has "yq"; then
    echo "yq is not installed. Installing yq..."

    # For AMD64 / x86_64
    if [ $(uname -m) = x86_64 ]; then
        sudo wget https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_amd64 -O /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
    fi

    # For ARM64 / aarch64
    if [ $(uname -m) = aarch64 ]; then
        sudo wget https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_arm64 -O /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
    fi

else
    echo "yq is already installed."
fi

# yq -V

