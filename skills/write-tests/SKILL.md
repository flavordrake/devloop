---
name: write-tests
description: Use when the user says "write tests", "write tests for X", "add test coverage", "backfill tests", or explicitly "/write-tests N", or after a code change that lacks coverage. Spawns the devloop:test-writer agent (Opus), which writes tests only and does not modify application code.
---

# Write Tests

Spawn `devloop:test-writer` to add coverage. It writes tests only; its principles
and workflow live in the agent.

## Input

- `/write-tests 225`: tests for issue #225's changes
- `/write-tests keybar scroll`: tests for a described behavior
- `/write-tests path/to/file:function`: tests for a specific function
- `/write-tests`: auto-detect gaps from recent history

Auto-detect: source files changed in the last few commits (`git diff HEAD~5 --name-only`)
with no corresponding test-file changes are coverage gaps. Propose the top gaps and
start on the first.

## Spawning

```
Agent(
  subagent_type="devloop:test-writer",
  isolation="worktree",
  run_in_background=true,
  description="Test writer: {target}",
  prompt="Target: {target and context}. Mode: backfill. Branch: bot/test-{slug}."
)
```

Mode is `backfill` here (tests pass against existing behavior). `/spec-develop` and
two-phase `/develop` use mode `red` on `bot/issue-{N}`.

Use this for code that shipped without tests, regression tests after a bug found on
device, or expanding coverage of a specific behavior. `/develop` already writes tests
as part of implementation.

## TRACE

For non-trivial targets (state machines, protocols, complex interactions), record
edge cases chosen and skipped, the failure modes targeted, and the mocking strategy.
Simple backfills need none.
