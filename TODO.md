# Remaining work

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
- [ ] Decide whether crash recovery warrants one public aggregate reset operation.
  Today users can clear lifecycle, turns, and Claude telemetry independently, but
  resetting a broken session completely requires three commands. Any aggregate
  operation must be added deliberately to the settled CLI grammar and tests.
- [ ] Measure the Claude status-line success path before release. It currently
  performs Airline version discovery, `jq`, two health mutations, and three problem
  recovery operations per evaluation. Optimize only if the measured
  process cost is material; Airline idempotence already avoids redundant state and
  redraw changes.

- [ ] Add a real tmux/Airline integration check alongside the parser smoke test.
- [ ] Review release metadata and run the release check against the target Airline release.
