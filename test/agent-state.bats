#!/usr/bin/env bats
# Tests for scripts/agent-state.sh.
#
# The mapping (as_map) is pure. as_apply drives the airline CLI; its calls are
# checked against a fake `airline` on PATH (pointed at via $AIRLINE_BIN) that
# logs its arguments. A fake `tmux` absorbs the refresh-client call. $TMUX/
# $TMUX_PANE are set so as_apply proceeds (and unset in the no-op test).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/agent-state.sh"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agst.XXXXXX")"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  export FAKE_AIRLINE_LOG="${TESTDIR}/airline.log"
  : > "$FAKE_TMUX_LOG"; : > "$FAKE_AIRLINE_LOG"
  cat > "${FAKE_BIN}/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
# Emulate `tmux show -gqv @agent-tools-airline-warned` returning the warn flag.
case "$*" in
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

# --- mapping ---

@test "map: working -> active" {
  source "$SCRIPT"; run as_map working; [ "$output" = "active" ]
}

@test "map: needs-input -> attention" {
  source "$SCRIPT"; run as_map needs-input; [ "$output" = "attention" ]
}

@test "map: done -> result, transient" {
  source "$SCRIPT"; run as_map done; [ "$output" = "result 1" ]
}

@test "map: idle and clear -> empty" {
  source "$SCRIPT"
  run as_map idle;  [ -z "$output" ]
  run as_map clear; [ -z "$output" ]
}

@test "map: error is no longer a state (status has no critical level)" {
  source "$SCRIPT"; run as_map error; [ "$status" -ne 0 ]
}

@test "map: unknown state fails" {
  source "$SCRIPT"; run as_map bogus; [ "$status" -ne 0 ]
}

# --- applying via the airline CLI ---

@test "apply: needs-input lights the agent lane attention (sticky)" {
  source "$SCRIPT"; as_apply needs-input
  grep -q "status set agent-3 attention -t %3" "$FAKE_AIRLINE_LOG"
  ! grep -q -- "--transient" "$FAKE_AIRLINE_LOG"
}

@test "apply: working lights the agent lane active" {
  source "$SCRIPT"; as_apply working
  grep -q "status set agent-3 active -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: done lights the agent lane result and marks it transient" {
  source "$SCRIPT"; as_apply done
  grep -q "status set agent-3 result --transient -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: clear clears the agent lane" {
  source "$SCRIPT"; as_apply clear
  grep -q "status clear agent-3 -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: clear does not clear independent provider health" {
  source "$SCRIPT"; as_apply clear
  ! grep -q "health clear" "$FAKE_AIRLINE_LOG"
}

@test "key: contributor is qualified by the calling pane" {
  source "$SCRIPT"
  TMUX_PANE=%9
  [ "$(as_key)" = "agent-9" ]
}

@test "apply: does not refresh the client itself (airline owns the redraw)" {
  source "$SCRIPT"; as_apply needs-input
  ! grep -q "refresh-client" "$FAKE_TMUX_LOG"
}

@test "apply: no-op outside tmux" {
  source "$SCRIPT"
  unset TMUX TMUX_PANE
  as_apply needs-input
  [ ! -s "$FAKE_AIRLINE_LOG" ]
  [ ! -s "$FAKE_TMUX_LOG" ]
}

@test "apply: missing airline warns and no-ops (does not fail the hook)" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset AIRLINE_BIN   # no airline anywhere
  run as_apply working
  [ "$status" -eq 0 ]                              # warn, not die
  [[ "$output" == *"airline CLI not found"* ]]
  [ ! -s "$FAKE_AIRLINE_LOG" ]
}

@test "apply: missing-airline warning is suppressed once already warned" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset AIRLINE_BIN
  export FAKE_WARNED=1                             # flag already set this server
  run as_apply working
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                 # silent the second time
}

# --- entry point ---

@test "main: unknown state errors" {
  run bash "$SCRIPT" bogus
  [ "$status" -ne 0 ]
}

@test "main: requires exactly one argument" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
