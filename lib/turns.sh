#!/usr/bin/env bash
# Maintain the calling pane's conversation-turn count in tmux.

AGENT_TURNS_OPTION="@agent-tools-turns"

agent_turns_error() { printf 'agent turns: %s\n' "$*" >&2; return 1; }

# Next counter value given the current one. A non-numeric or empty current
# value (no counter yet) starts at 1.
agent_turns_next() {
  local current="$1"
  case "$current" in
    ''|*[!0-9]*) echo 1 ;;
    *)           echo $((current + 1)) ;;
  esac
}

# Apply a command to the calling pane's counter. No-op outside tmux so hooks
# never fail when run in a non-tmux context.
agent_turns_apply() {
  local cmd="$1" current next

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0

  agent_initialize || return

  case "$cmd" in
    bump)
      current=$(tmux show -pqv -t "$TMUX_PANE" "$AGENT_TURNS_OPTION")
      next=$(agent_turns_next "$current")
      tmux set -p -t "$TMUX_PANE" "$AGENT_TURNS_OPTION" "$next"
      ;;
    clear)
      tmux set -pu -t "$TMUX_PANE" "$AGENT_TURNS_OPTION"
      ;;
    *)
      agent_turns_error "unknown command: $cmd"; return 1
      ;;
  esac
  tmux refresh-client -S 2>/dev/null || true
}
