---
name: develop
description: Use when the user says "develop", "work on issue", "implement issue", "fix issue N", or explicitly "/develop N". Spawns a local develop agent in a worktree to implement one or more GitHub issues. Supports batch mode ("/develop 3,9,16") with max 4 parallel agents. Without arguments, auto-proposes bot-labeled issues ranked by risk and relevance.
---

# Develop

Spawn isolated `devloop:develop` agents to implement GitHub issues.

## Input

- `/develop 16`: single issue, foreground
- `/develop 3,9,16`: batch, background, max 4 parallel, rest queued
- `/develop`: auto-propose

## Auto-propose

Rank open `bot`-labeled issues (via `scripts/develop-propose.sh --max 5` if the repo
has it, else `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh fetch-issues`) by:
- Risk: small single-module scope ranks above multi-module or security-sensitive code
- Theme: relation to recent `git log`
- Freshness: no prior bot attempts ranks higher
- Blockers: `blocked` and `device` labels rank lower

Show `| # | Title | Risk | Score | Reason |`, then start the top unblocked issue
immediately; the user invoked `/develop` to get work done, not to pick from a menu.

## Pre-flight (per issue)

1. Issue exists, is open, and has a body: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh fetch-issues {N}`. No body: ask the user to add scope.
2. Existing branch: `git ls-remote --heads origin 'bot/issue-{N}*'` (`gh-ops.sh search` lists issues, not branches). If one exists, ask: resume on that branch, or skip?
3. Prior failures in `memory/bot-attempts.md`.
4. Files in scope from the issue body; if missing, read likely source files and keep scope narrow.

## Agent prompt

```
Issue #{N}: {title}

## Issue body
{full body}

## Prior failures
{bot-attempts.md section, or "No prior attempts"}

## Prior TRACE context
{for .traces/trace-*issue-{N}*: status, knowledge seed, pivots, ambiguity gap; a summary, not full content. Or "No prior traces."}

## Session learnings
{user corrections and process discoveries from this session relevant to the task}

## Files in scope
{files, with context snippets showing patterns to follow}

## Constraints
- Max 3 cycles; deadline {unix_timestamp, now + 3600}
- Stay in scope; minimal changes; follow existing patterns
```

The phases, done-when criteria, and result format live in the agent.

## Single vs two-phase TDD

| Issue | Approach |
|-------|----------|
| Bug fix with clear repro, small feature, refactor | Single phase: `devloop:develop` writes tests and code |
| Non-obvious edge cases, protocol or state-machine changes | Two phase: `devloop:test-writer` (mode `red`, branch `bot/issue-{N}`, no PR), then `devloop:develop` on the same branch |
| Ambiguous acceptance criteria | `/spec-develop N` |
| Backfill coverage only | `/write-tests` |

## Spawning

```
Agent(
  subagent_type="devloop:develop",
  isolation="worktree",
  run_in_background=<true in batch mode>,
  description="Develop: issue 16",
  prompt="<agent prompt above>"
)
```

Parallel limit: 4. Queue the rest and spawn as slots free.

## Results

Agents print a `DEVELOP_RESULT:` block.

- PASS: report "Issue #{N}: PR {url}, cycles {count}/3." Ensure the `bot` label.
- FAIL or TIMEOUT: append to `memory/bot-attempts.md`:
  ```markdown
  ## Issue #{N}: {title}
  ### Attempt {n} ({date})
  - Branch: bot/issue-{N}
  - Result: FAIL ({failure_type})
  - Cycles: {count}/3, wall clock {elapsed}s
  - Files touched: {files}
  - Summary: {summary}
  - Last error: {last_error}
  ```
  Then `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh labels {N} --add divergence --rm bot` and report the failure.
- No structured output: treat as FAIL, type `unknown`.

Batch mode ends with a table: `| Issue | Result | PR | Cycles | Time |`.
