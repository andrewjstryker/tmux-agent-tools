#!/usr/bin/env bash
# pane.sh — find the tmux pane that hosts a Codex session.
#
# Codex runs hooks in its shared app-server daemon, so the hook inherits the
# TMUX_PANE of whichever pane started the daemon, not the pane of the session.
# Trust a pane only when this process descends from it; otherwise match the
# hook's session to a pane running a Codex process.

AGENT_CODEX_SESSION_OPTION="@agent-tools-codex-session"

# Print the string value of a top-level JSON field. Escaped values are skipped
# rather than half-decoded; callers treat an empty value as unknown.
agent_codex_payload_field() { # <payload> <field>
  local pattern="\"$2\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]*)\""
  [[ "$1" =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# Print the pane hosting the session described by the hook payload on stdin.
# Fails when no pane can be identified without guessing.
agent_codex_pane_resolve() {
  local payload='' session cwd pid ppid comm pane path bound ancestor
  local -A parent=() pane_of_pid=()
  local -a codex_pids=() codex_panes=() unbound=() candidates=()

  [ -n "${TMUX:-}" ] || return 1
  # Codex closes stdin after the payload; never wait on a caller that does not.
  [[ -t 0 ]] || IFS= read -r -d '' -t 1 payload || true
  session=$(agent_codex_payload_field "$payload" session_id)
  cwd=$(agent_codex_payload_field "$payload" cwd)

  while read -r pid ppid comm; do
    parent[$pid]=$ppid
    [[ "${comm##*/}" != codex ]] || codex_pids+=("$pid")
  done < <(ps -A -o pid= -o ppid= -o comm= 2>/dev/null)
  while read -r pane pid; do
    pane_of_pid[$pid]=$pane
  done < <(tmux list-panes -a -F '#{pane_id} #{pane_pid}' 2>/dev/null)

  # A hook run directly by the TUI (codex --no-daemon) descends from its pane.
  if ancestor=$(agent_codex_pane_ancestor $$); then
    printf '%s' "$ancestor"
    return 0
  fi

  # Under the daemon, a pane hosts Codex when a codex process descends from it.
  for pid in "${codex_pids[@]}"; do
    pane=$(agent_codex_pane_ancestor "$pid") && codex_panes+=("$pane")
  done
  ((${#codex_panes[@]})) || return 1

  while IFS=$'\t' read -r pane path bound; do
    [[ " ${codex_panes[*]} " == *" $pane "* ]] || continue
    if [[ -n "$session" && "$bound" == "$session" ]]; then
      printf '%s' "$pane"
      return 0
    fi
    [[ -z "$cwd" || "$path" == "$cwd" ]] || continue
    candidates+=("$pane")
    [[ -n "$bound" ]] || unbound+=("$pane")
  done < <(tmux list-panes -a -F "#{pane_id}	#{pane_current_path}	#{$AGENT_CODEX_SESSION_OPTION}" 2>/dev/null)

  # Prefer a pane no session has claimed; a lone candidate may have started a
  # new session (/new, /clear) and is rebound. Several candidates are ambiguous.
  if ((${#unbound[@]} == 1)); then
    pane=${unbound[0]}
  elif ((${#candidates[@]} == 1)); then
    pane=${candidates[0]}
  else
    return 1
  fi
  [ -z "$session" ] || tmux set -p -t "$pane" "$AGENT_CODEX_SESSION_OPTION" "$session" 2>/dev/null
  printf '%s' "$pane"
}

# Print the pane whose process is <pid> or one of its ancestors. Reads the
# parent and pane_of_pid maps of agent_codex_pane_resolve.
agent_codex_pane_ancestor() { # <pid>
  local pid="$1"
  while [[ -n "$pid" && "$pid" != 0 && "$pid" != 1 ]]; do
    if [[ -n "${pane_of_pid[$pid]:-}" ]]; then
      printf '%s' "${pane_of_pid[$pid]}"
      return 0
    fi
    pid=${parent[$pid]:-}
  done
  return 1
}

# Forget the session bound to the calling pane once that session ends.
agent_codex_pane_release() {
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  tmux set -pu -t "$TMUX_PANE" "$AGENT_CODEX_SESSION_OPTION" 2>/dev/null || true
}
