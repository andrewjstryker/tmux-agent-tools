#!/usr/bin/env bash
# Suppress repeated diagnostics using Agent-owned tmux options.

agent_warn_once() { # <category> <prefix> <message>
  local category="$1" prefix="$2" message="$3"
  local flag="@agent-tools-$category-warned"
  [[ "$(tmux show -gqv "$flag" 2>/dev/null)" == 1 ]] && return 0
  tmux set -g "$flag" 1 2>/dev/null
  printf '%s: %s\n' "$prefix" "$message" >&2
}
