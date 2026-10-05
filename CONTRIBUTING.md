# Contributing

`agent.sh` parses the public CLI and dispatches to `lib/` operations and provider
adapters in `adapters/`. `agent.tmux` publishes its path as `@agent-cli`; the
optional installed `agent` command discovers it through tmux. Run `agent help`
for the command reference and use the [usage guide](docs/usage.md) for setup.

Keep provider event translation in adapters. Shared operations own lifecycle
translation and the pane turn count. Route tmux calls through `lib/tmux.sh`
(the installed discovery facade is the exception), and use `lib/airline.sh`
for shared Airline discovery and version checking. Adapters and lifecycle
operations invoke the resolved Airline executable directly using its public CLI.
Airline owns its signal storage, rendering, and cleanup. The architecture check
enforces tmux access and shared discovery; it permits direct Airline commands.

Run from the checkout with Bats and ShellCheck installed:

```sh
make check
make release-check AIRLINE_SOURCE=../tmux-airline/airline.sh
```

The portable suite uses small tmux and Airline fakes to test Agent behavior and
outbound arguments. The release check also exercises the selected Airline source
parser with storage and tmux operations stubbed out; it is not an end-to-end
integration test. Keep provider examples and their tests in sync when changing
event mappings.
