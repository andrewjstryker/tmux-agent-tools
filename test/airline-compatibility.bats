#!/usr/bin/env bats
# Agent validates Airline's public release/API version before using its channels.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agcompat.XXXXXX")"
  FAKE_BIN="$TESTDIR/bin"
  mkdir -p "$FAKE_BIN"
  ln -s "$ROOT/test/support/fake-tmux" "$FAKE_BIN/tmux"
  ln -s "$ROOT/test/support/fake-airline" "$FAKE_BIN/airline"
  export PATH="$FAKE_BIN:$PATH"
  export AIRLINE_BIN="$FAKE_BIN/airline"
  export FAKE_TMUX_LOG="$TESTDIR/tmux.log"
  export FAKE_AIRLINE_LOG="$TESTDIR/airline.log"
  export TMUX="/tmp/fake,1,0"
  export TMUX_PANE=%3
  : > "$FAKE_TMUX_LOG"
  : > "$FAKE_AIRLINE_LOG"
  unset FAKE_AIRLINE_VERSION FAKE_AIRLINE_VERSION_FAIL FAKE_WARNED

  # shellcheck source=../lib/lifecycle.sh
  source "$ROOT/lib/lifecycle.sh"
}

teardown() {
  [[ -n "${TESTDIR:-}" ]] && rm -rf "$TESTDIR"
}

assert_no_mutation() {
  ! grep -qE '^(status|health|problem) ' "$FAKE_AIRLINE_LOG"
}

@test "strict release versions expose their major component" {
  run agent_airline_version_major 3.0.0
  [[ "$status" -eq 0 ]]
  [[ "$output" == 3 ]]

  run agent_airline_version_major 12.34.567
  [[ "$status" -eq 0 ]]
  [[ "$output" == 12 ]]
}

@test "accepted 3.x releases are checked before mutation" {
  local version
  for version in 3.0.0 3.1.0 3.999.42; do
    : > "$FAKE_AIRLINE_LOG"
    export FAKE_AIRLINE_VERSION="$version"

    run as_apply working
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
    [[ "$(sed -n '1p' "$FAKE_AIRLINE_LOG")" == version ]]
    grep -qx 'status set agent-3 active -t %3' "$FAKE_AIRLINE_LOG"
  done
}

@test "2.x and 4.x releases warn and do not mutate Airline" {
  local version
  for version in 2.99.99 4.0.0 40.1.2; do
    : > "$FAKE_AIRLINE_LOG"
    export FAKE_AIRLINE_VERSION="$version"

    run as_apply working
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"incompatible airline version $version"* ]]
    [[ "$output" == *">= 3.0.0 and < 4.0.0"* ]]
    [[ "$(cat "$FAKE_AIRLINE_LOG")" == version ]]
    assert_no_mutation
  done
}

@test "malformed version responses warn and do not mutate Airline" {
  local version
  for version in 3.0 v3.0.0 3.00.0 3.0.0-rc.1 garbage; do
    : > "$FAKE_AIRLINE_LOG"
    export FAKE_AIRLINE_VERSION="$version"

    run as_apply working
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"malformed airline version response"* ]]
    [[ "$(cat "$FAKE_AIRLINE_LOG")" == version ]]
    assert_no_mutation
  done
}

@test "a failed version command warns and does not mutate Airline" {
  export FAKE_AIRLINE_VERSION_FAIL=1

  run as_apply working
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"airline version command failed"* ]]
  [[ "$(cat "$FAKE_AIRLINE_LOG")" == version ]]
  assert_no_mutation
}

@test "incompatible Airline preserves Claude telemetry passthrough without mutations" {
  # shellcheck source=../adapters/claude/context.sh
  source "$ROOT/adapters/claude/context.sh"
  export FAKE_AIRLINE_VERSION=4.0.0
  local json='{"context_window":{"used_percentage":95}}'

  out=$(printf '%s' "$json" | ac_apply 2>"$TESTDIR/err")
  [[ "$out" == "$json" ]]
  grep -q 'incompatible airline version 4.0.0' "$TESTDIR/err"
  [[ "$(cat "$FAKE_AIRLINE_LOG")" == version ]]
  assert_no_mutation
}

@test "a configured non-executable warns without attempting Airline" {
  export AIRLINE_BIN="$TESTDIR/not-executable"
  printf '#!/bin/sh\n' > "$AIRLINE_BIN"

  run as_apply working
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"airline CLI is not executable: $AIRLINE_BIN"* ]]
  [[ ! -s "$FAKE_AIRLINE_LOG" ]]
}

@test "an installation failure warns only once per tmux server" {
  export FAKE_AIRLINE_VERSION=4.0.0
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"

  run as_apply working
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"incompatible airline version"* ]]

  run as_apply working
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  [[ "$(grep -c '^version$' "$FAKE_AIRLINE_LOG")" -eq 2 ]]
  assert_no_mutation
}

@test "a compatible installation recovers even after a warning" {
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
  export FAKE_AIRLINE_VERSION=4.0.0
  run as_apply working
  [[ "$status" -eq 0 ]]

  export FAKE_AIRLINE_VERSION=3.0.0
  run as_apply working
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  grep -qx 'status set agent-3 active -t %3' "$FAKE_AIRLINE_LOG"
}
