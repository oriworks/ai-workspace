UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_LOCAL_DIR="$(cd "$UTILS_DIR/../../k8s/local" && pwd)"

set -a
. "$K8S_LOCAL_DIR/config.env"
set +a

has() {
    local package=$1

    if [ "$(dpkg -l | awk "/$package/ {print}" | wc -l)" -ge 1 ] || [[ $(type -t $package) == function ]] || which "$package" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

require() {
    local missing=()
    for tool in "$@"; do
        has "$tool" || missing+=("$tool")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: missing tools: ${missing[*]} (see setup/install)" >&2
        exit 1
    fi
}

step() {
    echo
    echo "===> $* <==="
}