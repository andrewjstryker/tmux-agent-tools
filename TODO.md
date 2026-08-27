# Release implementation worklist

The target architecture and public contracts are recorded in `DESIGN.md`. This
file tracks the remaining implementation in independently reviewable chunks.
tmux-airline release work is outside this repository's scope.

## 1. Mechanical boundaries and test support

- Add the narrow `lib/tmux.sh` boundary and move every production `tmux` call
  behind it without changing behavior.
- Add `lib/airline.sh` as the only owner of Airline discovery and command
  construction.
- Add deliberately small tmux and Airline test doubles. The Airline fake records
  arguments, reports a configured version, and injects failures; it does not
  reproduce Airline state or behavior.
- Add an architecture check enforcing both boundaries.

## 2. Public CLI

- Add `agent.sh` with the grammar in `DESIGN.md`, deterministic help and version
  leaves, strict argument validation, and single dispatch.
- Keep provider-native event names exact and case-sensitive.
- Test parsing and delegation without requiring tmux.

## 3. Entry points

- Add the installable `agent` facade and its missing/stale CLI diagnostics.
- Replace `agent-tools.tmux` with `agent.tmux`, publishing only `@agent-cli`.
- Add installation, facade, and loader tests.
- Remove all `@agent-tools-*-bin` handles without aliases or fallback reads.

## 4. Airline 3.x compatibility

- Require the public `airline version` contract to be `>= 3.0.0` and `< 4.0.0`
  before an Airline-backed mutation.
- Warn once per tmux server and otherwise no-op for a missing executable, a
  failed or malformed version response, and an incompatible version.
- Test accepted 3.x versions, rejected 2.x and 4.x versions, malformed output,
  command failure, warning suppression, and absence of mutations after rejection.

## 5. Signal and problem semantics

- Keep lifecycle on window-scoped `status` and context/usage pressure on
  window-scoped `health`, including `fail` health.
- Resolve the calling pane to one canonical tmux session before reporting a
  plugin capability problem.
- Use only `airline problem set <session> ...` and `problem clear <session> ...`;
  do not pass a pane target or project through linked sessions.
- Treat problem messages as opaque to Airline. Include pane/window context when
  useful to the user.
- Pane-qualify telemetry problem contributors so one reporter cannot clear
  another reporter's failure.

## 6. Provider adapters and examples

- Map Claude `UserPromptSubmit`, `PermissionRequest`, `PostToolBatch`, `Stop`,
  and session boundaries to the coarse lifecycle operations. Remove generic
  `Notification` and per-tool `PostToolUse` lifecycle wiring.
- Retain the supported Codex session, prompt, permission, post-tool, stop, and
  session-end mappings.
- Keep Claude context and usage extraction on `statusLine`.
- Update both checked-in provider configurations to invoke `@agent-cli`.

## 7. Completion

- Update the README, requirements, examples, and release metadata to the final
  CLI and Airline 3.x contract.
- Run the complete fake-based suite and shellcheck. No real Airline installation
  is required to establish the Agent contract.
