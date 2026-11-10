#!/bin/bash
# Claude Code status line (ccstatusline) config.
#
#   claude.sh         apply repo config to this machine
#   claude.sh save    copy this machine's current config back into the repo

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_STATUSLINE="$REPO_DIR/config/claude/statusline.json"
REPO_CCSTATUSLINE="$REPO_DIR/config/ccstatusline/settings.json"

CLAUDE_SETTINGS=~/.claude/settings.json
CCSTATUSLINE_SETTINGS=~/.config/ccstatusline/settings.json

if [ "${1:-}" = "save" ]; then
    jq '{statusLine}' "$CLAUDE_SETTINGS" > "$REPO_STATUSLINE"
    cp "$CCSTATUSLINE_SETTINGS" "$REPO_CCSTATUSLINE"
    echo "Saved status line config to $REPO_DIR/config"
    exit 0
fi

# Install ccstatusline at the version pinned in the config
VERSION="$(jq -r '.installation.installedVersion // "latest"' "$REPO_CCSTATUSLINE")"
if ! command -v ccstatusline > /dev/null 2>&1; then
    echo "Installing ccstatusline@$VERSION..."
    npm install -g "ccstatusline@$VERSION"
fi

# ccstatusline layout
mkdir -p "$(dirname "$CCSTATUSLINE_SETTINGS")"
cp "$REPO_CCSTATUSLINE" "$CCSTATUSLINE_SETTINGS"

# Merge statusLine into Claude settings, keeping all other keys
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[ -f "$CLAUDE_SETTINGS" ] || echo '{}' > "$CLAUDE_SETTINGS"
tmp="$(mktemp)"
jq -s '.[0] * .[1]' "$CLAUDE_SETTINGS" "$REPO_STATUSLINE" > "$tmp"
mv "$tmp" "$CLAUDE_SETTINGS"

echo "Status line config applied."
