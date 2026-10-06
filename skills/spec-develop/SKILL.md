---
name: spec-develop
description: Full TDD pipeline — spec formulation, test writing, development. Use when the user says "spec-develop", "tdd", "implement with tests", or explicitly "/spec-develop N". Orchestrates three agents in sequence for a single issue.
---

# Spec, Test, Develop

Formulate a testable spec, write failing tests from it, then develop until they pass.
The orchestrator manages phases and checks quality between them; it does not write
code. Max 2 retries per agent phase; past that the issue needs human clarification.

## Input

- `/spec-develop 42`: full pipeline
- `/spec-develop 42 --skip-spec`: start at Phase 1 from the issue body (clear repro or concrete acceptance criteria only; an ambiguous issue needs the full pipeline so the clarify gate can catch it)
- `/spec-develop 42 --spec-only`: Phases 0 and 0.5 only

Use this when "what does done look like?" is not obvious. For clear bug fixes,
`/develop N` is enough.

## Phase 0: Spec

Spawn `devloop:spec-writer` with the issue number and a spec path (a file in a
`mktemp -d` directory). The agent holds the format and quality bar. Check the result:
concrete, non-circular assertions (at least 3 for features, 1 for bugs), untestable
claims flagged, and every assumption tagged `[NEEDS CLARIFICATION: ...]`. Inadequate:
give feedback and re-run.

## Phase 0.5: Clarify (orchestrator, no agent)

The spec must have zero `[NEEDS CLARIFICATION]` markers before tests are written.
1. Scan the spec for markers. None: go to Phase 1.
2. Ask the user with AskUserQuestion, one question per marker, concrete mutually
   exclusive options plus "Other". Batch markers into as few calls as possible.
3. Replace each assumption and its marker with the chosen behavior, concrete and testable.
4. Re-scan; advance only at zero markers. Record each assumed-versus-wanted pair for the TRACE Ambiguity Gap.

## Phase 1: Tests

Spawn `devloop:test-writer` in mode `red` on branch `bot/issue-{N}`, pointing it at
the spec: each assertion gets at least one test. Check: tests load and compile, the
ones that should fail do fail for the right reason, every assertion is covered, no
trivially passing tests. Merge the test PR with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh pr-merge`,
not `integrate` (which would close the issue).

## Phase 2: Develop

Spawn `devloop:develop` (see `/develop` for the prompt) adding: "Failing tests for this
issue are on main; make them pass. Read <spec path> for intent. Do not add net-new
tests; fix a wrong test only with a stated reason." Check: previously failing tests
pass, the `fast` gate is green, the diff matches the spec without scope creep. Merge
with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh integrate <PR> <issue>`.

## TRACE

Record the plan and mode; per phase: the spec and its markers, how each marker was
resolved, the assertion-to-test mapping, and cycles and lines changed. On completion:
Why (what the spec clarified), Ambiguity Gap, Knowledge Seed.

## Anti-patterns

- Letting the develop agent write its own tests: it ends up testing its implementation, not the intent.
- Skipping the spec for ambiguous issues.
- Merging the test PR with `integrate`.
