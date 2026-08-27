#!/usr/bin/env bash
# Render Agent CLI help from the annotated case arms in agent.sh.

agent_help_records() { # <section>
  local section="$1" line marker active="" found="" closed=""
  local arm_re='^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_-]*)\).*#[|][[:space:]]*(.*)$'

  while IFS= read -r line; do
    marker="${line#"${line%%[![:space:]]*}"}"
    if [[ "$marker" == "# help:begin $section" ]]; then
      [[ -z "$active" && -z "$found" ]] || {
        agent_command_die "duplicate help section: $section"
        return
      }
      active=1
      found=1
      continue
    fi
    if [[ "$marker" == "# help:end $section" ]]; then
      [[ -n "$active" ]] || {
        agent_command_die "unmatched help section end: $section"
        return
      }
      active=""
      closed=1
      continue
    fi
    if [[ -n "$active" && "$line" =~ $arm_re ]]; then
      printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  done < "$AGENT_HELP_SOURCE"

  [[ -n "$found" && -n "$closed" && -z "$active" ]] || {
    agent_command_die "incomplete or missing help section: $section"
    return
  }
}

agent_help_arms() { # <section>
  local records command annotation
  records="$(agent_help_records "$1")" || return
  while IFS=$'\t' read -r command annotation; do
    [[ -n "$command" ]] || continue
    if [[ "$annotation" == "— "* ]]; then
      annotation="${annotation#— }"
      annotation="${annotation^}"
    fi
    printf '  %-11s %s\n' "$command" "$annotation"
  done <<< "$records"
}

agent_help_noun() { # <noun>
  printf '%s:\n' "$1"
  agent_help_arms "$1"
}

agent_help_annotation() { # <noun-or-empty> <command>
  local section="${1:-root}" wanted="$2" records command annotation
  records="$(agent_help_records "$section")" || return
  while IFS=$'\t' read -r command annotation; do
    [[ "$command" == "$wanted" ]] || continue
    printf '%s' "$annotation"
    return 0
  done <<< "$records"
  return 1
}

agent_help_usage() {
  printf 'agent — tmux agent integration CLI\n\n'
  printf 'Usage: agent <noun> <verb> [<argument>...]\n'
  printf '       agent version\n'
  printf '       agent help [<noun> [<verb>]]\n\n'
  printf 'Commands:\n'
  agent_help_arms root || return

  local noun
  for noun in $AGENT_NOUNS; do
    printf '\n'
    agent_help_noun "$noun" || return
  done
}

agent_help_command() { # [<leaf|noun> [<verb>]]
  local first="${1:-}" second="${2:-}" annotation usage description
  [ "$#" -le 2 ] || {
    agent_command_die "help: too many command levels"
    return
  }
  [[ -n "$first" ]] || {
    agent_help_usage
    return
  }

  case " $AGENT_NOUNS " in
    *" $first "*)
      if [[ -z "$second" ]]; then
        printf 'Usage: agent %s <verb>\n\n' "$first"
        agent_help_noun "$first"
        return
      fi
      annotation="$(agent_help_annotation "$first" "$second")" || {
        agent_command_die "help: unknown command '$first $second'"
        return
      }
      ;;
    *)
      [[ -z "$second" ]] || {
        agent_command_die "help: '$first' has no subcommands"
        return
      }
      annotation="$(agent_help_annotation "" "$first")" || {
        agent_command_die "help: unknown command '$first'"
        return
      }
      ;;
  esac

  if [[ "$annotation" == "— "* ]]; then
    usage=""
    description="${annotation#— }"
  elif [[ "$annotation" == *" — "* ]]; then
    usage="${annotation%% — *}"
    description="${annotation#* — }"
  else
    usage=""
    description="$annotation"
  fi

  printf 'Usage: agent %s' "$first"
  [[ -z "$second" ]] || printf ' %s' "$second"
  [[ -z "$usage" ]] || printf ' %s' "$usage"
  printf '\n\n%s\n' "$description"
}
