#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agbound.XXXXXX")"
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

  source "$ROOT/lib/tmux.sh"
  source "$ROOT/lib/airline.sh"
}

teardown() {
  [[ -z "${TESTDIR:-}" ]] || rm -rf "$TESTDIR"
}

@test "tmux boundary preserves explicit option scopes and pane targets" {
  export FAKE_TMUX_PANE_VALUE=4
  agent_tmux_global_get @example >/dev/null
  agent_tmux_global_set @example value
  agent_tmux_pane_get %3 @agent-tools-turns >/dev/null
  agent_tmux_pane_set %3 @agent-tools-turns 5
  agent_tmux_pane_unset %3 @agent-tools-turns
  export FAKE_TMUX_SESSION='$7'
  session="$(agent_tmux_current_session %3)"
  agent_tmux_refresh_status

  grep -qx 'show -gqv @example' "$FAKE_TMUX_LOG"
  grep -qx 'set -g @example value' "$FAKE_TMUX_LOG"
  grep -qx 'show -pqv -t %3 @agent-tools-turns' "$FAKE_TMUX_LOG"
  grep -qx 'set -p -t %3 @agent-tools-turns 5' "$FAKE_TMUX_LOG"
  grep -qx 'set -pu -t %3 @agent-tools-turns' "$FAKE_TMUX_LOG"
  [ "$session" = '$7' ]
  grep -qx 'display-message -p -t %3 #{session_id}' "$FAKE_TMUX_LOG"
  grep -qx 'refresh-client -S' "$FAKE_TMUX_LOG"
}

@test "Airline discovery honors the override and documented bootstrap option" {
  export AIRLINE_BIN="$FAKE_BIN/airline"
  run agent_airline_discover
  [ "$status" -eq 0 ]
  [ "$output" = "$FAKE_BIN/airline" ]
  [ ! -s "$FAKE_TMUX_LOG" ]

  unset AIRLINE_BIN
  export FAKE_AIRLINE_CLI=/configured/airline
  run agent_airline_discover
  [ "$status" -eq 0 ]
  [ "$output" = /configured/airline ]
  grep -qx 'show -gqv @airline-cli' "$FAKE_TMUX_LOG"
}

@test "Airline fake records an exact argument vector and injects failures" {
  local cli="$FAKE_BIN/airline"
  agent_airline_problem_set \
    "$cli" '$7' capability fail 'message with spaces'

  local -a argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 6 ]
  [ "${argv[1]}" = problem ]
  [ "${argv[2]}" = set ]
  [ "${argv[3]}" = '$7' ]
  [ "${argv[4]}" = capability ]
  [ "${argv[5]}" = fail ]
  [ "${argv[6]}" = 'message with spaces' ]

  : > "$FAKE_AIRLINE_ARGV_LOG"
  agent_airline_problem_clear "$cli" '$7' capability
  argv=()
  mapfile -d '' -t argv < "$FAKE_AIRLINE_ARGV_LOG"
  [ "${argv[0]}" = 4 ]
  [ "${argv[1]}" = problem ]
  [ "${argv[2]}" = clear ]
  [ "${argv[3]}" = '$7' ]
  [ "${argv[4]}" = capability ]

  export FAKE_AIRLINE_FAIL=health
  run agent_airline_health_set "$cli" context fail %3
  [ "$status" -eq 65 ]
}
