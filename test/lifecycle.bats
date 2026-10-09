#!/usr/bin/env bats
# Tests for lib/lifecycle.sh.
#
# The mapping (agent_lifecycle_level) is pure. agent_lifecycle_apply drives the airline CLI; its calls are
# checked against a fake `airline` on PATH (pointed at via $FAKE_AIRLINE_CLI) that
# logs its arguments. A fake `tmux` absorbs the refresh-client call. $TMUX/
# $TMUX_PANE are set so agent_lifecycle_apply proceeds (and unset in the no-op test).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../agent.sh"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agst.XXXXXX")"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  export FAKE_AIRLINE_LOG="${TESTDIR}/airline.log"
  : > "$FAKE_TMUX_LOG"; : > "$FAKE_AIRLINE_LOG"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-tmux" "${FAKE_BIN}/tmux"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-airline" "${FAKE_BIN}/airline"
  PATH="${FAKE_BIN}:${PATH}"
  export FAKE_AIRLINE_CLI="${FAKE_BIN}/airline"
  export TMUX="/tmp/fake,1,0"
  export TMUX_PANE="%3"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

# --- mapping ---

@test "map: working -> active" {
  source "$SCRIPT"; run agent_lifecycle_level working; [ "$output" = "active" ]
}

@test "map: needs-input -> attention" {
  source "$SCRIPT"; run agent_lifecycle_level needs-input; [ "$output" = "attention" ]
}

@test "map: done -> result" {
  source "$SCRIPT"; run agent_lifecycle_level done; [ "$output" = "result" ]
}

@test "map: clear -> empty" {
  source "$SCRIPT"
  run agent_lifecycle_level clear; [ -z "$output" ]
}

@test "map: error is no longer a state (status has no critical level)" {
  source "$SCRIPT"; run agent_lifecycle_level error; [ "$status" -ne 0 ]
}

@test "map: unknown state fails" {
  source "$SCRIPT"; run agent_lifecycle_level bogus; [ "$status" -ne 0 ]
}

# --- applying via the airline CLI ---

@test "apply: needs-input sets the pane workflow to attention" {
  source "$SCRIPT"; agent_lifecycle_apply needs-input
  grep -q "status set -t %3 attention" "$FAKE_AIRLINE_LOG"
}

@test "apply: working sets the pane workflow to active" {
  source "$SCRIPT"; agent_lifecycle_apply working
  grep -q "status set -t %3 active" "$FAKE_AIRLINE_LOG"
}

@test "apply: done sets the pane workflow to result" {
  source "$SCRIPT"; agent_lifecycle_apply done
  grep -q "status set -t %3 result" "$FAKE_AIRLINE_LOG"
  ! grep -q "set-hook\|status clear" "$FAKE_TMUX_LOG"
}

@test "apply: clear clears the pane workflow" {
  source "$SCRIPT"; agent_lifecycle_apply clear
  grep -q "status clear -t %3" "$FAKE_AIRLINE_LOG"
}

@test "apply: clear does not clear independent provider health" {
  source "$SCRIPT"; agent_lifecycle_apply clear
  ! grep -q "health clear" "$FAKE_AIRLINE_LOG"
}

@test "apply: does not refresh the client itself (airline owns the redraw)" {
  source "$SCRIPT"; agent_lifecycle_apply needs-input
  ! grep -q "refresh-client" "$FAKE_TMUX_LOG"
}

@test "apply: no-op outside tmux" {
  source "$SCRIPT"
  unset TMUX TMUX_PANE
  agent_lifecycle_apply needs-input
  [ ! -s "$FAKE_AIRLINE_LOG" ]
  [ ! -s "$FAKE_TMUX_LOG" ]
}

@test "apply: missing airline completes initialization without signals" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset FAKE_AIRLINE_CLI   # no airline anywhere
  run agent_lifecycle_apply working
  [ "$status" -eq 0 ]                              # warn, not die
  [[ -z "$output" ]]
  [ ! -s "$FAKE_AIRLINE_LOG" ]
}

@test "apply: missing-airline warning is suppressed once already warned" {
  source "$SCRIPT"
  rm -f "${FAKE_BIN}/airline"; unset FAKE_AIRLINE_CLI
  export FAKE_WARNED=1                             # flag already set this server
  run agent_lifecycle_apply working
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                 # silent the second time
}

# --- entry point ---

@test "main: unknown state errors" {
  run bash "$SCRIPT" lifecycle set bogus
  [ "$status" -ne 0 ]
}

@test "main: requires exactly one argument" {
  run bash "$SCRIPT" lifecycle set
  [ "$status" -ne 0 ]
}
