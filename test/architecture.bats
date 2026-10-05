#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agarch.XXXXXX")"
}

teardown() {
  [[ -z "${TESTDIR:-}" ]] || rm -rf "$TESTDIR"
}

@test "production code respects the tmux access and Airline discovery boundaries" {
  run "$ROOT/test/lint-architecture.sh"
  [ "$status" -eq 0 ]
}

@test "architecture check catches direct tmux access and duplicated Airline discovery" {
  mkdir -p "$TESTDIR/lib" "$TESTDIR/operations"
  printf '# allowed boundary\ntmux show -gqv @example\n' > "$TESTDIR/lib/tmux.sh"
  printf '# allowed boundary\nagent_tmux_global_get @airline-cli\n' > "$TESTDIR/lib/airline.sh"
  printf 'tmux kill-server\n' > "$TESTDIR/agent"
  printf '%s\n' \
    'value=$(tmux show -gqv @example)' \
    'cli=$(agent_tmux_global_get @airline-cli)' > "$TESTDIR/operations/bad.sh"

  run "$ROOT/test/lint-architecture.sh" "$TESTDIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"direct tmux invocation"* ]]
  [[ "$output" == *"Airline discovery"* ]]
}

@test "architecture check allows callers to use Airline's public CLI" {
  mkdir -p "$TESTDIR/adapters/claude"
  printf '%s\n' \
    'cli=$(agent_airline_resolve)' \
    '"$cli" health set -t "$TMUX_PANE" example context warn "80% used"' \
    '"$cli" problem set -t "$TMUX_PANE" example input ok' \
    > "$TESTDIR/adapters/claude/telemetry.sh"

  run "$ROOT/test/lint-architecture.sh" "$TESTDIR"
  [ "$status" -eq 0 ]
}
