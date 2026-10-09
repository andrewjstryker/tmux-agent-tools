#!/usr/bin/env bats
# Tests for lib/turns.sh.
#
# agent_turns_next is pure. agent_turns_apply's tmux writes are checked against a fake `tmux` on
# PATH that logs its arguments and can echo a canned `show` value (the current
# counter). $TMUX/$TMUX_PANE are set so agent_turns_apply proceeds (unset in the no-op
# test).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../agent.sh"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agtn.XXXXXX")"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
  FAKE_BIN="${TESTDIR}/bin"
  mkdir -p "$FAKE_BIN"
  export FAKE_TMUX_LOG="${TESTDIR}/tmux.log"
  export FAKE_TMUX_PANE_VALUE_FILE="${TESTDIR}/show"
  : > "$FAKE_TMUX_LOG"
  : > "$FAKE_TMUX_PANE_VALUE_FILE"
  ln -s "${BATS_TEST_DIRNAME}/support/fake-tmux" "${FAKE_BIN}/tmux"
  PATH="${FAKE_BIN}:${PATH}"
  export TMUX="/tmp/fake,1,0"
  export TMUX_PANE="%3"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

# --- pure next-value logic ---

@test "next: empty (no counter yet) starts at 1" {
  source "$SCRIPT"; run agent_turns_next ""; [ "$output" = "1" ]
}

@test "next: increments a numeric value" {
  source "$SCRIPT"; run agent_turns_next 11; [ "$output" = "12" ]
}

@test "next: non-numeric resets to 1" {
  source "$SCRIPT"; run agent_turns_next "garbage"; [ "$output" = "1" ]
}

# --- applying to tmux ---

@test "apply: bump from unset sets the pane counter to 1" {
  source "$SCRIPT"
  printf '' > "$FAKE_TMUX_PANE_VALUE_FILE" # no existing counter
  agent_turns_apply bump
  grep -q "set -p -t %3 @agent-tools-turns 1" "$FAKE_TMUX_LOG"
}

@test "apply: bump increments an existing counter" {
  source "$SCRIPT"
  printf '4\n' > "$FAKE_TMUX_PANE_VALUE_FILE" # current counter is 4
  agent_turns_apply bump
  grep -q "set -p -t %3 @agent-tools-turns 5" "$FAKE_TMUX_LOG"
}

@test "apply: bump reads the counter as a pane option" {
  source "$SCRIPT"
  agent_turns_apply bump
  grep -q "show -pqv -t %3 @agent-tools-turns" "$FAKE_TMUX_LOG"
}

@test "apply: clear unsets the pane counter" {
  source "$SCRIPT"; agent_turns_apply clear
  grep -qE "set -pu -t %3 @agent-tools-turns$" "$FAKE_TMUX_LOG"
}

@test "apply: bump refreshes the client" {
  source "$SCRIPT"; agent_turns_apply bump
  grep -q "refresh-client -S" "$FAKE_TMUX_LOG"
}

@test "apply: unknown command fails" {
  source "$SCRIPT"; run agent_turns_apply bogus; [ "$status" -ne 0 ]
}

@test "apply: no-op outside tmux" {
  source "$SCRIPT"
  unset TMUX TMUX_PANE
  agent_turns_apply bump
  [ ! -s "$FAKE_TMUX_LOG" ]
}

# --- entry point ---

@test "main: unknown command errors" {
  run bash "$SCRIPT" turns bogus
  [ "$status" -ne 0 ]
}

@test "main: requires exactly one argument" {
  run bash "$SCRIPT" turns
  [ "$status" -ne 0 ]
}
