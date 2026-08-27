#!/usr/bin/env bash
# tmux.sh — mechanical access to the tmux server.
#
# This is the only production file that invokes tmux. It contains no lifecycle,
# provider, or Airline policy; callers supply explicit option names and targets.

agent_tmux_global_get() { tmux show -gqv "$1"; }
agent_tmux_global_set() { tmux set -g "$1" "$2"; }

agent_tmux_pane_get() { tmux show -pqv -t "$1" "$2"; }
agent_tmux_pane_set() { tmux set -p -t "$1" "$2" "$3"; }
agent_tmux_pane_unset() { tmux set -pu -t "$1" "$2"; }

agent_tmux_current_session() {
  tmux display-message -p -t "$1" '#{session_id}'
}

agent_tmux_refresh_status() { tmux refresh-client -S; }

# vim: ft=bash
