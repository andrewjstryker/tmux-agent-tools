#!/usr/bin/env bats
# Codex hooks run in a shared daemon; resolve the pane of the hook's session.
#
# `ps` and `tmux` are shell functions describing a process tree and pane table:
#   FAKE_PS     "pid ppid comm" lines
#   FAKE_PANES  "pane_id pane_pid cwd" lines
# Bound sessions live in $TESTDIR/bound-<pane>; set -p calls are logged.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agcodexpane.XXXXXX")"
  TMUX_LOG="$TESTDIR/tmux.log"
  : > "$TMUX_LOG"
  export TMUX="/tmp/fake,1,0"
  source "$ROOT/agent.sh"

  ps() { printf '%s\n' "$FAKE_PS"; }
  tmux() {
    local pane pid cwd
    case "$1 ${2:-} ${3:-}" in
      'list-panes -a -F')
        while read -r pane pid cwd; do
          [ -n "$pane" ] || continue
          if [[ "$4" == *pane_pid* ]]; then
            printf '%s %s\n' "$pane" "$pid"
          else
            printf '%s\t%s\t%s\n' "$pane" "$cwd" "$(cat "$TESTDIR/bound-$pane" 2>/dev/null)"
          fi
        done <<< "$FAKE_PANES"
        ;;
      'set -p -t')
        printf '%s\n' "$*" >> "$TMUX_LOG"
        printf '%s' "$6" > "$TESTDIR/bound-$4"
        ;;
      'set '*) printf '%s\n' "$*" >> "$TMUX_LOG" ;;
    esac
  }

  # Daemon (900) and its hook shell (901) hang off init, outside every pane.
  DAEMON_PS="900 1 codex
901 900 sh"
}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

payload() { printf '{"session_id": "%s", "cwd": "%s"}' "$1" "$2"; }

@test "payload fields are read from Codex hook JSON" {
  local json='{"hook_event_name":"Stop","session_id":"01a1-2b","cwd":"/work/a b"}'
  [ "$(agent_codex_payload_field "$json" session_id)" = 01a1-2b ]
  [ "$(agent_codex_payload_field "$json" cwd)" = "/work/a b" ]
  run agent_codex_payload_field "$json" transcript_path
  [ "$status" -ne 0 ]
}

@test "a hook descending from a pane uses that pane" {
  FAKE_PS="$DAEMON_PS
200 100 codex
$$ 200 bash"
  FAKE_PANES="%2 100 /work
%9 300 /work"
  run agent_codex_pane_resolve < <(payload s1 /work)
  [ "$status" -eq 0 ]
  [ "$output" = %2 ]
}

@test "a daemon hook resolves the only Codex pane in the session directory" {
  FAKE_PS="$DAEMON_PS
200 100 codex
400 300 vim"
  FAKE_PANES="%2 100 /work
%9 300 /work"
  run agent_codex_pane_resolve < <(payload s1 /work)
  [ "$status" -eq 0 ]
  [ "$output" = %2 ]
  grep -qx 'set -p -t %2 @agent-tools-codex-session s1' "$TMUX_LOG"
}

@test "a Codex process below a wrapper still marks its pane" {
  FAKE_PS="$DAEMON_PS
200 100 node
201 200 /usr/lib/node_modules/codex/bin/codex"
  FAKE_PANES="%2 100 /work"
  run agent_codex_pane_resolve < <(payload s1 /work)
  [ "$output" = %2 ]
}

@test "a bound session keeps its pane among several Codex panes" {
  FAKE_PS="$DAEMON_PS
200 100 codex
400 300 codex"
  FAKE_PANES="%2 100 /work
%5 300 /work"
  printf s1 > "$TESTDIR/bound-%2"
  printf s2 > "$TESTDIR/bound-%5"
  run agent_codex_pane_resolve < <(payload s2 /work)
  [ "$output" = %5 ]
  [ ! -s "$TMUX_LOG" ]
}

@test "a new session claims the unbound pane beside a bound one" {
  FAKE_PS="$DAEMON_PS
200 100 codex
400 300 codex"
  FAKE_PANES="%2 100 /work
%5 300 /work"
  printf s1 > "$TESTDIR/bound-%2"
  run agent_codex_pane_resolve < <(payload s2 /work)
  [ "$output" = %5 ]
}

@test "a lone Codex pane is rebound when it starts a new session" {
  FAKE_PS="$DAEMON_PS
200 100 codex"
  FAKE_PANES="%2 100 /work"
  printf old > "$TESTDIR/bound-%2"
  run agent_codex_pane_resolve < <(payload new /work)
  [ "$output" = %2 ]
  [ "$(cat "$TESTDIR/bound-%2")" = new ]
}

@test "unbound Codex panes sharing a directory are ambiguous" {
  FAKE_PS="$DAEMON_PS
200 100 codex
400 300 codex"
  FAKE_PANES="%2 100 /work
%5 300 /work"
  run agent_codex_pane_resolve < <(payload s1 /work)
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "Codex panes in other directories are not candidates" {
  FAKE_PS="$DAEMON_PS
200 100 codex"
  FAKE_PANES="%2 100 /elsewhere"
  run agent_codex_pane_resolve < <(payload s1 /work)
  [ "$status" -ne 0 ]
}

@test "no Codex pane resolves nothing" {
  FAKE_PS="$DAEMON_PS"
  FAKE_PANES="%2 100 /work"
  run agent_codex_pane_resolve < <(payload s1 /work)
  [ "$status" -ne 0 ]
}

@test "outside tmux nothing is resolved" {
  unset TMUX
  FAKE_PS="$DAEMON_PS
200 100 codex"
  FAKE_PANES="%2 100 /work"
  run agent_codex_pane_resolve < <(payload s1 /work)
  [ "$status" -ne 0 ]
}

@test "session end releases the pane binding" {
  TMUX_PANE=%2 agent_codex_pane_release
  grep -qx 'set -pu -t %2 @agent-tools-codex-session' "$TMUX_LOG"
}
