---
name: delegate
description: Use when the user says "delegate", "assign bot work", "dispatch issues", "triage open issues", "send to bot", or explicitly "/delegate". Scans open issues, classifies which are agent-delegatable, analyzes prior failed attempts, does cross-issue gap analysis, and dispatches approved issues to local devloop:develop agents.
---

# Delegation

Labels, workflow states, gates, and domain labels come from the repo's `AGENTS.md`
(gate tiers per the `gates.md` rule).

Scan open issues, classify delegatability, enrich with direction, and dispatch to local
`devloop:develop` agents. For issues with prior failed attempts, analyze what went wrong,
decompose if needed, and re-delegate with tighter constraints.

Upstream complement to `/integrate`: delegate -> develop -> integrate -> learn -> re-delegate.

**Approval noise = risk.** Scripts are approved once by pattern; composed one-off commands
need per-invocation approval, and speed-reading approvals is how a main repo once got
deleted. Every deterministic step is a script; only analysis and decisions reach the main context.

Run **foreground**. The user approves every delegation before it executes.

If a TRACE is active, follow the agent-trace skill.

## Phase 1: Discover and classify

Spawn `subagent_type: devloop:delegate-scout` in foreground. It runs the repo's
discovery/classification scripts (e.g. `delegate-discover.sh`, `delegate-classify.sh`,
`delegate-failure-analysis.sh`) and returns a summary with file paths. Classes:

- **delegate** -- clear scope, agent-ready, no prior attempts
- **already-attempted** -- has bot branches, needs failure analysis before re-delegation
- **decompose** -- too large or vague for one pass
- **human-only** -- device/hardware validation, research, UX judgment
- **blocked** -- depends on an unresolved issue
- **icebox** -- labeled `icebox`, skip entirely
- **close** -- superseded or stale

## Phase 2: Failure analysis (already-attempted issues)

For each `already-attempted` issue, analyze the bot branch (parallel agents if many).
Deterministic failure types (size thresholds per the `decomposition.md` rule):
- **over-engineered** -- diff over the decomposition thresholds
- **small-testable** -- small diff, worth re-trying
- **stale-base** -- 0 commits ahead of the default branch

Judgment types (read the diff):
- **wrong-approach** -- built the wrong thing
- **scope-creep** -- fixed the issue but broke unrelated things
- **test-failure** -- code is correct but tests fail for a specific reason

For each: compare the diff to the issue, check for files that shouldn't be touched, and for
3+ attempts identify the recurring pattern (is the issue itself mis-scoped?). Decide:
re-delegate with constraints, decompose, or human-only.

### Attempt count rules (know-when-to-quit)

- 1 prior attempt: analyze and re-delegate with corrections
- 2 prior attempts: re-delegate only if the failure mode is clearly addressable
  (stale-base, scope-creep with obvious fix). Otherwise decompose.
- 3+ prior attempts: do NOT re-delegate the same scope. Either decompose into
  fundamentally different sub-tasks or classify as human-only.

## Phase 3: Cross-issue gap analysis

The core value-add. Multiple issues often describe facets of one gap; delegating them
independently produces conflicting implementations.

### Detect file overlap

For each pair of issues about to be delegated, identify likely files from the bodies. If
they overlap, apply `conflict` to both and note it in the plan; resolve by sequencing
(`blocked` on the later one) or by confirming independence (remove `conflict`).

### Identify clusters

Group by shared modules, shared concern, dependency chains, and shared failure pattern.

### Research the gap

For each cluster: read the relevant source, all issue bodies, and failure diffs; then name
the real constraint behind repeated failures:
- Missing test infrastructure (agent can't validate the change)
- Unclear acceptance criteria (agent guesses wrong)
- Coupled modules (coordinated edits across files)
- Wrong decomposition (sub-tasks don't align with module boundaries)

### Prototype when necessary

If you can make the design decision: sketch the approach in the develop prompt, with exact
signatures and names. The agent implements to spec; it doesn't design. If you can't: flag
for human input, record what was learned, suggest a time-boxed spike.

### Merge vs decompose

- **Merge** small issues that touch the same files or one component, when the combined scope
  stays within the decomposition thresholds and none needs human-only validation. Merge
  procedure: see `/cycle` (Execute: Merge). Acceptance criteria = union of all issues.
- **Decompose** one issue that is too big: run `/decompose N` (background, one per issue,
  during Phases 2-4 so proposals are ready for the plan table). Filing sub-issues and
  updating the parent is owned by `/decompose`.
- Never both: if merging produces something too big, reconsider scope.

## Phase 4: Compose develop prompts

The prompt is the agent's entire brief. Each one has:

- **Objective** -- one sentence, what not how
- **Files in scope** -- explicit list, each read to confirm it exists; "Do NOT touch" everything else
- **Acceptance criteria** -- numbered, independently verifiable, mapped to tests or the repo's gate
- **Context** -- snippets from the current default branch, API signatures, adjacent patterns to follow
- **Do NOT** -- repo rules, no new abstractions for one-time operations, no changes outside
  scope, plus failure-specific constraints when re-delegating
- **Verify** -- the repo's `fast` gate tier (and `device` if criteria require it)

Quality check before dispatch: objective unambiguous, every file exists, context is current,
criteria testable without manual device testing, one concern.

Labels per `AGENTS.md`: `bot` (remove `divergence` on re-delegation), `device`,
`composite`, `spike`, `conflict` (with a comment naming the other issue).

## Phase 5: Present and confirm

```
| # | Title | Classification | Labels | Action | Notes |
|---|-------|---------------|--------|--------|-------|
```

Include failure summaries, proposed sub-issues, merge groups (with primary), and cluster
strategy. **Wait for approval.** The user may approve selectively, reclassify, or add context.

## Phase 6: Execute

- `/develop N` or `/develop 3,9,16` (max 4 parallel), which spawns
  `subagent_type: devloop:develop` with the composed prompt.
- `scripts/gh-ops.sh delegate N [--label L]` for label + audit comment + prune. All GitHub
  operations go through `gh-ops.sh` (run it with no arguments for the subcommand list).
- Clean stale branches for an issue before re-delegating.

Report:
```
Developed: #X, #Y (labels: bot +device +spike as applicable)
Merged: #A, #B -> #P
Decomposed: #D -> #D1, #D2 (#D2 blocked by #D1)
Closed: #C1 (superseded by #C2)
Skipped (human-only / blocked / icebox): #H1 / #B1 / #I1
```

## Encoded Lessons

- **Agents over-engineer by default.** Explicit scope boundaries are mandatory.
- **Previous failure context is gold.** Agents have no memory of prior branches; say exactly
  what the last attempt got wrong.
- **One issue, one concern.** A "simple" fix touching > 3 files is usually wrong-scoped.
- **Validation the agent can't run is human-only.** If the acceptance needs a device or
  hardware tier the agent can't reach, don't delegate it.
- **Clean before re-delegating.** Stale branches confuse discovery scoring.
- **Context prevents invention.** Show the pattern to follow or the agent invents one.
- **Clusters beat individual issues.** Coupled issues go as a coordinated sequence.
- **Agents can research.** `spike` issues are delegatable: exact questions, findings in
  `docs/` with sources, facts separated from speculation.

## Edge Cases

- No open issues -- report "No open issues to delegate"
- All human-only -- report classification, suggest which to tackle manually
- Issue has no body -- human-only (needs scoping)
- Branch fresh (< 24h) -- skip, work in progress
- Rate limiting -- pause, report to user
