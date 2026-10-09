#!/usr/bin/env bash
# Publish the CLI, then reset and initialize Agent for the current session.
AGENT_DIR="${AGENT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=agent.sh
source "$AGENT_DIR/agent.sh"
tmux set -g @agent-cli "$AGENT_DIR/agent.sh"
agent_main init
