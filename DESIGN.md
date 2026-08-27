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

Provider configuration invokes `@agent-cli`; interactive shell users may invoke
the installed `agent` facade. The current `agent-tools.tmux` entry point and the
`@agent-tools-*-bin` executable options are removed. There are no compatibility
aliases, forwarding commands, or fallback reads. Internal script paths and the
directory layout are not public API.

The public grammar is:

```text
agent version
agent help [<noun>]

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

Agent necessarily uses tmux for its own pane-scoped value and configuration, to
resolve the calling pane's canonical session, and to read the documented
`@airline-cli` bootstrap handle. Those calls are isolated in a small mechanical
`lib/tmux.sh` boundary. This boundary exists to make ownership auditable: no
other production file invokes `tmux`, and its API contains only operations that
Agent legitimately owns or must resolve.

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

Lifecycle is normal operation and uses Airline's window-scoped `status` channel.
Context-window and usage-limit pressure are also normal operation and use the
window-scoped `health` channel, including at `fail` severity. Status and health
direct the user to a window; the pane is expected to contain the operational
information the user needs.

An Airline `problem` has a narrower meaning: Agent cannot provide an advertised
capability. Examples include a missing required parser, provider input that
cannot be interpreted, or a failed health update through an otherwise compatible
Airline CLI. Problems do not represent agent lifecycle, window attention, pane
attention, or resource pressure.

Problem mutations are explicitly session-scoped. Agent resolves the calling
pane to one canonical tmux session and invokes only:

```text
airline problem set <session> <key> <warn|fail> <message>
airline problem clear <session> <key>
```

Agent does not pass a pane target to `problem`, and neither Agent nor Airline
projects the mutation to sessions that happen to link the same window. Airline
assigns no meaning to the message. Agent may include a pane or window identifier
when that helps the user diagnose the failed capability.

Problem contributors must have independent ownership. A successful reporter
must not clear another reporter's failure; pane-local telemetry failures
therefore use pane-qualified keys.

## Provider mapping

Provider adapters translate native events into the coarse lifecycle states
`working`, `needs-input`, and `done`. They do not retain a second copy of Airline
state and do not introduce buffering or a resident process.

Claude uses `UserPromptSubmit` for the start of work, `PermissionRequest` for a
direct request for user input, `PostToolBatch` for recovery to working after a
resolved tool batch, and `Stop` for completion. Session boundaries clear
Claude-owned state. Generic `Notification` and per-tool `PostToolUse` are not
used as lifecycle transitions. Claude context and usage telemetry remains on
its `statusLine` input, where those measurements are supplied.

Codex uses its supported native session, prompt, permission, post-tool, stop,
and session-end events. Provider configurations invoke the shared `agent hook`
surface and do not call internal operations directly.

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
2. Boundary tests cover exact tmux calls, canonical-session resolution, exact
   Airline argument vectors, and injected failures.
3. Compatibility tests cover a missing CLI, accepted 3.x releases, rejected 2.x
   and 4.x releases, malformed output, a failing `version` command, warn-once
   behavior, and absence of mutations after rejection.
4. Telemetry tests cover stdin passthrough, health reporting, capability
   problems, opaque diagnostic messages, recovery, and independent pane-owned
   problem contributors.
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
2. Add `agent.sh` grammar and dispatch tests.
3. Add `agent`, `agent.tmux`, installation behavior, and their tests; remove the
   old executable handles without aliases.
4. Add the Airline 3.x compatibility guard and degraded-installation tests.
5. Correct session-scoped problem reporting and independent contributor
   ownership.
6. Update Claude and Codex mappings and checked-in provider configurations.
7. Update the README and release metadata, then run the complete release check.
