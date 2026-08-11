#!/usr/bin/env bash
# agent-context.sh — reflect an agent's context-window pressure in the tmux
# window list, using tmux-airline's health channel (the `airline health` CLI).
#
# Context usage is exposed only to a Claude Code *statusLine* command (hooks
# don't get it), so this is wired as one. It reads the statusLine JSON on stdin,
# maps context_window.used_percentage to a severity, reports it on the calling
# pane's window, and passes the JSON through unchanged so it can be piped into
# your real status line:
#
#   "statusLine": { "type": "command",
#     "command": "$(tmux show -gqv @agent-context-bin) | your-status-line" }
#
# Context pressure is a *meter* (a sustained condition), so it uses the health
# gutter — distinct from the lifecycle *status lane* (badge) that agent-state.sh
# drives. The two coexist on a window. airline reduces all health contributors
# to the worst severity; this script contributes under the 'ctx' key. Thresholds
# are percent and overridable via tmux options:
#   @agent-context-alert  (default 80) -> alert  (amber gutter glyph)
#   @agent-context-stress (default 90) -> stress (red gutter glyph)
# Below the alert threshold the contribution is cleared.
#
# Layered like agent-state.sh: the pure mapping (ac_tier) is split from the CLI
# writes (ac_apply) so the bats suite can drive it without a tmux server.

# The health key this plugin contributes under (agent-state.sh clears the same
# key on a session reset). Kept in sync with agent-state.sh's AS_CTX_KEY.
AC_KEY="ctx"

ac_die() { printf 'agent-context: %s\n' "$*" >&2; return 1; }

# Resolve the airline CLI (the supported API) via @airline-cli — the absolute
# path airline publishes at load. That option is the contract for "airline is
# active": set means loaded, unset means it isn't (so there's nothing to drive,
# and we no-op). $AIRLINE_BIN overrides it for tests / non-TPM installs. Prints
# the path, or empty when airline isn't active.
ac_airline() {
  if [ -n "${AIRLINE_BIN:-}" ]; then printf '%s' "$AIRLINE_BIN"; return 0; fi
  tmux show -gqv @airline-cli 2>/dev/null
}

# Map a used-percentage to a palette token, given the two thresholds. Empty
# token = clear. Pure: thresholds are passed in, not read from tmux.
ac_tier() {
  local pct="$1" alert="$2" stress="$3"
  case "$pct" in ''|*[!0-9]*) echo ""; return 0 ;; esac   # non-numeric -> clear
  if   [ "$pct" -ge "$stress" ]; then echo "stress"
  elif [ "$pct" -ge "$alert"  ]; then echo "alert"
  else                                echo ""
  fi
}

# Extract context_window.used_percentage (integer part) from the statusLine
# JSON. Prefers jq; falls back to a grep parse so jq isn't a hard dependency.
ac_extract_pct() {
  local json="$1" pct=""
  if command -v jq >/dev/null 2>&1; then
    pct=$(printf '%s' "$json" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
  else
    pct=$(printf '%s' "$json" \
      | grep -o '"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]*' \
      | grep -o '[0-9.]*$' | head -n1)
  fi
  printf '%s' "${pct%%.*}"   # integer part only
}

# Read the statusLine JSON from stdin, report the context severity on the health
# channel by tier, and pass the JSON through unchanged (so it composes with a
# real status line). No CLI writes outside tmux, so it stays safe in any context.
# A missing airline is a silent no-op: the JSON is already out and the status
# line must never break, so we don't surface install errors on every render.
ac_apply() {
  local json token alert stress airline
  json=$(cat)
  printf '%s' "$json"        # passthrough first: the status line always renders

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(ac_airline); [ -n "$airline" ] || return 0

  alert=$(tmux show -gqv @agent-context-alert);   [ -n "$alert" ]  || alert=80
  stress=$(tmux show -gqv @agent-context-stress); [ -n "$stress" ] || stress=90
  token=$(ac_tier "$(ac_extract_pct "$json")" "$alert" "$stress")

  if [ -n "$token" ]; then
    "$airline" health set "$AC_KEY" "$token" -t "$TMUX_PANE"
  else
    "$airline" health clear "$AC_KEY" -t "$TMUX_PANE"
  fi
  tmux refresh-client -S 2>/dev/null || true
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -euo pipefail
  ac_apply
fi
