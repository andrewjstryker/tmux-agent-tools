#!/usr/bin/env bats
# The TPM entry point publishes stable paths under the project namespace.

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

@test "loader publishes every executable under @agent-tools" {
  bash "$ROOT/agent-tools.tmux"
  grep -q "set -g @agent-tools-state-bin $ROOT/operations/lifecycle.sh" "$FAKE_TMUX_LOG"
  grep -q "set -g @agent-tools-turns-bin $ROOT/operations/turns.sh" "$FAKE_TMUX_LOG"
  grep -q "set -g @agent-tools-claude-context-bin $ROOT/adapters/claude/context.sh" "$FAKE_TMUX_LOG"
  grep -q "set -g @agent-tools-claude-bin $ROOT/adapters/claude/hooks.sh" "$FAKE_TMUX_LOG"
  grep -q "set -g @agent-tools-codex-bin $ROOT/adapters/codex/hooks.sh" "$FAKE_TMUX_LOG"
}

@test "loader does not publish legacy @agent names" {
  bash "$ROOT/agent-tools.tmux"
  ! grep -qE 'set -g @agent-(state|turns|context)-' "$FAKE_TMUX_LOG"
}
