#!/usr/bin/env bats
# Tests for adapters/claude/context.sh.
#
# ac_tier and ac_extract_metrics are pure. ac_apply drives the
# airline CLI; its calls are checked against a fake `airline` on PATH (pointed at
# via $AIRLINE_BIN) that logs its arguments. A fake `tmux` answers `show`
# (threshold options) and absorbs refresh-client. $TMUX/$TMUX_PANE are set so
# ac_apply proceeds (unset in the no-op test).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../adapters/claude/context.sh"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agctx.XXXXXX")"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  export FAKE_AIRLINE_LOG="${TESTDIR}/airline.log"
  export FAKE_WARN=80 FAKE_FAIL=90                # context thresholds the fake `tmux show` returns
  export FAKE_USAGE_WARN=80 FAKE_USAGE_FAIL=90    # usage-limit thresholds
  : > "$FAKE_TMUX_LOG"; : > "$FAKE_AIRLINE_LOG"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-tmux" "${FAKE_BIN}/tmux"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-airline" "${FAKE_BIN}/airline"
  PATH="${FAKE_BIN}:${PATH}"
  export AIRLINE_BIN="${FAKE_BIN}/airline"
  export TMUX="/tmp/fake,1,0"
  export TMUX_PANE="%3"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

# --- pure tier mapping ---

@test "tier: below warn maps to recovery" {
  source "$SCRIPT"; run ac_tier 50 80 90; [ -z "$output" ]
}

@test "tier: at the warn threshold is warn" {
  source "$SCRIPT"; run ac_tier 80 80 90; [ "$output" = "warn" ]
}

@test "tier: between thresholds is warn" {
  source "$SCRIPT"; run ac_tier 85 80 90; [ "$output" = "warn" ]
}

@test "tier: at the fail threshold is fail" {
  source "$SCRIPT"; run ac_tier 90 80 90; [ "$output" = "fail" ]
}

@test "tier: above the fail threshold is fail" {
  source "$SCRIPT"; run ac_tier 99 80 90; [ "$output" = "fail" ]
}

@test "tier: non-numeric maps to recovery" {
  source "$SCRIPT"; run ac_tier "" 80 90; [ -z "$output" ]
}

# --- metric extraction ---

@test "extract: returns context and worst usage in one tuple" {
  source "$SCRIPT"
  run ac_extract_metrics '{"context_window":{"used_percentage":87.4},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":41.2}}}'
  [ "$output" = $'87\t41' ]
}

@test "extract: missing fields produce an empty tuple" {
  source "$SCRIPT"
  run ac_extract_metrics '{"model":{"display_name":"x"}}'
  [ "$output" = $'\t' ]
}

@test "extract: not fooled by sibling used_percentage keys (rate_limits)" {
  source "$SCRIPT"
  # rate_limits.*.used_percentage are siblings in the real schema; the jq path is
  # scoped to context_window, so it must return 8 — not 23 or 41.
  run ac_extract_metrics '{"context_window":{"used_percentage":8},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":41.2}}}'
  [ "$output" = $'8\t41' ]
}

@test "usage: one window absent uses the other" {
  source "$SCRIPT"
  run ac_extract_metrics '{"rate_limits":{"five_hour":{"used_percentage":67}}}'
  [ "$output" = $'\t67' ]
}

@test "usage: no rate_limits (non-subscriber) yields empty" {
  source "$SCRIPT"
  run ac_extract_metrics '{"context_window":{"used_percentage":50}}'
  [ "$output" = $'50\t' ]
}

@test "extract: malformed JSON fails" {
  source "$SCRIPT"
  run ac_extract_metrics '{bad json'
  [ "$status" -ne 0 ]
}

# --- applying via the airline CLI ---

@test "apply: high usage reports fail health" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":95}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry ctx-3 fail Claude context window 95% used in pane %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: mid usage reports warn health" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":83}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry ctx-3 warn Claude context window 83% used in pane %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: low usage reports health recovery" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":40}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry ctx-3 ok" "$FAKE_AIRLINE_LOG"
}

@test "apply: thresholds are overridable via tmux options" {
  source "$SCRIPT"
  FAKE_WARN=50 FAKE_FAIL=70
  echo '{"context_window":{"used_percentage":55}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry ctx-3 warn Claude context window 55% used in pane %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: high rate-limit reports fail on the usage key" {
  source "$SCRIPT"
  echo '{"rate_limits":{"seven_day":{"used_percentage":95}}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry usage-3 fail Claude usage limit 95% used in pane %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: mid rate-limit reports warn on the usage key" {
  source "$SCRIPT"
  echo '{"rate_limits":{"five_hour":{"used_percentage":83}}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry usage-3 warn Claude usage limit 83% used in pane %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: no rate_limits reports usage health recovery" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":40}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry usage-3 ok" "$FAKE_AIRLINE_LOG"
}

@test "apply: usage thresholds are independently overridable" {
  source "$SCRIPT"
  FAKE_USAGE_WARN=50 FAKE_USAGE_FAIL=70   # context stays 80/90
  echo '{"context_window":{"used_percentage":55},"rate_limits":{"five_hour":{"used_percentage":55}}}' | ac_apply >/dev/null
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry usage-3 warn Claude usage limit 55% used in pane %3" "$FAKE_AIRLINE_LOG" # 55 >= usage warn 50
  grep -q "health set -t %3 tmux-agent-tools-claude-telemetry ctx-3 ok" "$FAKE_AIRLINE_LOG" # 55 < context warn 80
}

@test "keys: health contributors are qualified by the calling pane" {
  source "$SCRIPT"
  TMUX_PANE=%9
  [ "$(ac_key "$AC_KEY_PREFIX")" = "ctx-9" ]
  [ "$(ac_key "$AC_USAGE_KEY_PREFIX")" = "usage-9" ]
}

@test "clear: removes only the calling pane's Claude health contributors" {
  source "$SCRIPT"
  ac_clear
  grep -q "health clear -t %3 tmux-agent-tools-claude-telemetry ctx-3" "$FAKE_AIRLINE_LOG"
  grep -q "health clear -t %3 tmux-agent-tools-claude-telemetry usage-3" "$FAKE_AIRLINE_LOG"
  grep -q 'problem close -t %3 tmux-agent-tools-claude-telemetry' "$FAKE_AIRLINE_LOG"
}

@test "main: clear emits no statusLine output" {
  run bash "$SCRIPT" clear
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "main: rejects an unknown command" {
  run bash "$SCRIPT" bogus
  [ "$status" -ne 0 ]
}

@test "apply: passes the JSON through unchanged on stdout" {
  source "$SCRIPT"
  local json='{"context_window":{"used_percentage":95},"model":{"display_name":"x"}}'
  run bash -c "printf '%s' '$json' | { source '$SCRIPT'; ac_apply; }"
  [ "$output" = "$json" ]
}

@test "apply: does not refresh the client itself (airline owns the redraw)" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":95}}' | ac_apply >/dev/null
  ! grep -q "refresh-client" "$FAKE_TMUX_LOG"
}

@test "apply: outside tmux, still passes JSON through but writes nothing" {
  source "$SCRIPT"
  unset TMUX TMUX_PANE
  local json='{"context_window":{"used_percentage":95}}'
  run bash -c "unset TMUX TMUX_PANE; printf '%s' '$json' | { source '$SCRIPT'; ac_apply; }"
  [ "$output" = "$json" ]
  [ ! -s "$FAKE_TMUX_LOG" ]
  [ ! -s "$FAKE_AIRLINE_LOG" ]
}

@test "apply: missing airline still passes JSON through, and warns once" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset AIRLINE_BIN   # no airline anywhere
  local json='{"context_window":{"used_percentage":95}}'
  # stderr (the warning) is separated to a file so stdout stays pure JSON.
  run bash -c "printf '%s' '$json' | { source '$SCRIPT'; ac_apply 2>'${TESTDIR}/err'; }"
  [ "$output" = "$json" ]                          # status line never breaks
  grep -q "airline CLI not found" "${TESTDIR}/err" # but the misconfig is visible
  [ ! -s "$FAKE_AIRLINE_LOG" ]
}

@test "apply: missing-airline warning is suppressed once already warned" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset AIRLINE_BIN
  export FAKE_WARNED=1                             # flag already set this server
  local json='{"context_window":{"used_percentage":95}}'
  run bash -c "printf '%s' '$json' | { source '$SCRIPT'; ac_apply 2>'${TESTDIR}/err'; }"
  [ "$output" = "$json" ]
  [ ! -s "${TESTDIR}/err" ]                        # silent the second time
}

@test "apply: missing jq is a global problem with the calling pane as origin" {
  source "$SCRIPT"
  ac_have_jq() { return 1; }                        # simulate jq absent via the seam
  local json='{"context_window":{"used_percentage":95}}'
  # Pipeline subshell inherits the ac_have_jq override; stderr split off to a file.
  out=$(printf '%s' "$json" | ac_apply 2>"${TESTDIR}/err")
  [ "$out" = "$json" ]                              # status line never breaks
  grep -q "jq not found" "${TESTDIR}/err"           # the missing dep is visible
  grep -q "health clear -t %3 tmux-agent-tools-claude-telemetry ctx-3" "$FAKE_AIRLINE_LOG"
  grep -q "health clear -t %3 tmux-agent-tools-claude-telemetry usage-3" "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry jq fail .*jq not found' "$FAKE_AIRLINE_LOG"
  ! grep -q 'session_id' "$FAKE_TMUX_LOG"
}

@test "apply: malformed JSON degrades without breaking passthrough" {
  source "$SCRIPT"
  local json='{bad json'
  out=$(printf '%s' "$json" | ac_apply 2>"${TESTDIR}/err")
  [ "$out" = "$json" ]
  grep -q "invalid statusLine JSON" "${TESTDIR}/err"
  grep -q 'problem resolve tmux-agent-tools-claude-telemetry jq' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry input fail .*pane %3: invalid statusLine JSON' "$FAKE_AIRLINE_LOG"
  ! grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry input ok' "$FAKE_AIRLINE_LOG"
}

@test "apply: airline health failure becomes a graceful adapter problem" {
  source "$SCRIPT"
  export FAKE_AIRLINE_FAIL=health
  local json='{"context_window":{"used_percentage":40}}'
  out=$(printf '%s' "$json" | ac_apply 2>"${TESTDIR}/err")
  [ "$out" = "$json" ]
  grep -q "airline health update failed" "${TESTDIR}/err"
  grep -q 'problem resolve tmux-agent-tools-claude-telemetry jq' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry input ok' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry health-update fail .*pane %3: airline health update failed' "$FAKE_AIRLINE_LOG"
}

@test "apply: successful evaluation resolves shared jq and recovers pane claims" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":40}}' | ac_apply >/dev/null
  grep -q 'problem resolve tmux-agent-tools-claude-telemetry jq' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry input ok' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry health-update ok' "$FAKE_AIRLINE_LOG"
  ! grep -q 'problem clear' "$FAKE_AIRLINE_LOG"
}

@test "apply: degradation re-reports the same stable shared capability key" {
  source "$SCRIPT"
  ac_have_jq() { return 1; }
  echo '{}' | ac_apply >/dev/null
  echo '{}' | ac_apply >/dev/null
  [ "$(grep -c 'problem set -t %3 tmux-agent-tools-claude-telemetry jq fail .*jq not found' "$FAKE_AIRLINE_LOG")" -eq 2 ]
}

@test "apply: does not resolve a session" {
  source "$SCRIPT"
  echo '{}' | ac_apply >/dev/null
  ! grep -q 'session_id' "$FAKE_TMUX_LOG"
}

@test "input failures use independent pane-origin claims under one logical key" {
  source "$SCRIPT"
  printf '{bad' | ac_apply >/dev/null 2>&1
  TMUX_PANE=%9
  printf '{bad' | ac_apply >/dev/null 2>&1
  printf '{}' | ac_apply >/dev/null

  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry input fail' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %9 tmux-agent-tools-claude-telemetry input fail' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %9 tmux-agent-tools-claude-telemetry input ok' "$FAKE_AIRLINE_LOG"
  ! grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry input ok' "$FAKE_AIRLINE_LOG"
}

@test "multiple panes report jq under one shared key" {
  source "$SCRIPT"
  ac_have_jq() { return 1; }
  printf '{}' | ac_apply >/dev/null 2>&1
  TMUX_PANE=%9
  printf '{}' | ac_apply >/dev/null 2>&1

  grep -q 'problem set -t %3 tmux-agent-tools-claude-telemetry jq fail' "$FAKE_AIRLINE_LOG"
  grep -q 'problem set -t %9 tmux-agent-tools-claude-telemetry jq fail' "$FAKE_AIRLINE_LOG"
}

@test "a failed pane-origin problem mutation does not break passthrough" {
  source "$SCRIPT"
  export FAKE_AIRLINE_FAIL=problem
  local json='{bad'

  out=$(printf '%s' "$json" | ac_apply 2>"$TESTDIR/err")
  [ "$out" = "$json" ]
  grep -q 'unable to report Claude telemetry problem through airline' "$TESTDIR/err"
  grep -q '^problem set -t %3 ' "$FAKE_AIRLINE_LOG"
}
