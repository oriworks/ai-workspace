#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/../utils/functions.sh"

if ! has "docker" || ! has "docker-compose"; then
    # https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh

    sudo usermod -aG docker $USER

    # Issue with traefik and docker api version
    # sudo mkdir /etc/systemd/system/docker.service.d
    # sudo bash -c 'echo -e "[Service]\nEnvironment=\"DOCKER_MIN_API_VERSION=1.24\"" >> /etc/systemd/system/docker.service.d/min_api_version.conf'

    sudo sed -i 's|^ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock$|ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock -H tcp://0.0.0.0:2375|' /lib/systemd/system/docker.service
    sudo systemctl daemon-reload
    sudo systemctl restart docker
else
    echo "Docker and Docker Compose are already installed."
fi

# docker version
