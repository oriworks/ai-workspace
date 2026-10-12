#!/bin/bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$CURRENT_DIR/utils/common.sh"

require k3d


step "Cluster ${CLUSTER_NAME}"

k3d cluster delete "$CLUSTER_NAME"

if [ "${1:-}" = "--all" ]; then
    step "Registry ${REGISTRY_NAME}:${REGISTRY_PORT}"
    
    k3d registry delete "${REGISTRY_CONTAINER}"
fi
