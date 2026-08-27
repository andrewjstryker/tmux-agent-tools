# Airline integration follow-up

This note records the remaining work after tmux-airline 2.1 establishes its
contributor contract. It is intentionally an agent-tools worklist, not a request
for additional Airline scope.

## Compatibility

- Require a compatible 2.1 contract from `airline version` before invoking
  Airline-backed operations. Resolve the executable through `@airline-cli`; that
  option remains only the bootstrap needed to reach Airline's public interface.
- Keep missing or incompatible Airline behavior quiet enough for provider hooks:
  report the configuration failure once and otherwise no-op.

## Problem semantics

- Remove the proposed pane-targeted `problem ... -t <pane>` calls and the linked-
  session projection assumption.
- Airline problems are explicitly session-scoped. A problem means Airline or one
  of its contributors cannot provide an advertised capability; it is not agent
  lifecycle, window attention, pane attention, or resource pressure.
- When an adapter itself cannot work as advertised (for example, a required parser
  is unavailable or valid provider input cannot be interpreted), determine the
  canonical session in agent-tools and call the existing public contract:

      airline problem set <session> <key> <warn|fail> <message>
      airline problem clear <session> <key>

  Do not ask Airline to infer session ownership from a pane, and do not propagate a
  problem through sessions that happen to link the same window.
- Continue reporting ordinary context and usage pressure through window-scoped
  `health`; those values do not become problems merely because they are severe.

## Provider hooks

- Review each provider event against the coarse lifecycle transitions: working,
  needs input, and done. Do not wire a per-tool event unless it represents a real
  transition that another event does not already cover.
- For Claude, evaluate `PostToolBatch` instead of `PostToolUse` if a post-tool
  recovery transition is still required. `UserPromptSubmit` already establishes
  working at the start of a turn.
- Keep Claude context and usage reporting on `statusLine`, because that is where
  Claude supplies the required measurements. Repeated unchanged reports are safe:
  Airline 2.1 compares the transaction workspace with its baseline, flushes only
  changed options, and redraws only when the reduced visible value changes.
- Verify Codex event availability against the supported Codex hook surface before
  shipping the checked-in example; do not assume Claude's hook vocabulary.

## Completion

- Update adapters, examples, README requirements, and tests together.
- Test compatible, missing, and incompatible Airline installations.
- Test provider event mappings without adding buffering, a resident process, or
  adapter-owned copies of Airline state.
