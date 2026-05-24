# Hermes Stuff

Utilities, overrides, and agent persona files for running a customized
[Hermes Agent](https://github.com/NousResearch/hermes-agent) gateway.

This repository is intended to make a Hermes Slack deployment reproducible:
it builds a local container image, starts a persistent gateway with Podman,
applies Slack-specific gateway settings, and copies local Python overrides into
the running container.

## Contents

| Path | Purpose |
| --- | --- |
| `Dockerfile` | Builds a slim Python image and installs Hermes Agent. |
| `start-hermes-agent.sh` | Interactive Podman launcher and Slack configuration helper. |
| `slack.py` | Override for Hermes' Slack platform adapter. |
| `send_message_tool.py` | Override for Hermes' cross-platform `send_message` tool. |
| `soba/SOUL.md` | Sr. Soba ticket-management persona. |
| `ngueve/SOUL.md` | Ngueve commercial/CRM persona. |
| `jamba/SOUL.md` | Jamba logistics persona. |
| `severino/SOUL.md` | Severino general supervisor persona. |

## Requirements

- Linux host with `podman` available.
- Network access for the image build, because the Dockerfile downloads the
  Hermes Agent installer from GitHub.
- Hermes/Slack credentials configured during `hermes setup`, including the
  Slack bot token and Socket Mode app token expected by Hermes.

## Quick Start

Run the launcher from the repository root:

```bash
./start-hermes-agent.sh
```

The script asks for:

- Agent name, used to name the container as `hermes-agent-<agent-name>`.
- Host root mount, mounted into the container as `/root/.hermes`.

If the image named by `HERMES_IMAGE_NAME` does not exist, the script builds it
from `Dockerfile`. It then creates or starts the gateway container and applies
the Slack configuration described below.

After the first start, run Hermes setup inside the container:

```bash
podman exec -it hermes-agent-<agent-name> hermes setup
```

Restart the container after changing setup, API keys, or integrations:

```bash
podman restart hermes-agent-<agent-name>
```

View gateway logs with:

```bash
podman logs -f hermes-agent-<agent-name>
```

## Configuration Helper

To apply the Slack gateway configuration and Python overrides to an existing
container without going through the interactive launcher, run:

```bash
./start-hermes-agent.sh --configure-slack <agent-name>
```

This command expects `hermes-agent-<agent-name>` to already exist. It starts the
container if needed, waits for the Hermes CLI to respond, copies overrides when
the files exist, applies the Slack config, and restarts the container.

The helper currently applies these settings:

```bash
hermes config set platforms.slack.gateway_restart_notification false
hermes config set display.platforms.slack.tool_progress off
hermes config set slack.gateway_restart_notification false
```

It also copies these override files into the Hermes installation inside the
container:

```text
send_message_tool.py -> /usr/local/lib/hermes-agent/tools/send_message_tool.py
slack.py             -> /usr/local/lib/hermes-agent/gateway/platforms/slack.py
```

## Environment Variables

The launcher supports these optional environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `HERMES_IMAGE_NAME` | `hermes-agent` | Podman image name to build or run. |
| `HERMES_AGENT_NAME` | `default` | Default agent/container suffix. |
| `HERMES_ROOT_MOUNT` | `$HOME/.hermes-docker` | Host directory mounted as `/root/.hermes`. |

Example:

```bash
HERMES_AGENT_NAME=vetify HERMES_ROOT_MOUNT=$HOME/.hermes-vetify ./start-hermes-agent.sh
```

## Agent Personas

The `*/SOUL.md` files define Hermes personas used by the deployment:

- `soba`: ticket steward responsible for registering, following up,
  postponing, closing, and reporting on tickets.
- `ngueve`: commercial relations and CRM specialist for customer profiles,
  current-account balances, invoices, stock, and incoming merchandise.
- `jamba`: logistics specialist for stock, inbound/outbound goods, routes,
  suppliers, batches, expiry dates, and product rotation.
- `severino`: general supervisor covering commercial, logistics, finance,
  document-management, and read-only ticket-status questions.

These files are prompts/configuration assets. They do not contain operational
data; the agents are expected to consult the tools and systems available to
Hermes at runtime.

## Notes

- This repository does not store credentials. Configure secrets through Hermes
  setup, environment variables, or the mounted Hermes home directory.
- The override files are copied into the container at runtime. Re-run the
  configuration helper after changing them.
- The mounted Hermes home directory is persistent container state and should
  not be committed to this repository.
