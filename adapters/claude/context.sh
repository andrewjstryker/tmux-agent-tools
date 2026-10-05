#!/usr/bin/env bash
# context.sh — adapt Claude Code statusLine resource data to
# tmux-airline's health channel (the `airline health` CLI).
#
# Two meters, both exposed only to a Claude Code *statusLine* command (hooks
# don't get them), so this is wired as one. It reads the statusLine JSON on
# stdin, maps each meter to a condition, reports them on the calling pane's
# window, and passes the JSON through unchanged so it can be piped into your real
# status line. When the adapter cannot provide those signals it raises a global
# Airline problem while retaining the calling pane as the claim origin.
#
#   "statusLine": { "type": "command",
#     "command": "$(tmux show -gqv @agent-cli) telemetry claude update | your-status-line" }
#
# The two meters:
#   * context-window fill — context_window.used_percentage, under the 'ctx' key.
#   * usage-limit         — the worse of rate_limits.{five_hour,seven_day}
#                           .used_percentage (Claude.ai Pro/Max only; each window
#                           may be absent), under the 'usage' key.
#
# Both are *meters* (sustained conditions), so they use the right health gutter —
# distinct from the lifecycle *status lane* (badge) that lifecycle.sh drives.
# All three coexist on a window. airline reduces all health contributors to the
# worst condition, so a busy window shows one gutter glyph at the max. Thresholds
# are percent and overridable via tmux options (each meter has its own pair):
#   @agent-tools-context-warn (default 80) -> warn (amber gutter glyph)
#   @agent-tools-context-fail (default 90) -> fail (red gutter glyph)
#   @agent-tools-usage-warn   (default 80) -> warn
#   @agent-tools-usage-fail   (default 90) -> fail
# Below the warn threshold the reporter records `ok` recovery.
#
# Layered like lifecycle.sh: the pure mapping (ac_tier) is split from the CLI
# writes (ac_apply) so the bats suite can drive it without a tmux server.

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
# shellcheck source=lib/tmux.sh
source "$AGENT_ROOT/lib/tmux.sh"
# shellcheck source=lib/airline.sh
source "$AGENT_ROOT/lib/airline.sh"

# Health contributors are pane-qualified so separate Claude sessions in panes of
# the same window reduce independently through airline's health collection.
AC_KEY_PREFIX="ctx"
AC_USAGE_KEY_PREFIX="usage"
AC_TELEMETRY_CONTRIBUTOR="tmux-agent-tools-claude-telemetry"
AC_PROBLEM_JQ_KEY="jq"
AC_PROBLEM_INPUT_KEY="input"
AC_PROBLEM_UPDATE_KEY="health-update"

ac_key() { printf '%s-%s' "$1" "${TMUX_PANE#%}"; }

ac_die() { printf 'claude-context: %s\n' "$*" >&2; return 1; }

# Warn — at most once per tmux server — about a missing dependency, then no-op.
# The flag lives in a global tmux option (no state files) keyed by <name>, so the
# 'airline' flag (@agent-tools-airline-warned) is shared with lifecycle.sh and
# the user sees one airline message regardless of which signal fired first.
# Critically rate-limited: this runs per statusLine render (a few times a second),
# so warning every call would be noise. The JSON has already passed through on
# stdout by the time we get here, so the status line never breaks — warn to stderr.
ac_warn_once() {   # <name> <message>
  agent_airline_warn_once "$1" claude-context "$2"
}

# jq is a hard dependency for this adapter: Claude speaks JSON and jq is the tool
# for JSON — no brittle hand-rolled parse. A seam for the one presence
# check. The statusLine JSON now carries sibling used_percentage keys (rate_limits),
# so a precise jq path is the only correct reader, not a first-match grep.
ac_have_jq() { command -v jq >/dev/null 2>&1; }

# Map a used-percentage to a health condition, given the two thresholds. Empty
# = recovered/ok. Pure: thresholds are passed in, not read from tmux.
ac_tier() {
  local pct="$1" warn="$2" fail="$3"
  case "$pct" in ''|*[!0-9]*) echo ""; return 0 ;; esac   # non-numeric -> clear
  if   [ "$pct" -ge "$fail" ]; then echo "fail"
  elif [ "$pct" -ge "$warn" ]; then echo "warn"
  else                              echo ""
  fi
}

# Parse and extract both meters in one jq process. Output is
# "<context><TAB><usage>"; either field may be empty. Invalid JSON is distinct
# from an absent field because jq's nonzero exit status is preserved.
ac_extract_metrics() {
  printf '%s' "$1" | jq -r '
    def integer_part:
      if . == null then "" else tostring | split(".")[0] end;
    [
      (.context_window.used_percentage | integer_part),
      ([.rate_limits.five_hour.used_percentage,
        .rate_limits.seven_day.used_percentage]
       | map(select(. != null)) | max | integer_part)
    ] | @tsv' 2>/dev/null
}

# Read the statusLine JSON from stdin, report each resource condition on health
# by tier, and pass the JSON through unchanged (so it composes with a
# real status line). The passthrough happens first, so the status line never
# breaks; outside tmux it's a silent no-op. Missing airline warns locally; other
# degradation is retained through airline's problem API.
# Report one health key: set it to a condition token, or report recovery when the
# token is empty. Factored out so the two meters share the observation path.
ac_report() {   # <airline> <key> <token> [<message>]
  if [ -n "$3" ]; then
    "$1" health set -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$2" "$3" "$4"
  else
    "$1" health set -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$2" ok
  fi
}

ac_problem_raise() {   # <airline> <key> <category> <message>
  local airline="$1" key="$2" category="$3" message="$4"
  if "$airline" problem set -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$key" fail "$message"; then
    ac_warn_once "$category" "$message"
  else
    ac_warn_once problem "unable to report Claude telemetry problem through airline: $message"
  fi
}

ac_problem_recover_key() {   # <airline> <key>
  if ! "$1" problem set -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$2" ok; then
    ac_warn_once problem "unable to recover Claude telemetry problem through airline"
  fi
}

ac_problem_resolve_key() {   # <airline> <key>
  if ! "$1" problem resolve "$AC_TELEMETRY_CONTRIBUTOR" "$2"; then
    ac_warn_once problem "unable to resolve Claude telemetry problem through airline"
  fi
}

# A degraded adapter must not leave its last successfully reported health values
# stuck on screen. Clear this pane's meters, retain the input passthrough, record
# the pane-originated capability problem, and return success to Claude's
# statusLine runner.
ac_degrade() {   # <airline> <key> <category> <message>
  local airline="$1" key="$2" category="$3" message="$4"
  "$airline" health clear -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$(ac_key "$AC_KEY_PREFIX")" || true
  "$airline" health clear -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$(ac_key "$AC_USAGE_KEY_PREFIX")" || true
  ac_problem_raise "$airline" "$key" "$category" "$message"
  return 0
}

# Clear only this pane's Claude health contributors. Lifecycle hooks use this at
# session boundaries; unlike the statusLine mode it intentionally emits nothing.
ac_clear() {
  local airline
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(agent_airline_resolve claude-context); [ -n "$airline" ] || return 0
  "$airline" health clear -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$(ac_key "$AC_KEY_PREFIX")" || true
  "$airline" health clear -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR" "$(ac_key "$AC_USAGE_KEY_PREFIX")" || true
  # The telemetry origin ended without demonstrating recovery. Close every claim
  # from this pane; Airline retains closed history and keeps other origins active.
  if ! "$airline" problem close -t "$TMUX_PANE" "$AC_TELEMETRY_CONTRIBUTOR"; then
    ac_warn_once problem "unable to close Claude telemetry problems through airline"
  fi
}

# Read a warn/fail threshold pair from tmux options with defaults. Prints
# "<warn> <fail>". <prefix> is the option base, e.g. @agent-tools-context.
ac_thresholds() {   # <prefix> <default-warn> <default-fail>
  local warn fail
  warn=$(agent_tmux_global_get "$1-warn"); [ -n "$warn" ] || warn=$2
  fail=$(agent_tmux_global_get "$1-fail"); [ -n "$fail" ] || fail=$3
  printf '%s %s' "$warn" "$fail"
}

ac_apply() {
  local json airline metrics context usage warn fail report_ok=1
  json=$(cat)
  printf '%s' "$json"        # passthrough first: the status line always renders

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(agent_airline_resolve claude-context); [ -n "$airline" ] || return 0
  ac_have_jq || {
    ac_degrade "$airline" "$AC_PROBLEM_JQ_KEY" jq \
      "Claude context/usage health unavailable: jq not found"
    return 0
  }
  # jq is a shared contributor capability. Detecting it authoritatively resolves
  # the global problem, including stale claims from origins that have not rerun.
  ac_problem_resolve_key "$airline" "$AC_PROBLEM_JQ_KEY"
  if ! metrics=$(ac_extract_metrics "$json"); then
    ac_degrade "$airline" "$AC_PROBLEM_INPUT_KEY" json \
      "Claude context/usage health unavailable for pane $TMUX_PANE: invalid statusLine JSON"
    return 0
  fi
  case "$metrics" in
    *$'\t'*) context="${metrics%%$'\t'*}"; usage="${metrics#*$'\t'}" ;;
    *)
      ac_degrade "$airline" "$AC_PROBLEM_INPUT_KEY" json \
        "Claude context/usage health unavailable for pane $TMUX_PANE: invalid metrics payload"
      return 0
      ;;
  esac
  # This pane's input stream recovered even if an outbound health update below
  # subsequently fails.
  ac_problem_recover_key "$airline" "$AC_PROBLEM_INPUT_KEY"

  # Context-window fill -> 'ctx' key.
  read -r warn fail <<<"$(ac_thresholds @agent-tools-context 80 90)"
  ac_report "$airline" "$(ac_key "$AC_KEY_PREFIX")" \
    "$(ac_tier "$context" "$warn" "$fail")" \
    "Claude context window ${context}% used in pane $TMUX_PANE" || report_ok=0

  # Usage limit (worse of the two rate-limit windows) -> 'usage' key.
  read -r warn fail <<<"$(ac_thresholds @agent-tools-usage 80 90)"
  ac_report "$airline" "$(ac_key "$AC_USAGE_KEY_PREFIX")" \
    "$(ac_tier "$usage" "$warn" "$fail")" \
    "Claude usage limit ${usage}% used in pane $TMUX_PANE" || report_ok=0
  if [ "$report_ok" -ne 1 ]; then
    ac_degrade "$airline" "$AC_PROBLEM_UPDATE_KEY" airline \
      "Claude context/usage health unavailable for pane $TMUX_PANE: airline health update failed"
    return 0
  fi
  # Airline's keyed recoveries are idempotent, so report this final capability's
  # recovery every evaluation. This pane cannot erase another pane's update
  # diagnostic.
  ac_problem_recover_key "$airline" "$AC_PROBLEM_UPDATE_KEY"
  # No refresh here: airline redraws only when the reduced condition changed, so a
  # statusLine that fires several times a second at a steady level costs one write
  # per key and zero redraws. Our own refresh would undo that gating.
}

ac_main() {
  set -euo pipefail
  case "${1:-update}" in
    update) [ $# -le 1 ] || ac_die "usage: context.sh [update|clear]"; ac_apply ;;
    clear)  [ $# -eq 1 ] || ac_die "usage: context.sh [update|clear]"; ac_clear ;;
    *)      ac_die "usage: context.sh [update|clear]" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  ac_main "$@"
fi
