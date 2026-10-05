# tmux-agent-tools design

This document records the agreed design for the next release. It defines the
public command surface, the boundary with tmux-airline, ownership of tmux state,
provider adaptation, and the testing strategy. The implementation may be changed
in reviewable chunks, but each chunk should converge on this contract.

## Entry points and public CLI

The project follows tmux-airline's three-entry-point pattern, using `agent` as
the command name:

- `agent` is the installable POSIX facade. It resolves the active CLI through
  tmux, rejects a missing or stale path clearly, and delegates with `exec`.
- `agent.sh` is the actual Bash CLI. It owns argument parsing, help, version
  reporting, and dispatch into private operations and provider adapters.
- `agent.tmux` is the TPM entry point. It publishes the absolute path to
  `agent.sh` in the global `@agent-cli` option.

Apart from those root entry points and provider-specific files under
`adapters/`, implementation lives under `lib/`. There is no separate
`operations/` layer; lifecycle and turn behavior are private library modules.

Provider configuration invokes `@agent-cli`; interactive shell users may invoke
the installed `agent` facade. The current `agent-tools.tmux` entry point and the
`@agent-tools-*-bin` executable options are removed. There are no compatibility
aliases, forwarding commands, or fallback reads. Internal script paths and the
directory layout are not public API.

The public grammar is:

```text
agent version
agent help [<noun> [<verb>]]

agent lifecycle set <working|needs-input|done>
agent lifecycle clear

agent turns bump
agent turns clear

agent hook claude <event>
agent hook codex <event>

agent telemetry claude update
agent telemetry claude clear
```

Provider event names remain the providers' exact, case-sensitive names. Unknown
providers, events, nouns, verbs, and extra arguments fail with a usage error.
Hook and lifecycle commands produce no standard output. Telemetry `update`
passes its input through unchanged on standard output so it composes with a
Claude status-line formatter. `version` and `help` do not require a running tmux
server.

## Ownership and boundaries

Agent owns:

- provider-neutral lifecycle translation;
- the pane-scoped `@agent-tools-turns` value;
- agent configuration under the `@agent-tools-*` option namespace;
- provider event and payload adaptation;
- detecting and reporting its own inability to provide an advertised
  capability.

Airline owns its public `status`, `health`, and `problem` protocols, their stored
state, reduction, rendering, redraw behavior, and tmux topology. Agent never
reads or writes Airline's private tmux options.

Agent necessarily uses tmux for its own pane-scoped value and configuration and
to read documented bootstrap handles. Plugin-internal calls are isolated in a
small mechanical `lib/tmux.sh`
boundary. The sole exception is the installed `agent` facade: because it cannot
know or source a movable plugin directory, it directly reads only `@agent-cli`.
No other production file invokes `tmux`. This boundary makes ownership
auditable, and its API contains only operations that Agent legitimately owns or
must resolve.

All Airline access is isolated in `lib/airline.sh`. No other production file
reads `@airline-cli`, checks the Airline version, or constructs an Airline
command. `AIRLINE_BIN` remains an explicit test and non-TPM override.

## Airline compatibility

Before an Airline-backed operation, Agent resolves the executable through
`AIRLINE_BIN` or `@airline-cli` and reads the public `airline version` command.
The supported contract is:

```text
>= 3.0.0 and < 4.0.0
```

Missing executables, failed version commands, malformed versions, and versions
outside that range are configuration failures. A provider hook must not fail or
repeatedly emit noise for them: Agent reports the configuration failure once per
tmux server and otherwise performs no Airline-backed mutation.

The compatibility check verifies only the advertised public contract. Agent
does not inspect Airline implementation details or reproduce Airline behavior.

## Signal semantics

Lifecycle is normal operation and uses Airline's pane-identified, window-reduced
`status` channel.
For a completed result, Agent reports only the `result` phase. Airline owns its
transient observation semantics, pane revision counter, hook, and conditional
cleanup. Agent stores no parallel lifecycle or observation state.
Context-window and usage-limit pressure are also normal operation and use the
window-scoped `health` channel, including at `fail` severity. Status and health
direct the user to a window; the pane is expected to contain the operational
information the user needs.

An Airline `problem` has a narrower meaning: Agent cannot provide an advertised
capability. Examples include a missing required parser, provider input that
cannot be interpreted, or a failed health update through an otherwise compatible
Airline CLI. Problems do not represent agent lifecycle, window attention, pane
attention, or resource pressure.

Problems are server-global lifecycle entries. Agent reports each telemetry
assertion with its pane origin and stable contributor identity:

```text
airline problem set -t <pane> <contributor> <key> <warn|fail> <message>
airline problem set -t <pane> <contributor> <key> ok
airline problem resolve <contributor> <key>
airline problem close -t <pane> <contributor>
```

Airline makes active problems visible in every initialized session while retaining
each pane as an independent origin claim. Pane-local recovery uses `set ... ok`.
When Agent verifies that the shared `jq` requirement is restored, `problem resolve`
authoritatively retires every stale origin claim. Neither path uses `problem ack`
or `problem clear`: acknowledgement changes presentation, while clear deletes the
global ledger and its claims. When a Claude telemetry
origin ends, Agent closes its contributor claims so Airline can retain closed
history without leaving them active. Airline assigns no meaning to the diagnostic
message.

The contributor is `tmux-agent-tools-claude-telemetry`; keys `jq`, `input`, and
`health-update` identify its failed capabilities. Airline's origin claims let
multiple panes assert the same logical key independently, so one pane's recovery
cannot clear another pane's claim. Identical reports are idempotent; Agent does not
maintain a separate transition marker.

An advertised telemetry capability that cannot operate is a `fail` problem. This
includes a missing `jq` while Claude telemetry is configured, provider input that
cannot be interpreted, and a failed Airline health mutation through an otherwise
compatible CLI. A validly absent optional measurement is normal operation: the
reporter sets its health contribution to `ok` and no problem is reported. `jq` is not required
for Codex or for provider-neutral lifecycle and turn operations.

## Provider mapping

Provider adapters translate native events into the coarse lifecycle states
`working`, `needs-input`, and `done`. They do not retain a second copy of Airline
state and do not introduce buffering or a resident process.

Claude uses `UserPromptSubmit` for the start of work, `PermissionRequest` for a
direct request for user input, `PostToolBatch` for recovery to working after a
resolved tool batch, and `Stop` for completion. Only a new or explicitly cleared
session (`startup|clear`) resets Claude-owned state; resume and compaction retain
it. Generic `Notification` and per-tool `PostToolUse` are not used as lifecycle
transitions. Claude context and usage telemetry remains on its `statusLine`
input, where those measurements are supplied.

Codex uses its supported native session, prompt, permission, post-tool, stop,
and session-end events. Its session-start reset likewise matches only
`startup|clear`, not resume or compaction. Provider configurations invoke the
shared `agent hook` surface and do not call internal operations directly.

## Testing strategy

The suite tests Agent's behavior and its outbound public contract. It does not
test that Airline works.

`test/support/fake-airline` is a deliberately small executable protocol fake. It
records arguments losslessly, returns a configured value for `version`, and can
return configured failures for selected commands. It does not implement signal
reduction, linked-session behavior, storage, rendering, redraws, transactions,
or validation on Airline's behalf.

The tmux test double records calls and supplies only the option and target values
needed by a test. Stateful cases such as warn-once behavior may use temporary
file-backed option state so separate CLI processes observe one fake tmux server.
No real Airline installation is required, and the normal suite does not require
a real tmux server.

Tests are divided by responsibility:

1. Pure tests cover lifecycle and provider mappings, telemetry extraction and
   thresholds, and version-range parsing.
2. Boundary tests cover exact tmux calls, pane-origin problem reporting, exact
   Airline argument vectors, strict signal tuple validation, and injected failures.
3. Compatibility tests cover a missing CLI, accepted 3.x releases, rejected 2.x
   and 4.x releases, malformed output, a failing `version` command, warn-once
   behavior, and absence of mutations after rejection.
4. Telemetry tests cover stdin passthrough, health reporting, capability
   problems, opaque diagnostic messages, recovery, stable shared-capability
   keys, and independently owned pane-specific contributors.
5. Provider tests cover the checked-in native event mappings and configuration
   JSON.
6. CLI tests cover grammar and single dispatch without tmux; facade and loader
   tests cover missing, stale, and published `@agent-cli` paths with fake tmux.

An architecture test enforces the boundaries: only `lib/tmux.sh` invokes tmux,
only `lib/airline.sh` resolves or invokes Airline, and adapters do not construct
Airline commands.

## Implementation sequence

Implementation proceeds in independently reviewable chunks:

1. Establish test support and the tmux/Airline boundaries while preserving
   existing behavior.
2. Add `agent.sh` grammar, full nested-help inspection, and dispatch tests.
3. Add `agent`, `agent.tmux`, installation behavior, and their tests; remove the
   old executable handles without aliases.
4. Add the Airline 3.x compatibility guard and degraded-installation tests.
5. Correct global problem reporting, pane-origin claims, and contributor ownership.
6. Update Claude and Codex mappings and checked-in provider configurations.
7. Update the README and release metadata, then run the complete release check.
