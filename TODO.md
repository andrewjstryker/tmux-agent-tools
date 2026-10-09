# Remaining work

- [ ] Decide whether crash recovery warrants one public aggregate reset operation.
  Today users can clear lifecycle, turns, and Claude telemetry independently, but
  resetting a broken session completely requires three commands. Any aggregate
  operation must be added deliberately to the settled CLI grammar and tests.
- [ ] Measure the Claude status-line success path before release. It currently
  reads cached initialization, runs `jq`, and performs two health mutations and three problem
  recovery operations per evaluation. Optimize only if the measured
  process cost is material; Airline idempotence already avoids redundant state and
  redraw changes.

- [ ] Review release metadata and run the release check against the target Airline release.
