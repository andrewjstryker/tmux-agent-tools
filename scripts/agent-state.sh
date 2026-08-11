#!/usr/bin/env bash
# agent-state.sh — reflect an agent's lifecycle state in the tmux window list,
# using tmux-airline's status-lane channel (the `airline status` CLI).
#
# Lifecycle is an *event* signal (a discrete state worth a glance), so it uses a
# status lane — airline's right-of-name badge stack — distinct from the health
# gutter, which agent-context.sh drives with a meter-style signal (context-window
# pressure). The two channels coexist on a window.
#
# Translates an agent state into one of airline's palette tokens and lights the
# 'agent' status lane on the window of the calling pane ($TMUX_PANE), so the
# window list shows a small colored badge (a ● after the name) marking which
# agent is working / waiting / finished. The agent speaks its own vocabulary;
# this script owns the state -> token mapping. It is agent-agnostic — any agent's
# hooks can call it; Claude Code is the worked example in the README.
#
#   needs-input -> alert    (orange — wants your attention)
#   working     -> monitor  (cyan   — a running system to watch)
#   done        -> ok       (green  — finished well; marked transient, so
#                            airline clears it once you view the window and
#                            leave — the one event this script can't observe)
#   error       -> stress   (red    — finished badly)
#   idle | clear-> (clear)  (back to normal)
#
# Usage: agent-state.sh <state>
#
# Layer 1: standalone. The pure mapping (as_map) is split from the CLI writes
# (as_apply) so the bats suite can drive it without a tmux server.

# The status lane this plugin owns (registered once in agent-state.tmux, in
# airline's global lane registry) and the health key agent-context.sh drives —
# cleared here too, so a session reset wipes both channels.
AS_LANE="agent"
AS_CTX_KEY="ctx"

as_die() { printf 'agent-state: %s\n' "$*" >&2; return 1; }

# Resolve the airline CLI (the supported API) via @airline-cli — the absolute
# path airline publishes at load. That option is the contract for "airline is
# active": set means loaded, unset means it isn't (so there's nothing to drive,
# and we no-op). $AIRLINE_BIN overrides it for tests / non-TPM installs. Prints
# the path, or empty when airline isn't active.
as_airline() {
  if [ -n "${AIRLINE_BIN:-}" ]; then printf '%s' "$AIRLINE_BIN"; return 0; fi
  tmux show -gqv @airline-cli 2>/dev/null
}

# Map a state to "<token> [transient]". Empty token = clear the lane.
# A trailing "1" means the signal is transient (airline clears it on unfocus).
# Returns non-zero on an unknown state.
as_map() {
  case "$1" in
    needs-input) echo "alert" ;;
    working)     echo "monitor" ;;
    done)        echo "ok 1" ;;     # transient: airline clears on unfocus
    error)       echo "stress" ;;
    idle|clear)  echo "" ;;
    *)           return 1 ;;
  esac
}

# Apply a state to the calling pane's window via the airline CLI. No-op outside
# tmux so hooks never fail when run in a non-tmux context.
as_apply() {
  local state="$1" mapped token transient airline
  mapped=$(as_map "$state") || { as_die "unknown state: $state"; return 1; }
  read -r token transient <<<"$mapped"

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(as_airline); [ -n "$airline" ] || { as_die "airline CLI not found (is tmux-airline installed?)"; return 1; }

  if [ -n "$token" ]; then
    # airline drops any stale --transient flag itself when set without it, so a
    # previous 'done' never lingers as transient under a later sticky state.
    if [ -n "$transient" ]; then
      "$airline" status set "$AS_LANE" "$token" --transient -t "$TMUX_PANE"
    else
      "$airline" status set "$AS_LANE" "$token" -t "$TMUX_PANE"
    fi
  else
    # clear/idle resets the window: clear the lifecycle lane AND the context
    # health key (agent-context.sh, the other channel this plugin drives), so a
    # SessionStart/SessionEnd wipe leaves no stale signal in either channel.
    "$airline" status clear "$AS_LANE"    -t "$TMUX_PANE"
    "$airline" health clear "$AS_CTX_KEY" -t "$TMUX_PANE"
  fi
  tmux refresh-client -S 2>/dev/null || true
}

as_main() {
  set -euo pipefail
  [ $# -eq 1 ] || as_die "usage: agent-state.sh <needs-input|working|done|error|idle|clear>"
  as_apply "$1"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  as_main "$@"
fi
