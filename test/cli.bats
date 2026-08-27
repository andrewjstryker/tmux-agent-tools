#!/usr/bin/env bats
# The public grammar delegates exactly once and does not require a tmux server.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CLI="$ROOT/agent.sh"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agent-cli.XXXXXX")"
  DISPATCH_LOG="$TESTDIR/dispatch.log"
  : > "$DISPATCH_LOG"
  export DISPATCH_LOG

  # shellcheck source=../agent.sh
  source "$CLI"

  as_apply() { printf 'lifecycle %s\n' "$*" >> "$DISPATCH_LOG"; }
  at_apply() { printf 'turns %s\n' "$*" >> "$DISPATCH_LOG"; }
  ch_apply() { printf 'hook-claude %s\n' "$*" >> "$DISPATCH_LOG"; }
  cx_apply() { printf 'hook-codex %s\n' "$*" >> "$DISPATCH_LOG"; }
  ac_apply() {
    printf 'telemetry-claude update\n' >> "$DISPATCH_LOG"
    cat
  }
  ac_clear() { printf 'telemetry-claude clear\n' >> "$DISPATCH_LOG"; }
}

teardown() {
  [[ -n "${TESTDIR:-}" ]] && rm -rf "$TESTDIR"
}

assert_dispatch() {
  local expected="$1"
  [[ "$(wc -l < "$DISPATCH_LOG")" -eq 1 ]]
  [[ "$(cat "$DISPATCH_LOG")" == "$expected" ]]
}

@test "version comes from the release VERSION file" {
  run "$CLI" version
  [[ "$status" -eq 0 ]]
  [[ "$output" == "3.0.0" ]]
  [[ ! -s "$DISPATCH_LOG" ]]
}

@test "version rejects extra arguments" {
  run agent_main version extra
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"version: takes no arguments"* ]]
}

@test "lifecycle grammar delegates a set or clear exactly once" {
  agent_main lifecycle set needs-input
  assert_dispatch "lifecycle needs-input"

  : > "$DISPATCH_LOG"
  agent_main lifecycle clear
  assert_dispatch "lifecycle clear"
}

@test "turn grammar delegates a bump or clear exactly once" {
  agent_main turns bump
  assert_dispatch "turns bump"

  : > "$DISPATCH_LOG"
  agent_main turns clear
  assert_dispatch "turns clear"
}

@test "hook grammar preserves exact provider event spelling" {
  agent_main hook claude UserPromptSubmit
  assert_dispatch "hook-claude UserPromptSubmit"

  : > "$DISPATCH_LOG"
  agent_main hook codex PermissionRequest
  assert_dispatch "hook-codex PermissionRequest"
}

@test "telemetry grammar delegates update and clear exactly once" {
  run agent_main telemetry claude update <<< '{"context_window":null}'
  [[ "$status" -eq 0 ]]
  [[ "$output" == '{"context_window":null}' ]]
  assert_dispatch "telemetry-claude update"

  : > "$DISPATCH_LOG"
  agent_main telemetry claude clear
  assert_dispatch "telemetry-claude clear"
}

@test "real telemetry update passes stdin through outside tmux" {
  run env -u TMUX -u TMUX_PANE bash -c \
    'printf %s "$1" | "$2" telemetry claude update' _ '{"x":1}' "$CLI"
  [[ "$status" -eq 0 ]]
  [[ "$output" == '{"x":1}' ]]
}

@test "root and noun help are available without tmux" {
  run agent_main help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"lifecycle:"* ]]
  [[ "$output" == *"telemetry:"* ]]

  run agent_main help lifecycle
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: agent lifecycle <verb>"* ]]
  [[ "$output" == *"needs-input"* ]]
}

@test "help supports every noun and verb level in the public grammar" {
  local path
  for path in \
    "lifecycle set" "lifecycle clear" \
    "turns bump" "turns clear" \
    "hook claude" "hook codex" \
    "telemetry claude"; do
    # Intentional split: each path is the two documented help levels.
    # shellcheck disable=SC2086
    run agent_main help $path
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Usage: agent $path"* ]]
  done

  run agent_main help version
  [[ "$status" -eq 0 ]]
  [[ "$output" == "Usage: agent version"* ]]

  run agent_main help help
  [[ "$status" -eq 0 ]]
  [[ "$output" == "Usage: agent help"* ]]
}

@test "empty argv and conventional help flags show root help" {
  run agent_main
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: agent"* ]]

  run agent_main --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: agent"* ]]

  run agent_main -h
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: agent"* ]]
}

@test "unknown command levels fail as usage errors without dispatch" {
  local argv
  for argv in \
    "unknown" \
    "lifecycle unknown" \
    "turns unknown" \
    "hook unknown Stop" \
    "telemetry unknown update" \
    "telemetry claude unknown"; do
    # Intentional split: these are complete invalid argv vectors.
    # shellcheck disable=SC2086
    run agent_main $argv
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"try: agent help"* ]]
    [[ ! -s "$DISPATCH_LOG" ]]
  done
}

@test "missing and extra arguments fail before dispatch" {
  local argv
  for argv in \
    "lifecycle set" \
    "lifecycle set working extra" \
    "lifecycle clear extra" \
    "turns bump extra" \
    "turns clear extra" \
    "hook claude" \
    "hook codex Stop extra" \
    "telemetry claude" \
    "telemetry claude clear extra"; do
    # Intentional split: these are complete invalid argv vectors.
    # shellcheck disable=SC2086
    run agent_main $argv
    [[ "$status" -eq 2 ]]
    [[ ! -s "$DISPATCH_LOG" ]]
  done
}

@test "provider adapters reject wrong-case and foreign native events" {
  run "$CLI" hook claude sessionstart
  [[ "$status" -ne 0 ]]

  run "$CLI" hook claude Notification
  [[ "$status" -ne 0 ]]

  run "$CLI" hook claude PostToolUse
  [[ "$status" -ne 0 ]]

  run "$CLI" hook codex PostToolBatch
  [[ "$status" -ne 0 ]]

  run "$CLI" hook codex notification
  [[ "$status" -ne 0 ]]
}

@test "hook dispatch can execute the installed private modules" {
  run env -u TMUX -u TMUX_PANE "$CLI" hook claude UserPromptSubmit
  [[ "$status" -eq 0 ]]

  run env -u TMUX -u TMUX_PANE "$CLI" hook codex Stop
  [[ "$status" -eq 0 ]]
}

@test "help rejects unknown and over-deep inspection paths" {
  run agent_main help lifecycle unknown
  [[ "$status" -eq 2 ]]

  run agent_main help version extra
  [[ "$status" -eq 2 ]]

  run agent_main help telemetry claude update
  [[ "$status" -eq 2 ]]
}
