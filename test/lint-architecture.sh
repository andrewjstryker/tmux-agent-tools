#!/usr/bin/env bash
# Enforce the two mechanical process boundaries recorded in DESIGN.md.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
violations=0
tmux_invocation='(^|[^[:alnum:]_])tmux([[:space:]]|$)'
airline_invocation='"\$[^"[:space:]]+"[[:space:]]+(status|health|problem)([[:space:]]|$)'

while IFS= read -r file; do
  [[ "$file" != test/* ]] || continue
  while IFS=: read -r line_number line; do
    [[ ! "$line" =~ ^[[:space:]]*# ]] || continue

    if [[ "$file" != lib/tmux.sh ]] && [[ "$line" =~ $tmux_invocation ]]; then
      printf '%s:%s: direct tmux invocation bypasses lib/tmux.sh\n' \
        "$file" "$line_number" >&2
      violations=1
    fi

    if [[ "$file" != lib/airline.sh ]]; then
      if [[ "$line" == *'@airline-cli'* || "$line" == *'AIRLINE_BIN'* ]]; then
        printf '%s:%s: Airline discovery bypasses lib/airline.sh\n' \
          "$file" "$line_number" >&2
        violations=1
      fi
      if [[ "$line" =~ $airline_invocation ]]; then
        printf '%s:%s: Airline invocation bypasses lib/airline.sh\n' \
          "$file" "$line_number" >&2
        violations=1
      fi
    fi
  done < <(awk '{ print FNR ":" $0 }' "$ROOT/$file")
done < <(cd "$ROOT" && rg --files -g '*.sh' -g '*.tmux' -g 'agent')

exit "$violations"
