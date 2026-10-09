#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TESTDIR=$(mktemp -d "${BATS_TMPDIR:-/tmp}/agent-init.XXXXXX")
  mkdir -p "$TESTDIR/bin"
  ln -s "$ROOT/test/support/fake-tmux" "$TESTDIR/bin/tmux"
  export PATH="$TESTDIR/bin:$PATH"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/state"
  export FAKE_TMUX_LOG="$TESTDIR/tmux.log"
  export FAKE_AIRLINE_LOG="$TESTDIR/airline.log"
  export FAKE_AIRLINE_CLI="$ROOT/test/support/fake-airline"
  export TMUX='/tmp/fake,1,0' TMUX_PANE=%3
  unset FAKE_SESSION FAKE_AIRLINE_FAIL FAKE_AIRLINE_VERSION AIRLINE_BIN
  : > "$FAKE_AIRLINE_LOG"
  : > "$FAKE_TMUX_LOG"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "separate invocations check and register once per session" {
  "$ROOT/agent.sh" lifecycle set working
  "$ROOT/agent.sh" lifecycle set done
  "$ROOT/agent.sh" turns bump
  [[ "$(grep -c '^version$' "$FAKE_AIRLINE_LOG")" -eq 1 ]]
  [[ "$(grep -c '^widget register ' "$FAKE_AIRLINE_LOG")" -eq 1 ]]
  [[ "$(tmux show -qv -t '$0' @agent-tools-init)" == 1 ]]
}

@test "explicit init resets the marker and repeats initialization" {
  "$ROOT/agent.sh" turns bump
  "$ROOT/agent.sh" init
  "$ROOT/agent.sh" lifecycle set working
  [[ "$(grep -c '^version$' "$FAKE_AIRLINE_LOG")" -eq 2 ]]
  [[ "$(grep -c '^widget register ' "$FAKE_AIRLINE_LOG")" -eq 2 ]]
}

@test "absent Airline is a completed attempt and executable overrides cannot start it" {
  unset FAKE_AIRLINE_CLI
  export AIRLINE_BIN="$ROOT/test/support/fake-airline"
  run "$ROOT/agent.sh" turns bump
  [[ "$status" -eq 0 && -z "$output" ]]
  [[ "$(tmux show -qv -t '$0' @agent-tools-init)" == 1 ]]
  grep -q 'set -p -t %3 @agent-tools-turns 1' "$FAKE_TMUX_LOG"
  [[ ! -s "$FAKE_AIRLINE_LOG" ]]
  export FAKE_AIRLINE_CLI="$AIRLINE_BIN"
  "$ROOT/agent.sh" lifecycle set working
  [[ ! -s "$FAKE_AIRLINE_LOG" ]]
  "$ROOT/agent.sh" init
  "$ROOT/agent.sh" lifecycle set working
  grep -qx 'status set -t %3 active' "$FAKE_AIRLINE_LOG"
}

@test "unpublishing Airline prevents calls even after successful initialization" {
  "$ROOT/agent.sh" init
  : > "$FAKE_AIRLINE_LOG"
  unset FAKE_AIRLINE_CLI
  "$ROOT/agent.sh" lifecycle set working
  [[ ! -s "$FAKE_AIRLINE_LOG" ]]
}

@test "each session initializes its own widget registration" {
  "$ROOT/agent.sh" turns bump
  export FAKE_SESSION='$1'
  "$ROOT/agent.sh" turns bump
  "$ROOT/agent.sh" lifecycle set working
  [[ "$(grep -c '^widget register ' "$FAKE_AIRLINE_LOG")" -eq 2 ]]
  [[ "$(tmux show -qv -t '$0' @agent-tools-init)" == 1 ]]
  [[ "$(tmux show -qv -t '$1' @agent-tools-init)" == 1 ]]
}

@test "registration failure completes the attempt and explicit init retries" {
  export FAKE_AIRLINE_FAIL='widget register'
  run "$ROOT/agent.sh" init
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'widget registration failed'* ]]
  [[ "$(tmux show -qv -t '$0' @agent-tools-init)" == 1 ]]
  "$ROOT/agent.sh" lifecycle set working
  [[ "$(grep -c '^widget register ' "$FAKE_AIRLINE_LOG")" -eq 1 ]]
  unset FAKE_AIRLINE_FAIL
  "$ROOT/agent.sh" init
  [[ "$(grep -c '^widget register ' "$FAKE_AIRLINE_LOG")" -eq 2 ]]
}

@test "help version and malformed init do not initialize" {
  "$ROOT/agent.sh" help init
  "$ROOT/agent.sh" version
  run "$ROOT/agent.sh" init extra
  [[ "$status" -eq 2 ]]
  [[ ! -s "$FAKE_TMUX_LOG" && ! -s "$FAKE_AIRLINE_LOG" ]]
}

@test "loader reload resets the current session initialization" {
  bash "$ROOT/agent.tmux"
  bash "$ROOT/agent.tmux"
  [[ "$(grep -c '^version$' "$FAKE_AIRLINE_LOG")" -eq 2 ]]
}
