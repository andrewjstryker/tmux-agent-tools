#!/usr/bin/env bats
# The TPM entry point publishes exactly one stable executable handle.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agloader.XXXXXX")"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  : > "$FAKE_TMUX_LOG"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-tmux" "${FAKE_BIN}/tmux"
  PATH="${FAKE_BIN}:${PATH}"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

@test "loader publishes only the public Agent CLI" {
  bash "$ROOT/agent.tmux"
  [[ "$(cat "$FAKE_TMUX_LOG")" == "set -g @agent-cli $ROOT/agent.sh" ]]
}

@test "legacy loader and executable handles are absent" {
  [[ ! -e "$ROOT/agent-tools.tmux" ]]
  bash "$ROOT/agent.tmux"
  ! grep -qE '@agent-tools-(state|turns|claude|codex|claude-context)-bin' \
    "$FAKE_TMUX_LOG"
}
