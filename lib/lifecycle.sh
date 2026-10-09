#!/usr/bin/env bash
# Translate agent lifecycle states into Airline pane status.

agent_lifecycle_error() { printf 'agent lifecycle: %s\n' "$*" >&2; return 1; }

# Map a state to an Airline pane workflow phase. Empty level = clear the pane.
# Returns non-zero on an unknown state.
agent_lifecycle_level() {
  case "$1" in
    working)     echo "active" ;;
    needs-input) echo "attention" ;;
    done)        echo "result" ;;
    clear)       echo "" ;;
    *)           return 1 ;;
  esac
}

# Apply a state to the calling pane's window via the airline CLI. No-op outside
# tmux so hooks never fail when run in a non-tmux context.
agent_lifecycle_apply() {
  local state="$1" level airline
  level=$(agent_lifecycle_level "$state") || { agent_lifecycle_error "unknown state: $state"; return 1; }

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(agent_airline_resolve); [ -n "$airline" ] || return 0
  if [ -n "$level" ]; then
    "$airline" status set -t "$TMUX_PANE" "$level"
  else
    # Lifecycle is independent from provider-specific health integrations.
    "$airline" status clear -t "$TMUX_PANE"
  fi
  # No refresh here: airline owns the redraw and issues it only when the badge or
  # health value actually changed, so re-setting 'working' on every tool call is
  # a no-op. Issuing our own refresh would defeat that and put the churn back.
}
