#!/usr/bin/env bats
# Tests for scripts/agent-context.sh.
#
# ac_tier, ac_extract_pct and ac_extract_usage are pure. ac_apply drives the
# airline CLI; its calls are checked against a fake `airline` on PATH (pointed at
# via $AIRLINE_BIN) that logs its arguments. A fake `tmux` answers `show`
# (threshold options) and absorbs refresh-client. $TMUX/$TMUX_PANE are set so
# ac_apply proceeds (unset in the no-op test).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/agent-context.sh"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agctx.XXXXXX")"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  export FAKE_AIRLINE_LOG="${TESTDIR}/airline.log"
  export FAKE_ALERT=80 FAKE_STRESS=90                # context thresholds the fake `tmux show` returns
  export FAKE_USAGE_ALERT=80 FAKE_USAGE_STRESS=90    # usage-limit thresholds
  : > "$FAKE_TMUX_LOG"; : > "$FAKE_AIRLINE_LOG"
  cat > "${FAKE_BIN}/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
case "$*" in
  *@agent-context-alert*)  printf '%s' "${FAKE_ALERT}" ;;
  *@agent-context-stress*) printf '%s' "${FAKE_STRESS}" ;;
  *@agent-usage-alert*)    printf '%s' "${FAKE_USAGE_ALERT}" ;;
  *@agent-usage-stress*)   printf '%s' "${FAKE_USAGE_STRESS}" ;;
  *@agent-tools-airline-warned*) printf '%s' "${FAKE_WARNED:-}" ;;
esac
SH
  cat > "${FAKE_BIN}/airline" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_AIRLINE_LOG"
SH
  chmod +x "${FAKE_BIN}/tmux" "${FAKE_BIN}/airline"
  PATH="${FAKE_BIN}:${PATH}"
  export AIRLINE_BIN="${FAKE_BIN}/airline"
  export TMUX="/tmp/fake,1,0"
  export TMUX_PANE="%3"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

# --- pure tier mapping ---

@test "tier: below alert clears" {
  source "$SCRIPT"; run ac_tier 50 80 90; [ -z "$output" ]
}

@test "tier: at the alert threshold is alert" {
  source "$SCRIPT"; run ac_tier 80 80 90; [ "$output" = "alert" ]
}

@test "tier: between thresholds is alert" {
  source "$SCRIPT"; run ac_tier 85 80 90; [ "$output" = "alert" ]
}

@test "tier: at the stress threshold is stress" {
  source "$SCRIPT"; run ac_tier 90 80 90; [ "$output" = "stress" ]
}

@test "tier: above the stress threshold is stress" {
  source "$SCRIPT"; run ac_tier 99 80 90; [ "$output" = "stress" ]
}

@test "tier: non-numeric clears" {
  source "$SCRIPT"; run ac_tier "" 80 90; [ -z "$output" ]
}

# --- percentage extraction ---

@test "extract: pulls the integer used_percentage from JSON" {
  source "$SCRIPT"
  run ac_extract_pct '{"context_window":{"used_percentage":87.4},"model":{}}'
  [ "$output" = "87" ]
}

@test "extract: missing field yields empty" {
  source "$SCRIPT"
  run ac_extract_pct '{"model":{"display_name":"x"}}'
  [ -z "$output" ]
}

@test "extract: not fooled by sibling used_percentage keys (rate_limits)" {
  source "$SCRIPT"
  # rate_limits.*.used_percentage are siblings in the real schema; the jq path is
  # scoped to context_window, so it must return 8 — not 23 or 41.
  run ac_extract_pct '{"context_window":{"used_percentage":8},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":41.2}}}'
  [ "$output" = "8" ]
}

# --- usage-limit extraction (worse of the two rate-limit windows) ---

@test "usage: takes the worse of the two windows (integer)" {
  source "$SCRIPT"
  run ac_extract_usage '{"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":41.2}}}'
  [ "$output" = "41" ]
}

@test "usage: one window absent uses the other" {
  source "$SCRIPT"
  run ac_extract_usage '{"rate_limits":{"five_hour":{"used_percentage":67}}}'
  [ "$output" = "67" ]
}

@test "usage: no rate_limits (non-subscriber) yields empty" {
  source "$SCRIPT"
  run ac_extract_usage '{"context_window":{"used_percentage":50}}'
  [ -z "$output" ]
}

# --- applying via the airline CLI ---

@test "apply: high usage reports stress health" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":95}}' | ac_apply >/dev/null
  grep -q "health set ctx stress -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: mid usage reports alert health" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":83}}' | ac_apply >/dev/null
  grep -q "health set ctx alert -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: low usage clears the health key" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":40}}' | ac_apply >/dev/null
  grep -q "health clear ctx -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: thresholds are overridable via tmux options" {
  source "$SCRIPT"
  FAKE_ALERT=50 FAKE_STRESS=70
  echo '{"context_window":{"used_percentage":55}}' | ac_apply >/dev/null
  grep -q "health set ctx alert -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: high rate-limit reports stress on the usage key" {
  source "$SCRIPT"
  echo '{"rate_limits":{"seven_day":{"used_percentage":95}}}' | ac_apply >/dev/null
  grep -q "health set usage stress -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: mid rate-limit reports alert on the usage key" {
  source "$SCRIPT"
  echo '{"rate_limits":{"five_hour":{"used_percentage":83}}}' | ac_apply >/dev/null
  grep -q "health set usage alert -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: no rate_limits clears the usage key" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":40}}' | ac_apply >/dev/null
  grep -q "health clear usage -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: usage thresholds are independently overridable" {
  source "$SCRIPT"
  FAKE_USAGE_ALERT=50 FAKE_USAGE_STRESS=70   # context stays 80/90
  echo '{"context_window":{"used_percentage":55},"rate_limits":{"five_hour":{"used_percentage":55}}}' | ac_apply >/dev/null
  grep -q "health set usage alert -t %3" "$FAKE_AIRLINE_LOG"   # 55 >= usage alert 50
  grep -q "health clear ctx -t %3"       "$FAKE_AIRLINE_LOG"   # 55 <  context alert 80
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

@test "apply: missing jq passes JSON through and warns once (no health write)" {
  source "$SCRIPT"
  ac_have_jq() { return 1; }                        # simulate jq absent via the seam
  local json='{"context_window":{"used_percentage":95}}'
  # Pipeline subshell inherits the ac_have_jq override; stderr split off to a file.
  out=$(printf '%s' "$json" | ac_apply 2>"${TESTDIR}/err")
  [ "$out" = "$json" ]                              # status line never breaks
  grep -q "jq not found" "${TESTDIR}/err"           # the missing dep is visible
  [ ! -s "$FAKE_AIRLINE_LOG" ]                       # and no health write attempted
}
