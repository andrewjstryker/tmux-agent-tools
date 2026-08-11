#!/usr/bin/env bash
# agent-context.sh — reflect an agent's resource pressure in the tmux window
# list, using tmux-airline's health channel (the `airline health` CLI).
#
# Two meters, both exposed only to a Claude Code *statusLine* command (hooks
# don't get them), so this is wired as one. It reads the statusLine JSON on
# stdin, maps each meter to a severity, reports them on the calling pane's
# window, and passes the JSON through unchanged so it can be piped into your real
# status line. JSON in, JSON out — so jq is required (see ac_have_jq):
#
#   "statusLine": { "type": "command",
#     "command": "$(tmux show -gqv @agent-context-bin) | your-status-line" }
#
# The two meters:
#   * context-window fill — context_window.used_percentage, under the 'ctx' key.
#   * usage-limit         — the worse of rate_limits.{five_hour,seven_day}
#                           .used_percentage (Claude.ai Pro/Max only; each window
#                           may be absent), under the 'usage' key.
#
# Both are *meters* (sustained conditions), so they use the health gutter —
# distinct from the lifecycle *status lane* (badge) that agent-state.sh drives.
# All three coexist on a window. airline reduces all health contributors to the
# worst severity, so a busy window shows one gutter glyph at the max. Thresholds
# are percent and overridable via tmux options (each meter has its own pair):
#   @agent-context-alert  (default 80) -> alert  (amber gutter glyph)
#   @agent-context-stress (default 90) -> stress (red gutter glyph)
#   @agent-usage-alert    (default 80) -> alert
#   @agent-usage-stress   (default 90) -> stress
# Below the alert threshold the contribution is cleared.
#
# Layered like agent-state.sh: the pure mapping (ac_tier) is split from the CLI
# writes (ac_apply) so the bats suite can drive it without a tmux server.

# The health keys this plugin contributes under (agent-state.sh clears the same
# keys on a session reset). Kept in sync with agent-state.sh's AS_CTX_KEY /
# AS_USAGE_KEY.
AC_KEY="ctx"
AC_USAGE_KEY="usage"

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

# Warn — at most once per tmux server — about a missing dependency, then no-op.
# The flag lives in a global tmux option (no state files) keyed by <name>, so the
# 'airline' flag (@agent-tools-airline-warned) is shared with agent-state.sh and
# the user sees one airline message regardless of which signal fired first.
# Critically rate-limited: this runs per statusLine render (a few times a second),
# so warning every call would be noise. The JSON has already passed through on
# stdout by the time we get here, so the status line never breaks — warn to stderr.
ac_warn_once() {   # <name> <message>
  local flag="@agent-tools-$1-warned"
  [ "$(tmux show -gqv "$flag" 2>/dev/null)" = 1 ] && return 0
  tmux set -g "$flag" 1 2>/dev/null
  printf 'agent-context: %s\n' "$2" >&2
}

# jq is a hard dependency: an agent speaks JSON, and jq is the tool for JSON — no
# brittle hand-rolled parse. A seam (overridable in tests) for the one presence
# check. The statusLine JSON now carries sibling used_percentage keys (rate_limits),
# so a precise jq path is the only correct reader, not a first-match grep.
ac_have_jq() { command -v jq >/dev/null 2>&1; }

# Map a used-percentage to a health severity, given the two thresholds. Empty
# = clear. Pure: thresholds are passed in, not read from tmux.
ac_tier() {
  local pct="$1" alert="$2" stress="$3"
  case "$pct" in ''|*[!0-9]*) echo ""; return 0 ;; esac   # non-numeric -> clear
  if   [ "$pct" -ge "$stress" ]; then echo "stress"
  elif [ "$pct" -ge "$alert"  ]; then echo "alert"
  else                                echo ""
  fi
}

# Extract context_window.used_percentage (integer part) from the statusLine JSON
# with jq — the precise path, scoped to the context_window object so the sibling
# used_percentage keys (rate_limits) can't be mistaken for it. Empty when the
# field is absent/null (early in a session, or just after /compact), which ac_tier
# then treats as "clear". Callers must confirm ac_have_jq first.
ac_extract_pct() {
  local pct
  pct=$(printf '%s' "$1" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
  printf '%s' "${pct%%.*}"   # integer part only
}

# Extract the usage-limit pressure: the WORSE (max) of the two rate-limit windows
# (five_hour, seven_day), as an integer percent. rate_limits appears only for
# Claude.ai Pro/Max sessions and each window may be independently absent, so jq
# gathers whatever is present and takes the max; empty when neither is set (and
# ac_tier then treats that as "clear"). Callers must confirm ac_have_jq first.
ac_extract_usage() {
  local pct
  pct=$(printf '%s' "$1" | jq -r '
    [.rate_limits.five_hour.used_percentage, .rate_limits.seven_day.used_percentage]
    | map(select(. != null)) | max // empty' 2>/dev/null)
  printf '%s' "${pct%%.*}"   # integer part only
}

# Read the statusLine JSON from stdin, report the context severity on the health
# channel by tier, and pass the JSON through unchanged (so it composes with a
# real status line). The passthrough happens first, so the status line never
# breaks; outside tmux it's a silent no-op. A missing dependency (airline or jq)
# warns once per server (see ac_warn_once) and then no-ops the health write.
# Report one health key: set it to <token> (a severity), or clear it when the
# token is empty. Factored out so the two meters share the set-or-clear path.
ac_report() {   # <airline> <key> <token>
  if [ -n "$3" ]; then
    "$1" health set "$2" "$3" -t "$TMUX_PANE"
  else
    "$1" health clear "$2" -t "$TMUX_PANE"
  fi
}

# Read an alert/stress threshold pair from tmux options with defaults. Prints
# "<alert> <stress>". <prefix> is the option base, e.g. @agent-context.
ac_thresholds() {   # <prefix> <default-alert> <default-stress>
  local alert stress
  alert=$(tmux show -gqv "$1-alert");   [ -n "$alert" ]  || alert=$2
  stress=$(tmux show -gqv "$1-stress"); [ -n "$stress" ] || stress=$3
  printf '%s %s' "$alert" "$stress"
}

ac_apply() {
  local json airline alert stress
  json=$(cat)
  printf '%s' "$json"        # passthrough first: the status line always renders

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(ac_airline); [ -n "$airline" ] || {
    ac_warn_once airline "airline CLI not found — set @airline-cli (load tmux-airline first) or the AIRLINE_BIN env var; status/health signals disabled"
    return 0
  }
  ac_have_jq || {
    ac_warn_once jq "jq not found — required to read the statusLine JSON; context/usage health disabled (install jq)"
    return 0
  }

  # Context-window fill -> 'ctx' key.
  read -r alert stress <<<"$(ac_thresholds @agent-context 80 90)"
  ac_report "$airline" "$AC_KEY" "$(ac_tier "$(ac_extract_pct "$json")" "$alert" "$stress")"

  # Usage limit (worse of the two rate-limit windows) -> 'usage' key.
  read -r alert stress <<<"$(ac_thresholds @agent-usage 80 90)"
  ac_report "$airline" "$AC_USAGE_KEY" "$(ac_tier "$(ac_extract_usage "$json")" "$alert" "$stress")"
  # No refresh here: airline redraws only when the reduced severity changed, so a
  # statusLine that fires several times a second at a steady level costs one write
  # per key and zero redraws. Our own refresh would undo that gating.
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -euo pipefail
  ac_apply
fi
