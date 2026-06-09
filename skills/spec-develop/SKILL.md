---
name: spec-develop
description: Full TDD pipeline — spec formulation, test writing, development. Use when the user says "spec-develop", "tdd", "implement with tests", or explicitly "/spec-develop N". Orchestrates three agents in sequence for a single issue.
---

# Spec → Test → Develop Pipeline

Orchestrates the full TDD cycle for a single issue: formulate a testable spec,
write tests that express the spec (red baseline), then develop until tests pass (green).

## Input

- `/spec-develop 42` — run the full pipeline for issue #42
- `/spec-develop 42 --skip-spec` — skip Phase 0 (spec already exists or is trivial)
- `/spec-develop 42 --spec-only` — just formulate the spec, don't test or develop

## When to use

- Features with non-trivial acceptance criteria
- Bugs where the expected behavior needs clarification
- Any issue where "what does done look like?" isn't obvious from the title

For simple 1-file bug fixes with clear reproduction, `/write-tests N` + `/develop N`
is fine. This skill adds value when the spec is ambiguous.

## Phase 0: Spec Formulation

Spawn a **read-only** agent to produce a testable behavioral spec.

**Agent prompt:**
```
You are a spec formulation agent. Your job is to read the issue and produce
a natural-language behavioral spec with observable, testable assertions.

Read:
- The issue body (gh issue view N)
- Relevant source files mentioned in the issue
- Adjacent test files to understand testing patterns

Produce a spec with:
1. **Preconditions** — what state must exist before the behavior
2. **Actions** — what the user or system does (concrete, not abstract)
3. **Assertions** — what is observable after the action (DOM state, function output,
   message sent, state changed). Each assertion must be verifiable by a test.
4. **Edge cases** — boundary conditions, empty input, error paths
5. **Untestable claims** — flag anything that can't be verified by automated test
   (e.g., "feels responsive", "looks good") as requiring device testing

**Mark every ambiguity, do not guess.** Whenever the issue leaves a behavior,
value, scope, or edge case underspecified and you have to ASSUME something to
write the spec, tag that assumption inline with a marker:

    [NEEDS CLARIFICATION: <the specific ambiguity, phrased as a question>]

Examples:
- "On invalid input the form shows an error [NEEDS CLARIFICATION: inline field
  error or a toast?]"
- "Sessions persist across restart [NEEDS CLARIFICATION: how many, and is there
  an eviction limit?]"

Do NOT silently pick a default — a silent guess is exactly what causes the bot
to build the wrong thing and forces a re-delegation. Surfacing it as a marker
lets the orchestrator resolve it (Phase 0.5) before any test is written. These
markers feed the TRACE "Ambiguity Gap" field.

Do NOT write code or tests. Only produce the spec.
Post the spec as a comment on the issue.
Write the spec to /tmp/spec-{N}.md.
```

**What the orchestrator checks after Phase 0:**
- Every assertion is concrete (not "works correctly" but "returns X when given Y")
- No circular assertions ("it does what it should do")
- Untestable claims flagged explicitly
- Every assumption the agent had to make is tagged `[NEEDS CLARIFICATION: ...]`
  rather than silently resolved
- At least 3 assertions for features, at least 1 for bug fixes

If the spec is inadequate, the orchestrator provides feedback and re-runs Phase 0.

## Phase 0.5: Clarify

**Orchestrator step — no agent.** Gate the pipeline on a clarified spec: the
formulated spec must contain NO unresolved `[NEEDS CLARIFICATION]` markers before
test-writing begins.

1. Scan `/tmp/spec-{N}.md` for `[NEEDS CLARIFICATION: ...]` markers.
2. **If none:** the spec is clarified — proceed to Phase 1.
3. **If any:** present them to the user with **AskUserQuestion** (the project's
   required clarification tool — structured options, never an open-ended prompt).
   - One question per marker. Phrase the marker's ambiguity as the question.
   - Offer concrete, mutually-exclusive options (the plausible resolutions you'd
     otherwise have guessed). Include an "Other / let me specify" path for
     anything the options don't cover.
4. Fold each answer back into `/tmp/spec-{N}.md`: replace the assumption + its
   marker with the user's chosen behavior. **Remove the marker** — a resolved
   ambiguity is no longer a marker.
5. Re-scan. Only when zero markers remain does the pipeline advance to Phase 1.

Keep it lightweight: batch all markers into as few AskUserQuestion calls as the
tool allows, resolve in one pass, then move on. Do NOT spawn an agent for this.

**What the orchestrator checks after Phase 0.5:**
- `/tmp/spec-{N}.md` contains zero `[NEEDS CLARIFICATION]` markers
- Each former marker was replaced with a concrete, testable behavior (not deleted
  and left vague)
- The resolved ambiguities are recorded for the TRACE "Ambiguity Gap" field
  (what was assumed → what the user actually wanted)

## Phase 1: Test Writing

Use the `/write-tests` skill with the spec as input.

**Key difference from standalone /write-tests:** The test agent reads the SPEC, not
the raw issue. The spec's assertions map directly to test cases.

```
Agent prompt addition:
"Read /tmp/spec-{N}.md for the behavioral spec. Each assertion in the spec
should have at least one corresponding test. Tests that FAIL are expected —
this is the red baseline for TDD."
```

**What the orchestrator checks after Phase 1:**
- Tests compile (tsc passes)
- Tests that should fail DO fail (red baseline confirmed)
- Each spec assertion has at least one test
- No tests that pass trivially (testing a no-op)

Merge the test PR to main (use `gh-ops.sh pr-merge`, NOT `integrate` which closes the issue).

## Phase 2: Development

Use the `/develop` skill with the pre-existing failing tests.

```
Agent prompt addition:
"Tests already exist on main. Your job is to make the FAILING tests pass.
Do NOT write new tests. Read /tmp/spec-{N}.md for context on what the
tests expect. You CAN update tests if they're wrong (testing the wrong
thing), but document why."
```

**What the orchestrator checks after Phase 2:**
- All previously-failing tests now pass
- No regressions (full test suite green)
- Fast gate passes (tsc + eslint + vitest)
- Diff is minimal — implementation matches spec, no scope creep

Merge via `gh-ops.sh integrate PR ISSUE` (this closes the issue).

## Lightweight mode (--skip-spec)

For issues where the spec is already clear (bug with reproduction steps, small feature
with concrete acceptance criteria), skip Phase 0:

1. Validate the issue body has testable assertions
2. Run Phase 1 (test writing) directly from the issue body
3. Run Phase 2 (development)

Skipping Phase 0 also skips Phase 0.5 — with no formulated spec there are no
`[NEEDS CLARIFICATION]` markers to resolve. If the issue body itself reads as
ambiguous, don't use `--skip-spec`; run the full pipeline so the clarify gate
can catch it.

Use this for most bug fixes and small features. Reserve the full pipeline for
features where "done" is ambiguous.

## Execution model

Run **foreground**. The orchestrator manages the pipeline and checks quality between
phases. Each agent runs in the background with `isolation: "worktree"`.

The orchestrator does NOT develop code — it manages the pipeline, checks quality,
and provides feedback between phases. If an agent fails, the orchestrator diagnoses
and re-runs with corrections (max 2 retries per phase).

Phase 0.5 (Clarify) is the orchestrator's own step: it runs AskUserQuestion directly
and edits the spec — no agent, no retry budget. The pipeline does not advance to
Phase 1 until the spec has zero unresolved `[NEEDS CLARIFICATION]` markers.

## TRACE integration

Initialize a TRACE at the start of the pipeline:
```bash
scripts/trace-init.sh "spec-develop-{N}"
```

Record in `strategy/initial_plan.md`:
- Issue summary and which phases will run
- Whether full or lightweight mode

After each phase, update the TRACE:
- **Phase 0**: save spec to `specs/spec-{N}.md` in the trace dir, including any
  `[NEEDS CLARIFICATION]` markers it surfaced
- **Phase 0.5**: record each marker and how the user resolved it (assumed → wanted) —
  this is the raw material for the "Ambiguity Gap" field
- **Phase 1**: record test count, which assertions map to which tests
- **Phase 2**: record cycles used, lines changed, any test updates

On completion, populate `TRACE.md` with:
- **The "Why"**: what the spec clarified that the issue didn't
- **The "Ambiguity Gap"**: what was assumed vs stated
- **The "Knowledge Seed"**: heuristic for future spec-develop runs

## Integration with /cycle

The `/cycle` skill should call `/spec-develop N` instead of `/develop N` for issues
that need spec formulation. The cycle skill determines which issues need full
spec-develop vs lightweight mode based on:

- Issues with `spike` label → full spec-develop (ambiguous by definition)
- Issues with >3 files in scope → full spec-develop
- Issues with clear reproduction steps → lightweight (`--skip-spec`)
- Bug fixes with <50 lines expected → lightweight

## Anti-patterns

- Don't let the develop agent write its own tests — that's the whole point of this skill
- Don't skip Phase 0 for ambiguous specs — "implement what the issue says" produces
  tests that test the implementation, not the intent
- Don't merge test PRs with `integrate` — that closes the issue before development
- Don't retry more than twice per phase — if the spec can't be written or tests can't
  be formulated, the issue needs human clarification
