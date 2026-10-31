#!/bin/bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$CURRENT_DIR/utils/common.sh"

require docker k3d kubectl helm envsubst

REGISTRY="${REGISTRY_NAME}:${REGISTRY_PORT}"
step "Registry ${REGISTRY}"

if docker container inspect "$REGISTRY_CONTAINER" > /dev/null 2>&1; then
    docker start "$REGISTRY_CONTAINER" > /dev/null
    echo "Started registry container $REGISTRY_CONTAINER."
else
    k3d registry create "$REGISTRY_NAME" --port "127.0.0.1:${REGISTRY_PORT}"
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

    # Só em WSL: copia o kubeconfig para o utilizador Windows
    if [ -n "${WINDOWS_USER:-}" ] && [ -d "/mnt/c/Users/${WINDOWS_USER}/.kube/config" ]; then
        k3d kubeconfig get ${CLUSTER_NAME} > "/mnt/c/Users/${WINDOWS_USER}/.kube/config/k3s-${CLUSTER_NAME}.yaml"
    fi
fi
kubectl config use-context "$KUBE_CONTEXT"

step "CRDs"
mkdir -p "$K8S_LOCAL_DIR/plugins"

# Experimental: o Traefik observa TCPRoute v1alpha2, que o canal standard não serve
step "Gateway API ${GATEWAY_API_VERSION} (experimental channel)"
wget https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml -O "${K8S_LOCAL_DIR}/plugins/gateway-api-experimental-install.yaml"

kubectl apply --server-side -f "${K8S_LOCAL_DIR}/plugins"

step "Traefik (chart ${TRAEFIK_CHART_VERSION})"
helm repo add traefik https://traefik.github.io/charts > /dev/null 2>&1 || true
helm repo update traefik > /dev/null
helm upgrade --install traefik traefik/traefik \
    --kube-context "$KUBE_CONTEXT" \
    --namespace traefik --create-namespace \
    --version "$TRAEFIK_CHART_VERSION" \
    --values "$K8S_LOCAL_DIR/traefik/values.yaml" \
    --wait

step "cert-manager (chart ${CERT_MANAGER_CHART_VERSION})"
helm repo add jetstack https://charts.jetstack.io > /dev/null 2>&1 || true
helm repo update jetstack > /dev/null
# Resolvers públicos: a verificação de propagação do DNS-01 não depende do DNS local
helm upgrade --install cert-manager jetstack/cert-manager \
    --kube-context "$KUBE_CONTEXT" \
    --namespace cert-manager --create-namespace \
    --version "$CERT_MANAGER_CHART_VERSION" \
    --set crds.enabled=true \
    --set 'extraArgs={--dns01-recursive-nameservers-only,--dns01-recursive-nameservers=1.1.1.1:53}' \
    --wait

step "TLS certificate *.${DOMAIN} (${ACME_ISSUER})"
CERT_MANAGER_DIR="$K8S_LOCAL_DIR/cert-manager"
CLOUDFLARE_TOKEN="$CERT_MANAGER_DIR/.cloudflare-token"
export TLS_SECRET="${DOMAIN//./-}-cert"

if [ ! -s "$CLOUDFLARE_TOKEN" ]; then
    echo "Error: missing Cloudflare API token at $CLOUDFLARE_TOKEN (Zone:Read + DNS:Edit on the ${DOMAIN#*.} zone)" >&2
    exit 1
fi

kubectl create secret generic cloudflare-api-token \
    --from-literal=api-token="$(tr -d '[:space:]' < "$CLOUDFLARE_TOKEN")" \
    --namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gateway \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl kustomize "$CERT_MANAGER_DIR" | envsubst '${DOMAIN} ${ACME_EMAIL} ${ACME_ISSUER} ${TLS_SECRET}' | kubectl apply -f -
kubectl -n gateway wait "certificate/${TLS_SECRET}" --for=condition=Ready --timeout=300s

step "Gateway"
DASHBOARD_CREDENTIALS="$K8S_LOCAL_DIR/traefik/.dashboard-credentials"

if [ ! -f "$DASHBOARD_CREDENTIALS" ]; then
    cat > "$DASHBOARD_CREDENTIALS" <<CREDENTIALS
DASHBOARD_USER=admin
DASHBOARD_PASSWORD=$(openssl rand -hex 16)
CREDENTIALS
    chmod 600 "$DASHBOARD_CREDENTIALS"
    echo "Generated credentials at $DASHBOARD_CREDENTIALS."
else
    echo "Credentials already exist at $DASHBOARD_CREDENTIALS."
fi
. "$DASHBOARD_CREDENTIALS"

kubectl create secret generic traefik-dashboard-auth \
    --type=kubernetes.io/basic-auth \
    --from-literal=username="$DASHBOARD_USER" \
    --from-literal=password="$DASHBOARD_PASSWORD" \
    --namespace traefik --dry-run=client -o yaml | kubectl apply -f -

kubectl kustomize "$K8S_LOCAL_DIR/gateway" | envsubst '${DOMAIN} ${TLS_SECRET}' | kubectl apply -f -
kubectl -n gateway wait gateway/oriworks --for=condition=Programmed --timeout=120s

step "Dolt ${DOLT_VERSION}"
DOLT_DIR="$K8S_LOCAL_DIR/dolt"
DOLT_CREDENTIALS="$DOLT_DIR/.credentials"

if [ ! -f "$DOLT_CREDENTIALS" ]; then
    cat > "$DOLT_CREDENTIALS" <<CREDENTIALS
DOLT_USER=beads
DOLT_PASSWORD=$(openssl rand -hex 24)
DOLT_ROOT_PASSWORD=$(openssl rand -hex 24)
CREDENTIALS
    chmod 600 "$DOLT_CREDENTIALS"
    echo "Generated credentials at $DOLT_CREDENTIALS."
else
    echo "Credentials already exist at $DOLT_CREDENTIALS."
fi
. "$DOLT_CREDENTIALS"

kubectl create namespace dolt \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic dolt-credentials \
    --from-env-file="$DOLT_CREDENTIALS" \
    --namespace dolt --dry-run=client -o yaml | kubectl apply -f -

kubectl kustomize "$DOLT_DIR" | envsubst '${DOLT_VERSION}' | kubectl apply -f -
kubectl -n dolt rollout status statefulset/dolt --timeout=120s

cat <<INFO

Cluster ${CLUSTER_NAME} ready.

  Traefik dashboard  https://traefik.${DOMAIN}/dashboard/
                       user ${DASHBOARD_USER} (senha em ${DASHBOARD_CREDENTIALS})
  Certificado        *.${DOMAIN} (${ACME_ISSUER})
  Registry           ${REGISTRY_NAME}:${REGISTRY_PORT}
                       docker push ${REGISTRY_NAME}:${REGISTRY_PORT}/<image>
                       helm push <chart>.tgz oci://${REGISTRY_NAME}:${REGISTRY_PORT}/charts --plain-http
  Dolt (beads)       127.0.0.1:3306  user ${DOLT_USER} (senha em ${DOLT_CREDENTIALS})
                       export BEADS_DOLT_PASSWORD=\$(grep ^DOLT_PASSWORD= ${DOLT_CREDENTIALS} | cut -d= -f2)
                       bd init --server --external --server-host 127.0.0.1 --server-port 3306 --server-user ${DOLT_USER} -p <prefix>

INFO