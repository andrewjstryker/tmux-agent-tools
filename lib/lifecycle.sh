#!/usr/bin/env bash
# lifecycle.sh — apply a provider-neutral agent lifecycle operation.
# using tmux-airline's left status-lane channel (the `airline status` CLI).
#
# Lifecycle is pane workflow state, so it uses airline's left status lane,
# distinct from the health gutter that provider integrations may drive with
# meter-style signals. The two channels coexist on a window.
#
# Translates an agent state into one of airline's status *levels* and lights the
# calling pane's one status entry ($TMUX_PANE), so the window list shows a small
# badge marking which agent is working / waiting / finished. The agent speaks its
# own vocabulary; this script owns the state -> level mapping. It is agent-agnostic;
# Claude and Codex adapters both call it.
#
# airline's status channel has three fixed levels, each with its own glyph and
# color (the plugin no longer picks palette tokens — airline owns that mapping):
#
#   working     -> active     (○ amber — a running system to watch)
#   done        -> result     (● green — finished well; Airline advances the
#                              lifecycle after the pane is viewed)
#   needs-input -> attention  (◆ amber — wants your input)
#   idle | clear-> (clear)    (back to normal)
#
# Usage: lifecycle.sh <state>
#
# The pure mapping (as_map) is split from the CLI writes (as_apply) so the bats
# suite can drive it without a tmux server. This file is private implementation;
# agent.sh is the public command boundary.

AGENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/tmux.sh
source "$AGENT_ROOT/lib/tmux.sh"
# shellcheck source=lib/airline.sh
source "$AGENT_ROOT/lib/airline.sh"

as_die() { printf 'agent-state: %s\n' "$*" >&2; return 1; }

# Map a state to an Airline pane workflow phase. Empty level = clear the pane.
# Returns non-zero on an unknown state.
as_map() {
  case "$1" in
    working)     echo "active" ;;
    needs-input) echo "attention" ;;
    done)        echo "result" ;;
    idle|clear)  echo "" ;;
    *)           return 1 ;;
  esac
}

# Apply a state to the calling pane's window via the airline CLI. No-op outside
# tmux so hooks never fail when run in a non-tmux context.
as_apply() {
  local state="$1" mapped level airline
  mapped=$(as_map "$state") || { as_die "unknown state: $state"; return 1; }
  level="$mapped"

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(agent_airline_resolve agent-state); [ -n "$airline" ] || return 0
  if [ -n "$level" ]; then
    agent_airline_status_set "$airline" "$level" "$TMUX_PANE"
  else
    # Lifecycle is independent from provider-specific health integrations.
    agent_airline_status_clear "$airline" "$TMUX_PANE"
  fi
  # No refresh here: airline owns the redraw and issues it only when the badge or
  # health value actually changed, so re-setting 'working' on every tool call is
  # a no-op. Issuing our own refresh would defeat that and put the churn back.
}

as_main() {
  set -euo pipefail
  [ $# -eq 1 ] || as_die "usage: lifecycle.sh <working|needs-input|done|idle|clear>"
  as_apply "$1"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  as_main "$@"
fi
