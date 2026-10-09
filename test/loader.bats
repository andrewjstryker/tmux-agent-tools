#!/usr/bin/env bats
# The TPM entry point publishes exactly one stable executable handle.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agloader.XXXXXX")"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  : > "$FAKE_TMUX_LOG"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-tmux" "${FAKE_BIN}/tmux"
  PATH="${FAKE_BIN}:${PATH}"
  unset FAKE_AIRLINE_CLI
  export FAKE_AIRLINE_LOG="$TESTDIR/airline.log"
  : > "$FAKE_AIRLINE_LOG"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

@test "loader publishes only the public Agent CLI" {
  bash "$ROOT/agent.tmux"
  grep -qx "set -g @agent-cli $ROOT/agent.sh" "$FAKE_TMUX_LOG"
  [[ "$(grep -c '^set -g ' "$FAKE_TMUX_LOG")" -eq 1 ]]
  [[ ! -s "$FAKE_AIRLINE_LOG" ]]
}

@test "legacy loader and executable handles are absent" {
  [[ ! -e "$ROOT/agent-tools.tmux" ]]
  bash "$ROOT/agent.tmux"
  ! grep -qE '@agent-tools-(state|turns|claude|codex|claude-context)-bin' \
    "$FAKE_TMUX_LOG"
}

@test "loader registers the widget catalog with compatible Airline" {
  export FAKE_AIRLINE_CLI="$ROOT/test/support/fake-airline"
  run bash "$ROOT/agent.tmux"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  grep -qx "widget register $ROOT/widgets" "$FAKE_AIRLINE_LOG"
}

@test "loader publishes Agent but skips registration with incompatible Airline" {
  export FAKE_AIRLINE_CLI="$ROOT/test/support/fake-airline"
  export FAKE_AIRLINE_VERSION=4.0.0
  run bash "$ROOT/agent.tmux"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"incompatible airline version"* ]]
  grep -qx "set -g @agent-cli $ROOT/agent.sh" "$FAKE_TMUX_LOG"
  ! grep -q '^widget ' "$FAKE_AIRLINE_LOG"
}
