#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/../utils/functions.sh"

if ! has "mkcert"; then

    curl --silent -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
    chmod +x mkcert-v*-linux-amd64
    sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert

    mkcert -install

else
    echo "mkcert is already installed."
fi

if [ ! -f ~/.local/share/mkcert/rootCA.crt ]; then
    mkcert -CAROOT
    CURRENT_PATH=$(pwd)
    cd ~/.local/share/mkcert
    explorer.exe .
    cd $CURRENT_PATH
    openssl x509 -in ~/.local/share/mkcert/rootCA.pem -out ~/.local/share/mkcert/rootCA.crt
else
    echo "mkcert root CA certificate already exists."
fi
