# TDD Two-Phase Development

The orchestrator (main session) owns the TDD cycle, not the develop agent.

## The two phases

1. **Phase 1: `/write-tests` agent** — writes tests from the issue spec. Tests express
   expected behavior. Confirms they FAIL (red baseline). Commits tests to bot branch.
2. **Phase 2: `/develop` agent** — implements code until pre-written tests pass (green).
   Does NOT write new tests.

## Why two agents, not one

When a single develop agent writes tests AND implementation, it tests the implementation
it just wrote — not the spec. That's circular. The test agent writes tests that express
what the behavior SHOULD be, independently of how it's implemented.

## Practical results

First successful use: issue #104 (per-session theme persistence). The test agent wrote 5
intentionally-failing tests. The develop agent made them pass with +10/-2 lines. The tests
defined exactly what to implement — no ambiguity, no scope creep, minimal changes.

## Rules

- For each issue in a cycle: `/write-tests N` first, then `/develop N`
- The write-tests agent reads the issue spec + relevant source, writes tests, confirms red
- The develop agent reads the same issue + the now-failing tests, implements until green
- The develop agent CAN update tests if they're wrong (testing the wrong thing) but should
  not write net-new tests
- Don't use `gh-ops.sh integrate` for test-only PRs — it auto-closes the issue. Use
  `gh-ops.sh pr-merge` instead, then the develop PR closes the issue.

## When to skip Phase 1

- Pure refactors with existing test coverage — existing tests ARE the red baseline
- CSS-only changes — visual verification, not unit-testable
- Script/infrastructure fixes — the gate itself is the test
