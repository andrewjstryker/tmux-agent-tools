#!/usr/bin/env bash
# agent-state.sh — reflect an agent's lifecycle state in the tmux window list,
# using tmux-airline's status-lane channel (the `airline status` CLI).
#
# Lifecycle is an *event* signal (a discrete state worth a glance), so it uses a
# status lane — airline's right-of-name badge stack — distinct from the health
# gutter, which agent-context.sh drives with a meter-style signal (context-window
# pressure). The two channels coexist on a window.
#
# Translates an agent state into one of airline's status *levels* and lights the
# 'agent' status lane on the window of the calling pane ($TMUX_PANE), so the
# window list shows a small badge (a glyph after the name) marking which agent is
# working / waiting / finished. The agent speaks its own vocabulary; this script
# owns the state -> level mapping. It is agent-agnostic — any agent's hooks can
# call it; Claude Code is the worked example in the README.
#
# airline's status channel has three fixed levels, each with its own glyph and
# color (the plugin no longer picks palette tokens — airline owns that mapping):
#
#   working     -> active     (○ amber — a running system to watch)
#   done        -> result     (● green — finished well; marked transient, so
#                              airline clears it once you view the window and
#                              leave — the one event this script can't observe)
#   needs-input -> attention  (◆ amber — wants your input)
#   idle | clear-> (clear)    (back to normal)
#
# Usage: agent-state.sh <state>
#
# Layer 1: standalone. The pure mapping (as_map) is split from the CLI writes
# (as_apply) so the bats suite can drive it without a tmux server.

# The status key this plugin lights (created implicitly on first `status set`;
# airline no longer registers keys) and the health keys agent-context.sh drives
# — cleared here too, so a session reset wipes both channels at once.
AS_LANE="agent"
AS_CTX_KEY="ctx"
AS_USAGE_KEY="usage"

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

# Warn — at most once per tmux server — that the airline CLI couldn't be resolved
# (no @airline-cli, no $AIRLINE_BIN), then no-op. The status/health signals need
# airline; without it there's nothing to drive. We *warn* (not fail) so a per-turn
# hook isn't flagged on every call, and *not silently* so a real misconfiguration
# is visible — but only once, via a global tmux flag (no state files), since this
# runs per hook. Reached only from inside tmux (callers guard on $TMUX first), so
# a user who never wired the airline-backed signals sees no message at all.
AS_WARN_FLAG="@agent-tools-airline-warned"
as_warn_no_airline() {
  [ "$(tmux show -gqv "$AS_WARN_FLAG" 2>/dev/null)" = 1 ] && return 0
  tmux set -g "$AS_WARN_FLAG" 1 2>/dev/null
  printf 'agent-state: airline CLI not found — set @airline-cli (load tmux-airline first) or the AIRLINE_BIN env var; status/health signals disabled\n' >&2
}

# Map a state to "<level> [transient]". Empty level = clear the lane.
# A trailing "1" means the signal is transient (airline clears it on unfocus).
# Returns non-zero on an unknown state.
as_map() {
  case "$1" in
    working)     echo "active" ;;
    needs-input) echo "attention" ;;
    done)        echo "result 1" ;;   # transient: airline clears on unfocus
    idle|clear)  echo "" ;;
    *)           return 1 ;;
  esac
}

# Apply a state to the calling pane's window via the airline CLI. No-op outside
# tmux so hooks never fail when run in a non-tmux context.
as_apply() {
  local state="$1" mapped level transient airline
  mapped=$(as_map "$state") || { as_die "unknown state: $state"; return 1; }
  read -r level transient <<<"$mapped"

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(as_airline); [ -n "$airline" ] || { as_warn_no_airline; return 0; }

  if [ -n "$level" ]; then
    # airline drops any stale --transient flag itself when set without it, so a
    # previous 'done' never lingers as transient under a later sticky state.
    if [ -n "$transient" ]; then
      "$airline" status set "$AS_LANE" "$level" --transient -t "$TMUX_PANE"
    else
      "$airline" status set "$AS_LANE" "$level" -t "$TMUX_PANE"
    fi
  else
    # clear/idle resets the window: clear the lifecycle lane AND every health key
    # agent-context.sh drives (context + usage), so a SessionStart/SessionEnd
    # wipe leaves no stale signal in either channel.
    "$airline" status clear "$AS_LANE"      -t "$TMUX_PANE"
    "$airline" health clear "$AS_CTX_KEY"   -t "$TMUX_PANE"
    "$airline" health clear "$AS_USAGE_KEY" -t "$TMUX_PANE"
  fi
  # No refresh here: airline owns the redraw and issues it only when the badge or
  # health value actually changed, so re-setting 'working' on every tool call is
  # a no-op. Issuing our own refresh would defeat that and put the churn back.
}

as_main() {
  set -euo pipefail
  [ $# -eq 1 ] || as_die "usage: agent-state.sh <working|needs-input|done|idle|clear>"
  as_apply "$1"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  as_main "$@"
fi
