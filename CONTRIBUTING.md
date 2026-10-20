# Contributing

`agent.sh` loads the implementation once, parses the public CLI, and calls
functions in `lib/` and `adapters/`. These modules define functions and constants;
they do not source dependencies or act as separate executables. Provider adapters
call shared operations directly. Names follow the public concepts: lifecycle,
turns, and telemetry, with `agent_<provider>_…` prefixes for provider functions.

Agent stores its configuration and state in `@agent-tools-*` tmux options.
Call tmux directly for Agent-owned values and Airline's public CLI for signals.
`lib/init.sh` records initialization attempts per session; `lib/airline.sh`
validates the published Airline CLI once during each attempt;
`lib/diagnostics.sh` handles warning suppression. Do not duplicate Airline's
signal state or lifecycle bookkeeping. All invocations are short-lived Bash
processes; jq handles JSON, and tmux owns persistent state and status refresh.

`agent.tmux` publishes `@agent-cli` and registers `widgets/` with Airline when
available. The optional installed `agent` facade discovers the CLI through tmux.
The turn widget is a native tmux format and also works without Airline.
Run `agent help` for commands and see [usage](USAGE.md) for configuration.

Run from the checkout with Bats and ShellCheck installed:

```sh
make check
make release-check AIRLINE_SOURCE=../tmux-airline/airline.sh
```

The portable suite uses small tmux and Airline fakes to test Agent behavior and
outbound arguments. The release check also exercises the selected Airline source
parser with storage and tmux operations stubbed out, then starts an isolated
tmux server to check widget rendering, pane isolation, Airline registration,
layout placement, and a provider hook sequence. Run `make widget-integration`
without `AIRLINE_SOURCE` to check the widget with tmux alone. Keep the provider
plugins under `plugins/` and their tests in sync when changing event mappings.
Validate the Claude plugin and marketplace with `claude plugin validate .`.
Codex reads `.agents/plugins/marketplace.json`; without it, Codex would fall back
to the Claude marketplace and install the Claude hooks.
