#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agbound.XXXXXX")"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
  FAKE_BIN="$TESTDIR/bin"
  mkdir -p "$FAKE_BIN"
  ln -s "$ROOT/test/support/fake-tmux" "$FAKE_BIN/tmux"
  ln -s "$ROOT/test/support/fake-airline" "$FAKE_BIN/airline"
  export PATH="$FAKE_BIN:$PATH"
  export FAKE_TMUX_LOG="$TESTDIR/tmux.log"
  export FAKE_AIRLINE_LOG="$TESTDIR/airline.log"
  export FAKE_AIRLINE_ARGV_LOG="$TESTDIR/airline.argv"
  : > "$FAKE_TMUX_LOG"
  : > "$FAKE_AIRLINE_LOG"
  : > "$FAKE_AIRLINE_ARGV_LOG"

  source "$ROOT/lib/diagnostics.sh"
  source "$ROOT/lib/airline.sh"
}

teardown() {
  [[ -z "${TESTDIR:-}" ]] || rm -rf "$TESTDIR"
}

@test "Airline fake records an exact argument vector and injects failures" {
  local cli="$FAKE_BIN/airline"
  "$cli" status set -t %3 attention

  local -a argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 5 ]
  [ "${argv[1]}" = status ]
  [ "${argv[2]}" = set ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]
  [ "${argv[5]}" = attention ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" status clear -t %3
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 4 ]
  [ "${argv[1]}" = status ]
  [ "${argv[2]}" = clear ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" problem set -t %3 tmux-agent-tools capability fail 'message with spaces'

  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 8 ]
  [ "${argv[1]}" = problem ]
  [ "${argv[2]}" = set ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]
  [ "${argv[5]}" = tmux-agent-tools ]
  [ "${argv[6]}" = capability ]
  [ "${argv[7]}" = fail ]
  [ "${argv[8]}" = 'message with spaces' ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" problem set -t %3 tmux-agent-tools capability ok
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 7 ]
  [ "${argv[1]}" = problem ]
  [ "${argv[2]}" = set ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]
  [ "${argv[5]}" = tmux-agent-tools ]
  [ "${argv[6]}" = capability ]
  [ "${argv[7]}" = ok ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" problem resolve tmux-agent-tools capability
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 4 ]
  [ "${argv[1]}" = problem ]
  [ "${argv[2]}" = resolve ]
  [ "${argv[3]}" = tmux-agent-tools ]
  [ "${argv[4]}" = capability ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" problem close -t %3 tmux-agent-tools
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 5 ]
  [ "${argv[1]}" = problem ]
  [ "${argv[2]}" = close ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]
  [ "${argv[5]}" = tmux-agent-tools ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" health set -t %3 tmux-agent-tools context fail '95% used'
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 8 ]
  [ "${argv[1]}" = health ]
  [ "${argv[2]}" = set ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]
  [ "${argv[5]}" = tmux-agent-tools ]
  [ "${argv[6]}" = context ]
  [ "${argv[7]}" = fail ]
  [ "${argv[8]}" = '95% used' ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" health clear -t %3 tmux-agent-tools context
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 6 ]
  [ "${argv[1]}" = health ]
  [ "${argv[2]}" = clear ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]
  [ "${argv[5]}" = tmux-agent-tools ]
  [ "${argv[6]}" = context ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  "$cli" health set -t %3 tmux-agent-tools context ok
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 7 ]
  [ "${argv[1]}" = health ]
  [ "${argv[2]}" = set ]
  [ "${argv[3]}" = -t ]
  [ "${argv[4]}" = %3 ]
  [ "${argv[5]}" = tmux-agent-tools ]
  [ "${argv[6]}" = context ]
  [ "${argv[7]}" = ok ]

  export FAKE_AIRLINE_FAIL=health
  run "$cli" health set -t %3 tmux-agent-tools context fail '95% used'
  [ "$status" -eq 65 ]
}

@test "Airline fake rejects the obsolete keyed and transient status shapes" {
  local cli="$FAKE_BIN/airline"

  run "$cli" status set agent-3 active -t %3
  [ "$status" -eq 64 ]

  run "$cli" status set result --transient -t %3
  [ "$status" -eq 64 ]

  run "$cli" status clear agent-3 -t %3
  [ "$status" -eq 64 ]

  run "$cli" status set result --print-revision -t %3
  [ "$status" -eq 64 ]
}

@test "Airline fake rejects the obsolete health argument shape" {
  local cli="$FAKE_BIN/airline"

  run "$cli" health set context fail -t %3
  [ "$status" -eq 64 ]

  run "$cli" health set -t %3 context warn
  [ "$status" -eq 64 ]

  run "$cli" health clear context -t %3
  [ "$status" -eq 64 ]
}

@test "Airline fake rejects Agent's obsolete session-origin problem shape" {
  local cli="$FAKE_BIN/airline"

  run "$cli" problem set '$7' capability fail 'message'
  [ "$status" -eq 64 ]
}
