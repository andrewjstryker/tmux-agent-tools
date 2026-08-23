#!/usr/bin/env bash
# agent-turns.sh — maintain a per-pane conversation turn counter in the pane
# option @agent-tools-turns.
#
# Claude Code (and agents generally) expose no turn/message count to hooks, so
# this keeps its own: an agent's per-turn hook calls `agent-turns.sh bump`,
# which increments @agent-tools-turns on the calling pane. The count is pane-scoped so
# it tracks the agent in the focused pane and is blank everywhere else.
#
# This plugin only owns the *value*. Rendering is a plain tmux format that
# references the option — no special airline API. With tmux-airline, a segment is
# just a public @airline-segment-<slot> option you set with `set -g` (see the
# README):
#
#   set -g @airline-segment-right-in '#{?@agent-tools-turns, #{@agent-tools-turns}⟳,}'
#
# It is agent-agnostic; Claude Code is the worked example in the README.
#
#   bump        -> increment the active pane's counter (unset -> 1)
#   reset|clear -> remove the counter (blank in the status line)
#
# Usage: agent-turns.sh <bump|reset|clear>
#
# The pure logic (at_next) is split from the tmux writes (at_apply) so the bats
# suite can drive it without a tmux server.

AT_OPT="@agent-tools-turns"

at_die() { printf 'agent-turns: %s\n' "$*" >&2; return 1; }

# Next counter value given the current one. A non-numeric or empty current
# value (no counter yet) starts at 1.
at_next() {
  local current="$1"
  case "$current" in
    ''|*[!0-9]*) echo 1 ;;
    *)           echo $((current + 1)) ;;
  esac
}

# Apply a command to the calling pane's counter. No-op outside tmux so hooks
# never fail when run in a non-tmux context.
at_apply() {
  local cmd="$1" current next

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0

  case "$cmd" in
    bump)
      current=$(tmux show -pqv -t "$TMUX_PANE" "$AT_OPT")
      next=$(at_next "$current")
      tmux set -p -t "$TMUX_PANE" "$AT_OPT" "$next"
      ;;
    reset|clear)
      tmux set -pu -t "$TMUX_PANE" "$AT_OPT"
      ;;
    *)
      at_die "unknown command: $cmd"; return 1
      ;;
  esac
  tmux refresh-client -S 2>/dev/null || true
}

at_main() {
  set -euo pipefail
  [ $# -eq 1 ] || at_die "usage: agent-turns.sh <bump|reset|clear>"
  at_apply "$1"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  at_main "$@"
fi
