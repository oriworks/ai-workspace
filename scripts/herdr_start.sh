#!/bin/bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$CURRENT_DIR/utils/common.sh"

require herdr jq git

ROOT="$(git -C "$CURRENT_DIR" rev-parse --show-toplevel)"
SESSION="${HERDR_START_SESSION:-$(basename "$ROOT")}"

hd() {
    herdr --session "$SESSION" "$@"
}

step "Session ${SESSION}"

if herdr session list --json | jq -e --arg s "$SESSION" '.sessions[] | select(.name == $s and .running)' > /dev/null; then
    echo "Session already running."
else
    (cd "$ROOT" && nohup herdr --session "$SESSION" server > /dev/null 2>&1 & disown)
    for _ in $(seq 20); do
        hd workspace list > /dev/null 2>&1 && break
        sleep 0.5
    done
    hd workspace list > /dev/null 2>&1 || { echo "Error: session $SESSION did not start" >&2; exit 1; }
    echo "Started session $SESSION."
fi

ensure_workspace() {
    local label=$1
    local dir=$2

    local workspace_id
    workspace_id="$(hd workspace list | jq -r --arg l "$label" 'first(.result.workspaces[] | select(.label == $l) | .workspace_id) // empty')"
    if [ -n "$workspace_id" ]; then
        echo "Workspace $label already exists."
    else
        workspace_id="$(hd workspace create --cwd "$dir" --label "$label" --no-focus | jq -r '.result.workspace.workspace_id')"
        echo "Created workspace $label ($dir)."
    fi

    ensure_tabs "$workspace_id" "$dir" "$label"
}

# Primeira tab "shell", segunda "agent" com o claude a correr
ensure_tabs() {
    local workspace_id=$1
    local dir=$2
    local label=$3
    local tabs first_tab_id first_label agent_tab_id

    tabs="$(hd tab list --workspace "$workspace_id")"
    first_tab_id="$(jq -r '.result.tabs | min_by(.number) | .tab_id' <<< "$tabs")"
    first_label="$(jq -r '.result.tabs | min_by(.number) | .label' <<< "$tabs")"
    if [ "$first_label" != "shell" ]; then
        hd tab rename "$first_tab_id" shell > /dev/null
        echo "  Renamed tab $first_tab_id to shell."
    fi

    agent_tab_id="$(jq -r 'first(.result.tabs[] | select(.label == "agent") | .tab_id) // empty' <<< "$tabs")"
    if [ -n "$agent_tab_id" ]; then
        echo "  Tab agent already exists."
    else
        agent_tab_id="$(hd tab create --workspace "$workspace_id" --cwd "$dir" --label agent --no-focus | jq -r '.result.tab.tab_id')"
        echo "  Created tab agent."
    fi

    ensure_agent "$workspace_id" "$agent_tab_id" "$label"
}

ensure_agent() {
    local workspace_id=$1
    local tab_id=$2
    local label=$3
    local panes pane_id name

    panes="$(hd pane list --workspace "$workspace_id")"
    if jq -e --arg t "$tab_id" '.result.panes[] | select(.tab_id == $t and .agent != null)' <<< "$panes" > /dev/null; then
        echo "  Agent already running."
        return
    fi

    pane_id="$(jq -r --arg t "$tab_id" 'first(.result.panes[] | select(.tab_id == $t) | .pane_id)' <<< "$panes")"
    # Nomes de agent: [a-z][a-z0-9_-]{0,31}
    name="$(tr '[:upper:]' '[:lower:]' <<< "$label" | sed -e 's/[^a-z0-9_-]/-/g' -e 's/^[^a-z]*//' | cut -c1-32)"
    if hd agent start "${name:-agent}" --kind claude --pane "$pane_id" > /dev/null; then
        echo "  Started claude in $pane_id."
    else
        echo "  Warning: claude in $pane_id is not ready (check the agent tab)." >&2
    fi
}

step "Workspaces"

ensure_workspace "$SESSION" "$ROOT"
for dir in "$ROOT"/projects/*/; do
    [ -d "$dir" ] || continue
    ensure_workspace "$(basename "$dir")" "${dir%/}"
done

if [ "${HERDR_SESSION:-}" != "$SESSION" ]; then
    exec herdr session attach "$SESSION"
fi
