#!/bin/bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$CURRENT_DIR/utils/common.sh"

require docker k3d kubectl

REGISTRY="${REGISTRY_NAME}:${REGISTRY_PORT}"
step "Registry ${REGISTRY}"

if docker container inspect "$REGISTRY_CONTAINER" > /dev/null 2>&1; then
    docker start "$REGISTRY_CONTAINER" > /dev/null
    echo "Started registry container $REGISTRY_CONTAINER."
else
    k3d registry create "$REGISTRY_NAME" --port "0.0.0.0:${REGISTRY_PORT}"
fi

if docker info --format '{{range .RegistryConfig.InsecureRegistryCIDRs}}{{.}} {{end}}{{range $k, $v := .RegistryConfig.IndexConfigs}}{{if not $v.Secure}}{{$k}} {{end}}{{end}}' | grep -qw "$REGISTRY"; then
    echo "Docker already trusts $REGISTRY as insecure registry."
else
    DAEMON_JSON=/etc/docker/daemon.json
    sudo python3 - "$DAEMON_JSON" "$REGISTRY" <<'PY'
import json, os, sys
path, registry = sys.argv[1], sys.argv[2]
config = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
registries = config.setdefault("insecure-registries", [])
if registry not in registries:
    registries.append(registry)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY
    sudo systemctl restart docker
    echo "Docker daemon restarted to apply insecure registry settings."
fi


step "Cluster ${CLUSTER_NAME}"

if k3d cluster get "$CLUSTER_NAME" > /dev/null 2>&1; then
    k3d cluster start "$CLUSTER_NAME"
    echo "Cluster already exists."
else
    export STORAGE_DIR="$K8S_LOCAL_DIR/storage"
    mkdir -p "$STORAGE_DIR" "$K8S_LOCAL_DIR/.rendered"
    envsubst '${CLUSTER_NAME} ${CLUSTER_SERVERS} ${CLUSTER_AGENTS} ${STORAGE_DIR} ${REGISTRY_NAME} ${REGISTRY_CONTAINER} ${REGISTRY_PORT}' \
        < "$K8S_LOCAL_DIR/cluster.yaml" > "$K8S_LOCAL_DIR/.rendered/cluster.yaml"
    unset STORAGE_DIR
    k3d cluster create --config "$K8S_LOCAL_DIR/.rendered/cluster.yaml"

    k3d kubeconfig get ${CLUSTER_NAME} > "$K8S_LOCAL_DIR/.rendered/k3s.yaml"
    mv "$K8S_LOCAL_DIR/.rendered/k3s.yaml" "/mnt/c/Users/${WINDOWS_USER}/.kube/config/k3s-${CLUSTER_NAME}.yaml"
fi
kubectl config use-context "$KUBE_CONTEXT"

step "CRDs"
mkdir -p "$K8S_LOCAL_DIR/plugins"

step "Gateway API ${GATEWAY_API_VERSION} (standard channel)"
wget https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml -O "${K8S_LOCAL_DIR}/plugins/gateway-api-standard-install.yaml"

kubectl apply -f "${K8S_LOCAL_DIR}/plugins"

step "Traefik (chart ${TRAEFIK_CHART_VERSION})"
helm repo add traefik https://traefik.github.io/charts > /dev/null 2>&1 || true
helm repo update traefik > /dev/null
helm upgrade --install traefik traefik/traefik \
    --kube-context "$KUBE_CONTEXT" \
    --namespace traefik --create-namespace \
    --version "$TRAEFIK_CHART_VERSION" \
    --values "$K8S_LOCAL_DIR/traefik/values.yaml" \
    --wait

step "TLS certificate"
TRAEFIK_DIR="$K8S_LOCAL_DIR/traefik"
CERTS_DIR="$TRAEFIK_DIR/certs"
SECRET_NAME="${DOMAIN//./-}-cert"

if [ ! -f "$CERTS_DIR/local-cert.pem" ]; then
    mkdir -p "$CERTS_DIR"
    mkcert -cert-file "$CERTS_DIR/local-cert.pem" -key-file "$CERTS_DIR/local-key.pem" $(cat "$TRAEFIK_DIR/domains.txt")
else
    echo "Certificate already exists at $CERTS_DIR."
fi

kubectl create namespace gateway \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls "$SECRET_NAME" \
    --cert="$CERTS_DIR/local-cert.pem" \
    --key="$CERTS_DIR/local-key.pem" \
    --namespace gateway --dry-run=client -o yaml | kubectl apply -f -

step "Gateway"

kubectl apply -k "$K8S_LOCAL_DIR/gateway"
kubectl -n gateway wait gateway/oriworks --for=condition=Programmed --timeout=120s

cat <<INFO

Cluster ${CLUSTER_NAME} ready.

  Traefik dashboard  https://traefik.${DOMAIN}/dashboard/
  Registry           ${REGISTRY_NAME}:${REGISTRY_PORT}
                       docker push ${REGISTRY_NAME}:${REGISTRY_PORT}/<image>
                       helm push <chart>.tgz oci://${REGISTRY_NAME}:${REGISTRY_PORT}/charts --plain-http

INFO