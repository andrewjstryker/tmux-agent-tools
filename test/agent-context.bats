#!/usr/bin/env bats
# Tests for scripts/agent-context.sh.
#
# ac_tier and ac_extract_pct are pure. ac_apply drives the airline CLI; its
# calls are checked against a fake `airline` on PATH (pointed at via
# $AIRLINE_BIN) that logs its arguments. A fake `tmux` answers `show` (threshold
# options) and absorbs refresh-client. $TMUX/$TMUX_PANE are set so ac_apply
# proceeds (unset in the no-op test).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/agent-context.sh"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agctx.XXXXXX")"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  export FAKE_AIRLINE_LOG="${TESTDIR}/airline.log"
  export FAKE_ALERT=80 FAKE_STRESS=90    # what the fake `tmux show` returns
  : > "$FAKE_TMUX_LOG"; : > "$FAKE_AIRLINE_LOG"
  cat > "${FAKE_BIN}/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
case "$*" in
  *@agent-context-alert*)  printf '%s' "${FAKE_ALERT}" ;;
  *@agent-context-stress*) printf '%s' "${FAKE_STRESS}" ;;
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

@test "apply: passes the JSON through unchanged on stdout" {
  source "$SCRIPT"
  local json='{"context_window":{"used_percentage":95},"model":{"display_name":"x"}}'
  run bash -c "printf '%s' '$json' | { source '$SCRIPT'; ac_apply; }"
  [ "$output" = "$json" ]
}

@test "apply: refreshes the client" {
  source "$SCRIPT"
  echo '{"context_window":{"used_percentage":95}}' | ac_apply >/dev/null
  grep -q "refresh-client -S" "$FAKE_TMUX_LOG"
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

@test "apply: missing airline still passes JSON through (silent no-op)" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset AIRLINE_BIN   # no airline anywhere
  local json='{"context_window":{"used_percentage":95}}'
  run bash -c "printf '%s' '$json' | { source '$SCRIPT'; ac_apply; }"
  [ "$output" = "$json" ]
  [ ! -s "$FAKE_AIRLINE_LOG" ]
}
