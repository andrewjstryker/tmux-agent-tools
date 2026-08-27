# Release implementation worklist

The target architecture and public contracts are recorded in `DESIGN.md`. This
file tracks the remaining implementation in independently reviewable chunks.
tmux-airline release work is outside this repository's scope.

## 1. Mechanical boundaries and test support — completed

- [x] Add the narrow `lib/tmux.sh` boundary and move every production `tmux` call
  behind it without changing behavior.
- [x] Add `lib/airline.sh` as the only owner of Airline discovery and command
  construction.
- [x] Add deliberately small tmux and Airline test doubles. The Airline fake records
  arguments, reports a configured version, and injects failures; it does not
  reproduce Airline state or behavior.
- [x] Add an architecture check enforcing both boundaries.

## 2. Public CLI — completed

- [x] Consolidate provider-neutral lifecycle and turn behavior under `lib/`;
  reserve `adapters/` for provider-specific code.
- [x] Add `agent.sh` with the grammar in `DESIGN.md`, full
  `help [<noun> [<verb>]]` inspection, deterministic version reporting, strict
  argument validation, and single dispatch.
- [x] Keep provider-native event names exact and case-sensitive.
- [x] Test parsing and delegation without requiring tmux.

## 3. Entry points — completed

- [x] Add the installable `agent` facade and its missing/stale CLI diagnostics.
- [x] Replace `agent-tools.tmux` with `agent.tmux`, publishing only `@agent-cli`.
- [x] Add installation, facade, and loader tests.
- [x] Remove all `@agent-tools-*-bin` handles without aliases or fallback reads.
- [x] Update checked-in provider configurations to invoke `@agent-cli`.

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
- Report unavailable advertised telemetry as `fail`. A missing `jq` is a Claude
  telemetry failure only; Codex, lifecycle, and turns do not require it.
- Give shared failures stable capability keys so repeated evaluations and panes
  do not duplicate one problem. Pane-qualify only failures owned by one input
  stream so another pane cannot clear them.

## 6. Provider adapters and examples

- Map Claude `UserPromptSubmit`, `PermissionRequest`, `PostToolBatch`, `Stop`,
  and session boundaries to the coarse lifecycle operations. Reset only for
  `startup|clear`; preserve state across resume and compaction. Remove generic
  `Notification` and per-tool `PostToolUse` lifecycle wiring.
- Retain the supported Codex session, prompt, permission, post-tool, stop, and
  session-end mappings, with the same `startup|clear` reset boundary.
- Keep Claude context and usage extraction on `statusLine`.

## 7. Completion

- Update the README, requirements, examples, and release metadata to the final
  CLI and Airline 3.x contract.
- Run the complete fake-based suite and shellcheck. No real Airline installation
  is required to establish the Agent contract.
