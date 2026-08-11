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

@test "map: needs-input -> alert" {
  source "$SCRIPT"; run as_map needs-input; [ "$output" = "alert" ]
}

@test "map: working -> monitor" {
  source "$SCRIPT"; run as_map working; [ "$output" = "monitor" ]
}

@test "map: done -> ok, transient" {
  source "$SCRIPT"; run as_map done; [ "$output" = "ok 1" ]
}

@test "map: error -> stress" {
  source "$SCRIPT"; run as_map error; [ "$output" = "stress" ]
}

@test "map: idle and clear -> empty" {
  source "$SCRIPT"
  run as_map idle;  [ -z "$output" ]
  run as_map clear; [ -z "$output" ]
}

@test "map: unknown state fails" {
  source "$SCRIPT"; run as_map bogus; [ "$status" -ne 0 ]
}

# --- applying via the airline CLI ---

@test "apply: needs-input lights the agent lane alert (sticky)" {
  source "$SCRIPT"; as_apply needs-input
  grep -q "status set agent alert -t %3" "$FAKE_AIRLINE_LOG"
  ! grep -q -- "--transient" "$FAKE_AIRLINE_LOG"
}

@test "apply: working lights the agent lane monitor" {
  source "$SCRIPT"; as_apply working
  grep -q "status set agent monitor -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: done lights the agent lane ok and marks it transient" {
  source "$SCRIPT"; as_apply done
  grep -q "status set agent ok --transient -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: error lights the agent lane stress" {
  source "$SCRIPT"; as_apply error
  grep -q "status set agent stress -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: clear clears the agent lane" {
  source "$SCRIPT"; as_apply clear
  grep -q "status clear agent -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: clear also clears the context health key" {
  source "$SCRIPT"; as_apply clear
  grep -q "health clear ctx -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: refreshes the client" {
  source "$SCRIPT"; as_apply needs-input
  grep -q "refresh-client -S" "$FAKE_TMUX_LOG"
}

@test "apply: no-op outside tmux" {
  source "$SCRIPT"
  unset TMUX TMUX_PANE
  as_apply needs-input
  [ ! -s "$FAKE_AIRLINE_LOG" ]
  [ ! -s "$FAKE_TMUX_LOG" ]
}

@test "apply: errors when airline cannot be found" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset AIRLINE_BIN   # no airline anywhere
  run as_apply working
  [ "$status" -ne 0 ]
  [ ! -s "$FAKE_AIRLINE_LOG" ]
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
