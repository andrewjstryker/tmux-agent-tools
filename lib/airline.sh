#!/usr/bin/env bash
# airline.sh — mechanical access to tmux-airline's public CLI.
#
# Discovery and command construction live here so operations and adapters name
# Agent concepts rather than reproducing the external CLI grammar. Compatibility
# policy is added in a later implementation chunk.

agent_airline_resolve() {
  if [[ -n "${AIRLINE_BIN:-}" ]]; then
    printf '%s' "$AIRLINE_BIN"
    return 0
  fi
  agent_tmux_global_get @airline-cli 2>/dev/null
}

agent_airline_warn_once() { # <category> <prefix> <message>
  local category="$1" prefix="$2" message="$3"
  local flag="@agent-tools-$category-warned"
  [[ "$(agent_tmux_global_get "$flag" 2>/dev/null)" == 1 ]] && return 0
  agent_tmux_global_set "$flag" 1 2>/dev/null
  printf '%s: %s\n' "$prefix" "$message" >&2
}

agent_airline_warn_missing() { # <diagnostic-prefix>
  agent_airline_warn_once airline "$1" \
    'airline CLI not found — set @airline-cli (load tmux-airline first) or the AIRLINE_BIN env var; status/health signals disabled'
}

agent_airline_status_set() { # <cli> <key> <level> <transient-or-empty> <pane>
  local cli="$1" key="$2" level="$3" transient="$4" pane="$5"
  if [[ -n "$transient" ]]; then
    "$cli" status set "$key" "$level" --transient -t "$pane"
  else
    "$cli" status set "$key" "$level" -t "$pane"
  fi
}

agent_airline_status_clear() { # <cli> <key> <pane>
  "$1" status clear "$2" -t "$3"
}

agent_airline_health_set() { # <cli> <key> <level> <pane>
  "$1" health set "$2" "$3" -t "$4"
}

agent_airline_health_clear() { # <cli> <key> <pane>
  "$1" health clear "$2" -t "$3"
}

# These two functions preserve the current pane-originated 2.x command shape.
# The explicit session-scoped 3.x contract replaces them in implementation
# chunk 5.
agent_airline_problem_set_from_pane() { # <cli> <key> <level> <message> <pane>
  "$1" problem set "$2" "$3" "$4" -t "$5"
}

agent_airline_problem_clear_from_pane() { # <cli> <key> <pane>
  "$1" problem clear "$2" -t "$3"
}

# vim: ft=bash
