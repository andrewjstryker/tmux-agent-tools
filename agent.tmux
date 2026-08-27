#!/usr/bin/env bash
# TPM / run-shell entry point. Publish the one stable executable handle; all
# command parsing and behavior lives in agent.sh.

CURRENT_DIR="${AGENT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# shellcheck source=lib/tmux.sh
source "$CURRENT_DIR/lib/tmux.sh"

agent_tmux_global_set @agent-cli "$CURRENT_DIR/agent.sh"
