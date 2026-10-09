#!/usr/bin/env bash
# Report Claude statusLine resource measurements through Airline, preserving stdin.

# Health contributors are pane-qualified so separate Claude sessions in panes of
# the same window reduce independently through airline's health collection.
AGENT_CLAUDE_TELEMETRY_KEY_PREFIX="ctx"
AGENT_CLAUDE_TELEMETRY_USAGE_KEY_PREFIX="usage"
AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR="tmux-agent-tools-claude-telemetry"
AGENT_CLAUDE_TELEMETRY_PROBLEM_JQ_KEY="jq"
AGENT_CLAUDE_TELEMETRY_PROBLEM_INPUT_KEY="input"
AGENT_CLAUDE_TELEMETRY_PROBLEM_UPDATE_KEY="health-update"

agent_claude_telemetry_key() { printf '%s-%s' "$1" "${TMUX_PANE#%}"; }

# Kept separate so telemetry failure tests can simulate a missing parser.
agent_claude_telemetry_have_jq() { command -v jq >/dev/null 2>&1; }

# Map a used-percentage to a health condition, given the two thresholds. Empty
# = recovered/ok. Pure: thresholds are passed in, not read from tmux.
agent_claude_telemetry_tier() {
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
agent_claude_telemetry_extract_metrics() {
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
agent_claude_telemetry_report() {   # <airline> <key> <token> [<message>]
  if [ -n "$3" ]; then
    "$1" health set -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$2" "$3" "$4"
  else
    "$1" health set -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$2" ok
  fi
}

agent_claude_telemetry_problem_raise() {   # <airline> <key> <category> <message>
  local airline="$1" key="$2" category="$3" message="$4"
  if "$airline" problem set -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$key" fail "$message"; then
    agent_warn_once "$category" "agent telemetry claude" "$message"
  else
    agent_warn_once problem "agent telemetry claude" "unable to report Claude telemetry problem through airline: $message"
  fi
}

agent_claude_telemetry_problem_recover_key() {   # <airline> <key>
  if ! "$1" problem set -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$2" ok; then
    agent_warn_once problem "agent telemetry claude" "unable to recover Claude telemetry problem through airline"
  fi
}

agent_claude_telemetry_problem_resolve_key() {   # <airline> <key>
  if ! "$1" problem resolve "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$2"; then
    agent_warn_once problem "agent telemetry claude" "unable to resolve Claude telemetry problem through airline"
  fi
}

# A degraded adapter must not leave its last successfully reported health values
# stuck on screen. Clear this pane's meters, retain the input passthrough, record
# the pane-originated capability problem, and return success to Claude's
# statusLine runner.
agent_claude_telemetry_degrade() {   # <airline> <key> <category> <message>
  local airline="$1" key="$2" category="$3" message="$4"
  "$airline" health clear -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$(agent_claude_telemetry_key "$AGENT_CLAUDE_TELEMETRY_KEY_PREFIX")" || true
  "$airline" health clear -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$(agent_claude_telemetry_key "$AGENT_CLAUDE_TELEMETRY_USAGE_KEY_PREFIX")" || true
  agent_claude_telemetry_problem_raise "$airline" "$key" "$category" "$message"
  return 0
}

# Clear only this pane's Claude health contributors. Lifecycle hooks use this at
# session boundaries; unlike the statusLine mode it intentionally emits nothing.
agent_claude_telemetry_clear() {
  local airline
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(agent_airline_resolve); [ -n "$airline" ] || return 0
  "$airline" health clear -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$(agent_claude_telemetry_key "$AGENT_CLAUDE_TELEMETRY_KEY_PREFIX")" || true
  "$airline" health clear -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR" "$(agent_claude_telemetry_key "$AGENT_CLAUDE_TELEMETRY_USAGE_KEY_PREFIX")" || true
  # The telemetry origin ended without demonstrating recovery. Close every claim
  # from this pane; Airline retains closed history and keeps other origins active.
  if ! "$airline" problem close -t "$TMUX_PANE" "$AGENT_CLAUDE_TELEMETRY_CONTRIBUTOR"; then
    agent_warn_once problem "agent telemetry claude" "unable to close Claude telemetry problems through airline"
  fi
}

# Read a warn/fail threshold pair from tmux options with defaults. Prints
# "<warn> <fail>". <prefix> is the option base, e.g. @agent-tools-context.
agent_claude_telemetry_thresholds() {   # <prefix> <default-warn> <default-fail>
  local warn fail
  warn=$(tmux show -gqv "$1-warn"); [ -n "$warn" ] || warn=$2
  fail=$(tmux show -gqv "$1-fail"); [ -n "$fail" ] || fail=$3
  printf '%s %s' "$warn" "$fail"
}

agent_claude_telemetry_update() {
  local json airline metrics context usage warn fail report_ok=1
  json=$(cat)
  printf '%s' "$json"        # passthrough first: the status line always renders

  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  airline=$(agent_airline_resolve); [ -n "$airline" ] || return 0
  agent_claude_telemetry_have_jq || {
    agent_claude_telemetry_degrade "$airline" "$AGENT_CLAUDE_TELEMETRY_PROBLEM_JQ_KEY" jq \
      "Claude context/usage health unavailable: jq not found"
    return 0
  }
  # jq is a shared contributor capability. Detecting it authoritatively resolves
  # the global problem, including stale claims from origins that have not rerun.
  agent_claude_telemetry_problem_resolve_key "$airline" "$AGENT_CLAUDE_TELEMETRY_PROBLEM_JQ_KEY"
  if ! metrics=$(agent_claude_telemetry_extract_metrics "$json"); then
    agent_claude_telemetry_degrade "$airline" "$AGENT_CLAUDE_TELEMETRY_PROBLEM_INPUT_KEY" json \
      "Claude context/usage health unavailable for pane $TMUX_PANE: invalid statusLine JSON"
    return 0
  fi
  case "$metrics" in
    *$'\t'*) context="${metrics%%$'\t'*}"; usage="${metrics#*$'\t'}" ;;
    *)
      agent_claude_telemetry_degrade "$airline" "$AGENT_CLAUDE_TELEMETRY_PROBLEM_INPUT_KEY" json \
        "Claude context/usage health unavailable for pane $TMUX_PANE: invalid metrics payload"
      return 0
      ;;
  esac
  # This pane's input stream recovered even if an outbound health update below
  # subsequently fails.
  agent_claude_telemetry_problem_recover_key "$airline" "$AGENT_CLAUDE_TELEMETRY_PROBLEM_INPUT_KEY"

  # Context-window fill -> 'ctx' key.
  read -r warn fail <<<"$(agent_claude_telemetry_thresholds @agent-tools-context 80 90)"
  agent_claude_telemetry_report "$airline" "$(agent_claude_telemetry_key "$AGENT_CLAUDE_TELEMETRY_KEY_PREFIX")" \
    "$(agent_claude_telemetry_tier "$context" "$warn" "$fail")" \
    "Claude context window ${context}% used in pane $TMUX_PANE" || report_ok=0

  # Usage limit (worse of the two rate-limit windows) -> 'usage' key.
  read -r warn fail <<<"$(agent_claude_telemetry_thresholds @agent-tools-usage 80 90)"
  agent_claude_telemetry_report "$airline" "$(agent_claude_telemetry_key "$AGENT_CLAUDE_TELEMETRY_USAGE_KEY_PREFIX")" \
    "$(agent_claude_telemetry_tier "$usage" "$warn" "$fail")" \
    "Claude usage limit ${usage}% used in pane $TMUX_PANE" || report_ok=0
  if [ "$report_ok" -ne 1 ]; then
    agent_claude_telemetry_degrade "$airline" "$AGENT_CLAUDE_TELEMETRY_PROBLEM_UPDATE_KEY" airline \
      "Claude context/usage health unavailable for pane $TMUX_PANE: airline health update failed"
    return 0
  fi
  # Airline's keyed recoveries are idempotent, so report this final capability's
  # recovery every evaluation. This pane cannot erase another pane's update
  # diagnostic.
  agent_claude_telemetry_problem_recover_key "$airline" "$AGENT_CLAUDE_TELEMETRY_PROBLEM_UPDATE_KEY"
  # No refresh here: airline redraws only when the reduced condition changed, so a
  # statusLine that fires several times a second at a steady level costs one write
  # per key and zero redraws. Our own refresh would undo that gating.
}
