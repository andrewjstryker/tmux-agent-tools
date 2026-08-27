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

@test "Claude notification requests attention" {
  "$ROOT/adapters/claude/hooks.sh" Notification
  [ "$(cat "$ADAPTER_LOG")" = "state needs-input" ]
}

@test "Claude stop records a completed result" {
  "$ROOT/adapters/claude/hooks.sh" Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done" ]
}

@test "Claude session boundaries clear every Claude-owned operation" {
  "$ROOT/adapters/claude/hooks.sh" SessionEnd
  grep -qx "state clear" "$ADAPTER_LOG"
  grep -qx "turns reset" "$ADAPTER_LOG"
  grep -qx "context clear" "$ADAPTER_LOG"
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

@test "Codex stop records a completed result" {
  "$ROOT/adapters/codex/hooks.sh" Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done" ]
}

@test "Codex session boundaries clear shared state without Claude telemetry" {
  "$ROOT/adapters/codex/hooks.sh" SessionEnd
  grep -qx "state clear" "$ADAPTER_LOG"
  grep -qx "turns reset" "$ADAPTER_LOG"
  ! grep -q "context" "$ADAPTER_LOG"
}

@test "provider adapters reject events from the other provider" {
  run "$ROOT/adapters/codex/hooks.sh" Notification
  [ "$status" -ne 0 ]
  run "$ROOT/adapters/claude/hooks.sh" PermissionRequest
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
