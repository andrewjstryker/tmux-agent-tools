# tmux-agent-tools

Surface Claude Code and Codex activity in
[tmux-airline](https://github.com/andrewjstryker/tmux-airline)—at a glance, even
while you're focused elsewhere.

The plugin has two implementation layers:

- **Library modules** in `lib/` express provider-neutral concepts: lifecycle
  (`working`, `needs-input`, `done`) and a conversation-turn counter.
- **Adapters** in `adapters/<provider>/` translate each agent's native hook events into
  those modules. Claude also has a status-line adapter for provider-specific
  context and usage telemetry.

```text
lib/
  lifecycle.sh             working | needs-input | done | clear
  turns.sh                 bump | reset
adapters/
  claude/hooks.sh          Claude events → library modules
  claude/context.sh        Claude statusLine → health/problem
  codex/hooks.sh           Codex events → library modules
```

| Provider | Lifecycle | Turns | Resource health | Public command |
| -------- | --------- | ----- | --------------- | -------------- |
| Claude Code | yes | yes | context + usage | `agent hook claude` |
| Codex | yes | yes | unavailable from current hook data | `agent hook codex` |

This boundary is intentional: adding an agent means adding an adapter, without
teaching the operational layer a new event vocabulary.

Three independent signals, each matched to the airline channel that fits it:

- **Lifecycle → status badge.** A small glyph before the window name shows which
  window is **working** (`○`), **wants your input** (`◆`), or is **done** (`●`).
  Lifecycle is an *event* signal, so airline's status lane (its left-of-name
  badge stack) is the right treatment.
- **Resource pressure → health gutter.** When a provider exposes context or
  usage pressure, a condition glyph appears in the window's
  **right gutter**, **amber then red**. Both are *meters* (sustained resource
  conditions), so airline's health channel fits. The included Claude Code
  integration reports context-window and usage-limit pressure.
- **Turn counter → a widget you place.** A per-pane count of conversation turns,
  rendered as `<n>⟳` wherever your status line evaluates formats.

The signals coexist on a window: a working window (`○` badge) can also be near its
context limit (red gutter glyph) and show a turn count.

## Lifecycle → status badge

`lib/lifecycle.sh` lights a pane-qualified status contributor via
`airline status set agent-<pane> <level>`. Pane qualification lets multiple
agents share a window without overwriting each other. airline's status channel
has three fixed levels; the plugin picks the *level* and airline owns the glyph:

| State | airline level | Badge | In the window list |
| ----- | ------------- | ----- | ------------------ |
| `working` | `active` | `○` amber | a running system to watch |
| `needs-input` | `attention` | `◆` amber | wants your input |
| `done` | `result` | `●` green | finished well (clears when you view & leave) |
| `idle` / `clear` | — | — | no badge |

`done` is set **`--transient`**, so airline clears the badge once you've focused
the window and moved on — the one transition this plugin can't observe.
`working`/`needs-input` are persistent: the agent's own lifecycle supersedes them
(working → done/needs-input; needs-input → working when you re-engage).

> There's no `error` state: airline's status channel has no critical/red level
> (`result` outranks `active`; there's nothing above `attention`). A run that
> ends badly is still "the agent wants you" — wire it to `needs-input`.

`clear`/`idle` clear only the calling pane's lifecycle contributor. Provider
health is independent and is cleared by that provider's integration.

## Claude Code resource pressure → health

`adapters/claude/context.sh` adapts Claude Code's `statusLine` JSON into two
meters on airline's **health channel**. Each pane contributes its own `ctx-<pane>`
and `usage-<pane>` keys; airline reduces all health contributors to the worst
condition and shows one gutter glyph:

**Context window** (`ctx` key) — how full the context is:

| Context used | airline condition | In the window list |
| ------------ | ---------------- | ------------------ |
| `< 80%` | — (cleared) | clean gutter |
| `≥ 80%` | `warn` (amber) | approaching capacity |
| `≥ 90%` | `fail` (red) | near capacity — needs attention |

**Usage limit** (`usage` key) — the worse of Claude's 5-hour and 7-day rate-limit
windows (Claude.ai Pro/Max only; absent otherwise, which reads as cleared):

| Usage-limit used | airline condition | In the window list |
| ---------------- | ---------------- | ------------------ |
| `< 80%` | — (cleared) | clean gutter |
| `≥ 80%` | `warn` (amber) | approaching your limit |
| `≥ 90%` | `fail` (red) | near your limit |

Each meter has its own **overridable** thresholds:

```tmux
set -g @agent-tools-context-warn  75    # default 80
set -g @agent-tools-context-fail 92    # default 90
set -g @agent-tools-usage-warn    70    # default 80
set -g @agent-tools-usage-fail   85    # default 90
```

Why a meter and not a meter *widget*: Claude already shows context and usage in
the pane — but only when you're focused there, which is exactly when you don't
need tmux to tell you. The one moment they matter across windows is when a window
is *nearing a ceiling*, and that's an operational condition. Airline maps
`warn` to its amber alert color and `fail` to its red stress color.

Both are exposed through Claude Code's **statusLine** command, so the integration
is wired there rather than pretending its payload is a provider-neutral format.

If this adapter cannot work as advertised—for example, jq is missing or Claude
sends malformed JSON—it clears stale health, preserves the status-line pipeline,
and raises `agent-tools-claude-context` as a problem from the calling pane.
Problems are semantically session-scoped: airline owns the tmux topology and
projects that pane origin into every session linking its window. The adapter
does not choose a session or retain its own transition marker; it reports its
current capability on each evaluation, and airline makes identical updates
storage- and redraw-idempotent. Inspect retained diagnostics with
`airline problem show`; the problem clears after recovery.

## Turn counter → a widget you place

There's a clean split:

- **This plugin owns the value.** A provider adapter calls `lib/turns.sh`,
  which keeps a count in the **pane-scoped** option `@agent-tools-turns`.
- **You own the rendering.** The counter is a plain tmux format that references
  `@agent-tools-turns` — a *regular widget you place yourself*. There's no special
  API: it works as an airline segment, with vanilla `status-right`, or anywhere
  a tmux format is evaluated.

Because `@agent-tools-turns` is pane-scoped, tmux resolves it against the **active
pane**, so the widget shows the turn count of the pane you're looking at and is
blank when that pane isn't running an agent.

`turns.sh` maintains the counter:

| Command | Effect |
| ------- | ------ |
| `bump` | increment the active pane's counter (unset → 1) |
| `reset` / `clear` | remove the counter (blank in the status line) |

Neither provider supplies a stable turn count to these hooks, so the plugin
maintains its own—no transcript parsing.

### Placing the widget

Render `@agent-tools-turns` wherever your status line evaluates formats.

**With tmux-airline** — a segment is just a public `@airline-segment-<slot>`
option you set with `set -g`; airline owns the chevrons and the tier background,
you own the slot and the format. There are six slots (`left-out`/`mid`/`in`,
`right-in`/`mid`/`out`):

```sh
# right-side inner slot showing "<n>⟳", blank when there's no counter
set -g @airline-segment-right-in '#{?@agent-tools-turns, #{@agent-tools-turns}⟳,}'
```

The value is a normal tmux format, so the dynamic `#{@agent-tools-turns}` stays live,
and you can style it with airline's theme color options:

```sh
set -g @airline-segment-right-in '#{?@agent-tools-turns,#[fg=#{@airline-emphasized}] #{@agent-tools-turns}⟳,}'
```

Edit the option to change it, `set -gu @airline-segment-right-in` to drop it, or
`airline segment show` to inspect the slots. (A layout is the durable way to own
the whole arrangement; a bare `set -g` is fine for one slot.)

**Without tmux-airline** — append the same format to `status-right` directly:

```sh
set -ga status-right '#{?@agent-tools-turns, #{@agent-tools-turns}⟳,}'
```

The `⟳` is just text in your format — swap it for any glyph you prefer.

## Requirements

- **The next tmux-airline release after 2.0**, providing the `status`, semantic
  `health` (`ok|warn|fail`), and pane-originated `problem` mutation contract.
  Airline owns rendering, linked-session problem projection, transient clearing,
  and `focus-events`; this plugin touches no private airline option. Do not
  release this revision against airline 2.0: its problem target handling does
  not yet provide the linked-session contract. The turn counter itself needs
  only a status line that evaluates tmux formats.
- `tmux` 3.0+. The `done` badge is `--transient`; airline enables `focus-events`
  itself the first time a transient signal is set, so its unfocus-clear works
  with no extra setup here.
- [`jq`](https://jqlang.github.io/jq/) — **only** for the Claude Code health
  integration, which reads Claude's statusLine JSON. Without it the integration
  passes the JSON through unchanged, clears stale health, and reports a
  session-scoped Claude adapter problem. Codex and the provider-neutral
  lifecycle and turn modules need no JSON and no jq.

## Install (TPM)

```tmux
# ~/.tmux.conf — load airline first so its CLI (@airline-cli) is published
# before the library resolves it.
set -g @plugin 'andrewjstryker/tmux-airline'
set -g @plugin 'andrewjstryker/tmux-agent-tools'
run '~/.tmux/plugins/tpm/tpm'
```

At load the plugin publishes one handle, `@agent-cli`, so provider configuration
never hardcodes an installation directory:

```sh
# Provider hooks
"$(tmux show -gqv @agent-cli)" hook claude Notification
"$(tmux show -gqv @agent-cli)" hook codex PermissionRequest

# Provider-neutral commands
"$(tmux show -gqv @agent-cli)" lifecycle set needs-input
"$(tmux show -gqv @agent-cli)" turns bump

# Claude statusLine telemetry
"$(tmux show -gqv @agent-cli)" telemetry claude update
```

`@agent-cli` is the sole executable handle. Agent-owned configuration and state
use the project namespace `@agent-tools-*`.
The former `@agent-state-*`, `@agent-context-*`, `@agent-usage-*`, and
`@agent-turns` names are intentionally not read as compatibility aliases.

To use `agent` interactively, install its small discovery facade somewhere on
your `PATH`:

```sh
make install                 # defaults to ~/.local/bin/agent
# or: make install PREFIX="$HOME"
agent help
```

The facade reads `@agent-cli` from the running tmux server and delegates to the
active plugin checkout. It reports whether Agent has not been initialized or
the published path has become stale.

The lifecycle and telemetry modules reach the `airline` CLI through
**`@airline-cli`**—the absolute path airline publishes at load, which doubles as
the contract for "airline is active." There's no path-guessing, and it's
resolved at call time, not load time.
`AIRLINE_BIN` overrides it for tests or a non-TPM layout.

If an airline-backed operation is invoked without airline resolvable
(misconfigured, or loaded before airline), they print one warning per tmux server
and then no-op — so a missing dependency is visible without failing the hook on
every turn or spamming the statusLine. Wire none of the airline-backed signals
and you'll never see it. (The turn counter needs no airline — it's a plain tmux
option you render yourself.)

## Wiring Claude Code

Merge [`examples/claude-settings.json`](examples/claude-settings.json) into
`~/.claude/settings.json`. Every hook calls the published CLI with the native
event name; the Claude adapter owns the mapping to lifecycle and turn
operations. `SessionStart` and `SessionEnd` also clear Claude telemetry.

For **health** (context + usage), add the Claude adapter as your `statusLine`
command. It reports each condition on airline's health channel and passes the
JSON through unchanged, so it can precede your existing formatter:

```json
{
  "statusLine": {
    "type": "command",
    "command": "cli=\"$(tmux show -gqv @agent-cli 2>/dev/null)\"; if [ -n \"$cli\" ]; then \"$cli\" telemetry claude update; else cat; fi | your-status-line-command"
  }
}
```

If you don't have a status line, drop the pipe (Claude will show the raw JSON, or
append a formatter of your choice). statusLine is singular in Claude Code, so
this *augments* rather than replaces — the passthrough is what lets it coexist
with your existing one.

Outside tmux, all commands are silent no-ops (the statusLine mode still passes
its JSON through), so the wiring is safe in any context.

## Wiring Codex

Install [`examples/codex-hooks.json`](examples/codex-hooks.json) as
`~/.codex/hooks.json`, or merge its `hooks` object into an existing file. Every
hook calls `@agent-cli`; the Codex adapter maps `PermissionRequest` to
`needs-input` and the shared prompt/tool/stop/session events to the same
operations as Claude.

Codex sends JSON on stdin; the adapter deliberately ignores it and emits no
stdout. Use `/hooks` in Codex to review and trust the commands. Current Codex
hook data does not supply the stable context-window and usage percentages needed
for health, so Codex support is lifecycle plus turns—not a hidden partial path.

## Tests

[bats](https://github.com/bats-core/bats-core) under `test/`, plain core bats.
The pure mappings are unit-tested; the CLI/tmux writes are checked against a fake
`airline` / `tmux` on `PATH` (airline selected via `AIRLINE_BIN`) that logs its
arguments.

```bash
make check    # tests + shellcheck
make test     # bats test
make lint     # shellcheck, if installed
```
