#!/usr/bin/env bats
# The installable facade discovers the movable plugin CLI through tmux.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agfacade.XXXXXX")"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
  FAKE_BIN="$TESTDIR/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="$TESTDIR/tmux.log"
  export FACADE_ARGV_LOG="$TESTDIR/argv.log"
  : > "$FAKE_TMUX_LOG"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-tmux" "$FAKE_BIN/tmux"
  PATH="$FAKE_BIN:$PATH"
  unset FAKE_AGENT_CLI
}

teardown() {
  [[ -n "${TESTDIR:-}" ]] && rm -rf "$TESTDIR"
}

make_delegate() {
  local delegate="$TESTDIR/real agent.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\0'\'' "$@" > "$FACADE_ARGV_LOG"' > "$delegate"
  chmod +x "$delegate"
  export FAKE_AGENT_CLI="$delegate"
}

@test "facade resolves the published CLI and preserves its argument vector" {
  make_delegate

  "$ROOT/agent" hook claude "Event With Spaces"

  mapfile -d '' -t argv < "$FACADE_ARGV_LOG"
  [[ "${#argv[@]}" -eq 3 ]]
  [[ "${argv[0]}" == hook ]]
  [[ "${argv[1]}" == claude ]]
  [[ "${argv[2]}" == "Event With Spaces" ]]
  grep -qx 'show-options -gqv @agent-cli' "$FAKE_TMUX_LOG"
}

@test "facade explains when Agent has not been initialized" {
  run "$ROOT/agent" help
  [[ "$status" -eq 1 ]]
  [[ "$output" == \
    "agent: tmux-agent-tools is not initialized; start or reload tmux first" ]]
}

@test "facade rejects a stale published CLI path" {
  export FAKE_AGENT_CLI="$TESTDIR/does-not-exist"

  run "$ROOT/agent" help
  [[ "$status" -eq 1 ]]
  [[ "$output" == \
    "agent: configured CLI is not executable: $TESTDIR/does-not-exist" ]]
}
