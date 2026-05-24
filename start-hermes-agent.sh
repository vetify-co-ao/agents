#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${HERMES_IMAGE_NAME:-hermes-agent}"
DEFAULT_AGENT_NAME="${HERMES_AGENT_NAME:-default}"
DEFAULT_ROOT_MOUNT="${HERMES_ROOT_MOUNT:-$HOME/.hermes-docker}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

set_container_name() {
    local agent_name="$1"
    CONTAINER_NAME="hermes-agent-$agent_name"
}

wait_for_hermes() {
    local attempts=30

    echo "Waiting for Hermes CLI to be ready in '$CONTAINER_NAME'..."
    for _ in $(seq 1 "$attempts"); do
        if podman exec "$CONTAINER_NAME" hermes --help >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    echo "Hermes CLI did not become ready in '$CONTAINER_NAME' after ${attempts}s." >&2
    return 1
}

ensure_container_running() {
    if ! podman container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        echo "Container '$CONTAINER_NAME' does not exist." >&2
        return 1
    fi

    if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]; then
        echo "Starting existing container '$CONTAINER_NAME'..."
        podman start "$CONTAINER_NAME" >/dev/null
    fi
}

copy_python_overrides() {
    if [ -f "$SCRIPT_DIR/send_message_tool.py" ]; then
        echo "Copying send_message_tool.py override..."
        podman cp "$SCRIPT_DIR/send_message_tool.py" \
            "$CONTAINER_NAME:/usr/local/lib/hermes-agent/tools/send_message_tool.py"
    else
        echo "send_message_tool.py not found in $SCRIPT_DIR; skipping override."
    fi

    if [ -f "$SCRIPT_DIR/slack.py" ]; then
        echo "Copying slack.py override..."
        podman cp "$SCRIPT_DIR/slack.py" \
            "$CONTAINER_NAME:/usr/local/lib/hermes-agent/gateway/platforms/slack.py"
    else
        echo "slack.py not found in $SCRIPT_DIR; skipping override."
    fi
}

configure_gateway() {
    wait_for_hermes

    copy_python_overrides

    echo "Applying Hermes Slack configuration..."
    podman exec "$CONTAINER_NAME" hermes config set platforms.slack.gateway_restart_notification false
    podman exec "$CONTAINER_NAME" hermes config set display.platforms.slack.tool_progress off
    podman exec "$CONTAINER_NAME" hermes config set slack.gateway_restart_notification false

    echo "Restarting container '$CONTAINER_NAME'..."
    podman restart "$CONTAINER_NAME" >/dev/null
}

if [ "${1:-}" = "--configure-slack" ]; then
    AGENT_NAME="${2:-$DEFAULT_AGENT_NAME}"
    set_container_name "$AGENT_NAME"
    ensure_container_running
    configure_gateway

    cat <<EOF

Slack configuration was applied to '$CONTAINER_NAME'.
Python overrides were copied when present, and the container was restarted.

View logs with:
  podman logs -f $CONTAINER_NAME
EOF
    exit 0
fi

read -r -p "Agent name [$DEFAULT_AGENT_NAME]: " AGENT_NAME
AGENT_NAME="${AGENT_NAME:-$DEFAULT_AGENT_NAME}"
set_container_name "$AGENT_NAME"

read -r -p "Root mount point on host [$DEFAULT_ROOT_MOUNT]: " ROOT_MOUNT
ROOT_MOUNT="${ROOT_MOUNT:-$DEFAULT_ROOT_MOUNT}"

mkdir -p "$ROOT_MOUNT"

if ! podman image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Podman image '$IMAGE_NAME' not found. Building it now..."
    podman build -t "$IMAGE_NAME" "$SCRIPT_DIR"
fi

if podman container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
        echo "Container '$CONTAINER_NAME' is already running."
    else
        echo "Starting existing container '$CONTAINER_NAME'..."
        podman start "$CONTAINER_NAME"
    fi
else
    echo "Creating and starting gateway container '$CONTAINER_NAME'..."
    podman run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -v "$ROOT_MOUNT:/root/.hermes" \
        "$IMAGE_NAME" gateway
fi

configure_gateway

cat <<EOF

Hermes gateway is starting in detached mode.

The script applied these gateway settings automatically:
  hermes config set platforms.slack.gateway_restart_notification false
  hermes config set display.platforms.slack.tool_progress off
  hermes config set slack.gateway_restart_notification false

The script also copied local Python overrides when present:
  send_message_tool.py -> /usr/local/lib/hermes-agent/tools/send_message_tool.py
  slack.py -> /usr/local/lib/hermes-agent/gateway/platforms/slack.py

The container was restarted after applying those changes.

If setup has not been run yet, invoke it with:
  podman exec -it $CONTAINER_NAME hermes setup

After setup changes config, API keys, or integrations, restart the container:
  podman restart $CONTAINER_NAME

View logs with:
  podman logs -f $CONTAINER_NAME

Hermes root data is mounted at:
  $ROOT_MOUNT -> /root/.hermes
EOF
