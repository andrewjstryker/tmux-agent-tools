#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agarch.XXXXXX")"
}

teardown() {
  [[ -z "${TESTDIR:-}" ]] || rm -rf "$TESTDIR"
}

@test "production code respects the tmux and Airline boundaries" {
  run "$ROOT/test/lint-architecture.sh"
  [ "$status" -eq 0 ]
}

@test "architecture check catches direct tmux and Airline access" {
  mkdir -p "$TESTDIR/lib" "$TESTDIR/operations"
  printf '# allowed boundary\ntmux show -gqv @example\n' > "$TESTDIR/lib/tmux.sh"
  printf '# allowed boundary\nagent_tmux_global_get @airline-cli\n' > "$TESTDIR/lib/airline.sh"
  printf '%s\n' \
    'value=$(tmux show -gqv @example)' \
    'cli=$(agent_tmux_global_get @airline-cli)' \
    '"$cli" health set context warn -t %1' > "$TESTDIR/operations/bad.sh"

  run "$ROOT/test/lint-architecture.sh" "$TESTDIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"direct tmux invocation"* ]]
  [[ "$output" == *"Airline discovery"* ]]
  [[ "$output" == *"Airline invocation"* ]]
}
