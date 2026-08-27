#!/usr/bin/env bats
# Provider adapters translate native event names into the shared operations.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agadapters.XXXXXX")"
  export ADAPTER_LOG="${TESTDIR}/adapter.log"
  : > "$ADAPTER_LOG"

  for name in state turns context; do
    script="${TESTDIR}/$name"
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "$ADAPTER_LOG"\n' "$name" > "$script"
    chmod +x "$script"
  done
  export AGENT_STATE_BIN="${TESTDIR}/state"
  export AGENT_TURNS_BIN="${TESTDIR}/turns"
  export CLAUDE_CONTEXT_BIN="${TESTDIR}/context"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

@test "Claude prompt starts work and increments the turn" {
  "$ROOT/adapters/claude/hooks.sh" UserPromptSubmit
  grep -qx "state working" "$ADAPTER_LOG"
  grep -qx "turns bump" "$ADAPTER_LOG"
}

@test "Claude permission request requests attention" {
  "$ROOT/adapters/claude/hooks.sh" PermissionRequest
  [ "$(cat "$ADAPTER_LOG")" = "state needs-input" ]
}

@test "Claude post-tool batch returns to working" {
  "$ROOT/adapters/claude/hooks.sh" PostToolBatch
  [ "$(cat "$ADAPTER_LOG")" = "state working" ]
}

@test "Claude stop records a completed result" {
  "$ROOT/adapters/claude/hooks.sh" Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done" ]
}

@test "Claude configured session boundaries clear every Claude-owned operation" {
  local event
  for event in SessionStart SessionEnd; do
    : > "$ADAPTER_LOG"
    "$ROOT/adapters/claude/hooks.sh" "$event"
    grep -qx "state clear" "$ADAPTER_LOG"
    grep -qx "turns reset" "$ADAPTER_LOG"
    grep -qx "context clear" "$ADAPTER_LOG"
  done
}

@test "Codex prompt starts work and increments the turn" {
  "$ROOT/adapters/codex/hooks.sh" UserPromptSubmit
  grep -qx "state working" "$ADAPTER_LOG"
  grep -qx "turns bump" "$ADAPTER_LOG"
}

@test "Codex permission request requests attention" {
  "$ROOT/adapters/codex/hooks.sh" PermissionRequest
  [ "$(cat "$ADAPTER_LOG")" = "state needs-input" ]
}

@test "Codex post-tool event returns to working" {
  "$ROOT/adapters/codex/hooks.sh" PostToolUse
  [ "$(cat "$ADAPTER_LOG")" = "state working" ]
}

@test "Codex stop records a completed result" {
  "$ROOT/adapters/codex/hooks.sh" Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done" ]
}

@test "Codex configured session boundaries clear shared state without Claude telemetry" {
  local event
  for event in SessionStart SessionEnd; do
    : > "$ADAPTER_LOG"
    "$ROOT/adapters/codex/hooks.sh" "$event"
    grep -qx "state clear" "$ADAPTER_LOG"
    grep -qx "turns reset" "$ADAPTER_LOG"
    ! grep -q "context" "$ADAPTER_LOG"
  done
}

@test "provider adapters reject events from the other provider" {
  run "$ROOT/adapters/codex/hooks.sh" Notification
  [ "$status" -ne 0 ]
  run "$ROOT/adapters/codex/hooks.sh" PostToolBatch
  [ "$status" -ne 0 ]
  run "$ROOT/adapters/claude/hooks.sh" PostToolUse
  [ "$status" -ne 0 ]
  run "$ROOT/adapters/claude/hooks.sh" Notification
  [ "$status" -ne 0 ]
}

@test "checked-in provider configurations are valid JSON and use the public CLI" {
  jq -e . "$ROOT/examples/claude-settings.json" "$ROOT/examples/codex-hooks.json" >/dev/null
  jq -r '.. | objects | .command? // empty' "$ROOT/examples/claude-settings.json" |
    grep -q '"$cli" hook claude'
  jq -r '.. | objects | .command? // empty' "$ROOT/examples/codex-hooks.json" |
    grep -q '"$cli" hook codex'
  grep -q '@agent-cli' "$ROOT/examples/claude-settings.json" "$ROOT/examples/codex-hooks.json"
  ! grep -qE '@agent-tools-(state|turns|claude|codex|claude-context)-bin' \
    "$ROOT/examples/claude-settings.json" "$ROOT/examples/codex-hooks.json"
}

@test "provider configurations reset only for startup or clear" {
  local config matcher
  for config in claude-settings.json codex-hooks.json; do
    run jq -er '.hooks.SessionStart | length == 1 and .[0].matcher == "startup|clear"' \
      "$ROOT/examples/$config"
    [ "$status" -eq 0 ]
    [ "$output" = true ]
    matcher="$(jq -r '.hooks.SessionStart[0].matcher' "$ROOT/examples/$config")"
    [[ startup =~ ^($matcher)$ ]]
    [[ clear =~ ^($matcher)$ ]]
    [[ ! resume =~ ^($matcher)$ ]]
    [[ ! compact =~ ^($matcher)$ ]]
  done
}

@test "Claude configuration uses only the coarse native lifecycle events" {
  run jq -er \
    '.hooks | keys | sort == ["PermissionRequest", "PostToolBatch", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"]' \
    "$ROOT/examples/claude-settings.json"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "Codex configuration retains its supported native lifecycle events" {
  run jq -er \
    '.hooks | keys | sort == ["PermissionRequest", "PostToolUse", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"]' \
    "$ROOT/examples/codex-hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "each configured event is passed unchanged through the public CLI" {
  local provider config event command
  while IFS=$'\t' read -r provider config; do
    while IFS=$'\t' read -r event command; do
      [[ "$command" == *'"$cli" hook '"$provider $event"'; fi' ]]
    done < <(jq -r \
      '.hooks | to_entries[] | .key as $event | .value[].hooks[].command | [$event, .] | @tsv' \
      "$ROOT/examples/$config")
  done <<'CONFIGS'
claude	claude-settings.json
codex	codex-hooks.json
CONFIGS
}
