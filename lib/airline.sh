#!/usr/bin/env bash
# airline.sh — discover and validate tmux-airline's public CLI.
# Callers invoke the resolved executable using Airline's public grammar.

AGENT_AIRLINE_VERSION_RANGE='>= 3.0.0 and < 4.0.0'

# Print the major component of a strict, stable SemVer response. Airline's
# release/API version command reports a release version rather than a range or
# decorated product string, so prerelease/build forms are not part of this
# bootstrap contract.
agent_airline_version_major() { # <version>
  local version="$1"
  if [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

agent_airline_executable() { # <resolved-cli>
  if [[ "$1" == */* ]]; then
    [[ -x "$1" ]]
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

# Validate only a CLI published by a running Airline installation.
agent_airline_validate() { # <published-cli>
  local cli="$1" prefix="agent init" version major
  if ! agent_airline_executable "$cli"; then
    agent_warn_once airline "$prefix" \
      "airline CLI is not executable: $cli; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  if ! version=$("$cli" version 2>/dev/null); then
    agent_warn_once airline "$prefix" \
      "airline version command failed; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  if ! major=$(agent_airline_version_major "$version"); then
    agent_warn_once airline "$prefix" \
      "malformed airline version response: $version; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  if [[ "$major" != 3 ]]; then
    agent_warn_once airline "$prefix" \
      "incompatible airline version $version; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  printf '%s' "$cli"
}

# Signal callers share initialization but never use an unpublished or replaced CLI.
agent_airline_resolve() {
  local published
  agent_initialize || return
  published=$(tmux show -gqv @airline-cli 2>/dev/null)
  [[ -n "$published" && "$published" == "$AGENT_AIRLINE_CLI" ]] || return 0
  printf '%s' "$AGENT_AIRLINE_CLI"
}

# vim: ft=bash
