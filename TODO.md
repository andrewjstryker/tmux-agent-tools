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

## 4. Airline 3.x compatibility — completed

- [x] Require the public `airline version` contract to be `>= 3.0.0` and `< 4.0.0`
  before an Airline-backed mutation.
- [x] Warn once per tmux server and otherwise no-op for a missing executable, a
  failed or malformed version response, and an incompatible version.
- [x] Test accepted 3.x versions, rejected 2.x and 4.x versions, malformed output,
  command failure, warning suppression, and absence of mutations after rejection.
- [x] Follow Airline's strict health grammar: put `-t <window>` before the keyed
  contributor tuple, attach an opaque diagnostic to every `warn`/`fail`, and use
  the same target ordering for `clear`.

## 5. Signal and problem semantics — completed

- [x] Keep lifecycle on window-scoped `status` and context/usage pressure on
  window-scoped `health`, including `fail` health.
- [x] Follow Airline's pane-identified workflow status API: set only the phase and
  pane target and omit contributor keys, transient policy, revisions, and hooks.
  Airline interprets `result` as transient and owns observation cleanup.
- [x] Use Airline's server-global problem ledger with `-t "$TMUX_PANE"` origin
  claims. Agent performs no pane-to-session resolution; Airline makes active
  problems visible in every initialized session and owns origin cleanup hooks.
- [x] Resolve the globally shared `jq` capability with `problem resolve`; recover
  pane-local input/update claims with `problem set -t ... ok`; reserve
  `problem ack` for user acknowledgement and `problem clear` for destructive
  deletion. Close the pane contributor's claims
  when its Claude telemetry origin ends.
- [x] Treat problem messages as opaque to Airline. Include pane/window context when
  useful to the user.
- [x] Report unavailable advertised telemetry as `fail`. A missing `jq` is a Claude
  telemetry failure only; Codex, lifecycle, and turns do not require it.
- [x] Use contributor `tmux-agent-tools-claude-telemetry` with stable `jq`, `input`,
  and `health-update` keys. Airline's pane-origin claims keep concurrent reporters
  independent under the same logical problem.

## 6. Provider adapters and examples — completed

- [x] Map Claude `UserPromptSubmit`, `PermissionRequest`, `PostToolBatch`, `Stop`,
  and session boundaries to the coarse lifecycle operations. Reset only for
  `startup|clear`; preserve state across resume and compaction. Remove generic
  `Notification` and per-tool `PostToolUse` lifecycle wiring.
- [x] Retain the supported Codex session, prompt, permission, post-tool, stop, and
  session-end mappings, with the same `startup|clear` reset boundary.
- [x] Keep Claude context and usage extraction on `statusLine`.

## 7. Structural review follow-up

- [ ] Use one internal execution model. Prefer sourcing the implementation once in
  `agent.sh` and having provider adapters call lifecycle, turn, and telemetry
  functions directly instead of rediscovering those components as subprocesses.
- [ ] Namespace sourced globals and internal functions by component. Remove generic
  names such as `AGENT_ROOT`, `ADAPTER_DIR`, and `PROJECT_DIR` whose values currently
  depend on source order.
- [ ] Normalize internal vocabulary around the public nouns: `lifecycle`, `turns`,
  and `telemetry`. Replace cryptic `as_*`, `at_*`, and `ac_*` names, update stale
  `agent-state` diagnostics, and remove private `idle`/`reset` aliases where the
  public operation is `clear`.
- [ ] Rename the Claude `context.sh` implementation to reflect that it owns
  telemetry. Keep it as one module while its pipeline remains linear; split input
  parsing, health calculation, and problem reporting only if the module grows or
  those parts need independent reuse.
- [ ] Move generic warn-once behavior out of the Airline boundary. `lib/airline.sh`
  should own Airline discovery, compatibility, and commands, while shared
  diagnostics should have a provider-neutral home.
- [ ] Correct the architecture documentation to state the deliberate facade
  exception: production tmux calls are confined to `lib/tmux.sh`, except that the
  installable `agent` facade reads `@agent-cli` to find the actual CLI.
- [ ] Decide whether crash recovery warrants one public aggregate reset operation.
  Today users can clear lifecycle, turns, and Claude telemetry independently, but
  resetting a broken session completely requires three commands. Any aggregate
  operation must be added deliberately to the settled CLI grammar and tests.
- [ ] Measure the Claude status-line success path before release. It currently
  performs Airline version discovery, `jq`, two health mutations, and three problem
  recovery operations per evaluation. Optimize only if the measured
  process cost is material; Airline idempotence already avoids redundant state and
  redraw changes.

## 8. Completion

- [ ] Update the README, requirements, examples, and release metadata to the final
      CLI and Airline 3.x contract.
- [ ] Run `make release-check AIRLINE_SOURCE=/path/to/tmux-airline/airline.sh`.
      The portable suite and shellcheck establish Agent behavior; the release-only
      smoke additionally passes Agent's exact health/problem vectors through the
      selected Airline source parser without starting tmux or mutating Airline state.
