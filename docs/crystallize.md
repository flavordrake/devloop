# Crystallize: Design Overview

## The Problem

An LLM-driven development workflow accumulates skill documents — recipes
that tell the LLM how to perform multi-step tasks. Over time these skills
grow prose-heavy: the author describes *how* to count things, parse
structured data, compare timestamps, and aggregate results, because at
write-time the LLM is the only executor available.

This creates two failure modes:

1. **Silent inaccuracy.** The LLM is asked to do arithmetic, time-series
   comparison, structured parsing, or counting. It gets it wrong sometimes
   and the error mode is invisible — there's no test, no assertion, no
   diff. The skill "works" most of the time, which makes the failures
   harder to catch than if it never worked.

2. **Irreducible bloat.** Every time a skill needs a deterministic
   operation, the author writes 5–15 lines of prose explaining the
   algorithm. The LLM reads all of it on every invocation, spending
   tokens narrating the computation instead of producing the output.
   The skill doc grows monotonically because nobody removes the prose
   after a script is written — the script and the prose coexist, with
   the prose re-explaining what the script already does.

Crystallize is the process of identifying these operations, extracting
them into real scripts with real tests, and rewriting the skill doc to
invoke the scripts. The source is not kept intact; it's compacted.

## The Boundary

Every instruction in a skill doc falls on one side of a hard line:

```
┌────────────────────────────────────────┐
│  LLM (probabilistic, judgment)         │
│                                        │
│  Intent disambiguation                 │
│  Code quality review                   │
│  UX tradeoff decisions                 │
│  Novel problem-solving                 │
│  Writing human-facing prose            │
│  Deciding WHICH script to call         │
│  Interpreting script output            │
├────────────────────────────────────────┤
│  Script (deterministic, tested)        │
│                                        │
│  Arithmetic, statistics                │
│  Timestamp/duration comparison         │
│  Counting files, lines, commits        │
│  Sorting, ordering, ranking            │
│  Parsing JSON/YAML/structured formats  │
│  Aggregation and grouping              │
│  Schema validation                     │
│  Version/hash comparison               │
│  Pattern matching (grep/glob)          │
│  Cascading diagnostic probes           │
└────────────────────────────────────────┘
```

Crystallize finds instructions below the line that are written above it,
and moves them down. The LLM's remaining job is exclusively judgment:
which script to call, what the output means, and what to do about it.

## How It Works

### Phase 1: Audit

Read the target SKILL.md. Classify every instruction:

- **A** — already invokes a script. Cite the file. No action needed.
- **B** — describes a deterministic operation in prose. Candidate for
  extraction. Signal phrases: "count the", "sort by", "parse the",
  "compare timestamps", or raw CLI invocations (`gh`, `git log`,
  `curl`, `jq` pipelines) that should use wrapper scripts.
- **C** — requires judgment, prose, or novel reasoning. One-line "why"
  so future passes don't re-attempt crystallization.

A deterministic audit script (`crystallize-audit.sh`) pre-computes
signal-phrase matches and script cross-references as structured JSON.
The LLM reviews the JSON and makes final A/B/C classification — the
deterministic tool reduces the LLM's job to judgment only.

### Phase 2: Discover Existing Tools

**Before writing anything new**, scan the repo for deterministic tools
that already exist but aren't referenced by any skill:

- `scripts/` — intent-named executables with CLI contracts
- `tools/` — utility programs (servers, parsers, extractors)
- `.traces/*/artifacts/` — one-off scripts built during problem-solving
  arcs, used once, never promoted

Classify each tool as **invoked** (some skill calls it), **orphaned**
(exists but no skill references it), **half-built** (started in a TRACE,
abandoned), or **dead** (unclear contract, no use case).

Cross-reference orphaned tools against B-bucket operations: any match
skips straight to the rewrite step. Zero new code, just wiring. This
is the highest-leverage path — the tool is already written, tested by
its original use, and proven against a real problem.

Output: a **tool registry** (`.claude/tool-registry.md`) that catalogs
all deterministic tools in the repo. Durable across passes, discoverable
by every skill.

### Phase 3–4: Mine Fixtures, Draft Scripts

For B-bucket operations with no existing tool:

1. Mine `.traces/` for real inputs the skill saw in past runs. Use those
   as test fixtures — not synthetic, not hand-crafted, real.
2. Draft a single-purpose script with a stable CLI. One script per
   operation. Add a test file that runs every fixture.
3. Register the new script in the tool registry.

### Phase 5: Verify

Run the script against every fixture. Confirm determinism (same output
every run). If a fixture represents an operation the LLM performed in a
TRACE, compare the script's output to what the LLM produced. If they
disagree:

- Script is wrong → fix it.
- LLM was wrong → this is the value proof. Log it.

### Phase 6: Rewrite

Replace prose with script calls. Be ruthless:

**Before** (15 lines):
```markdown
### Count bot attempts
Look in memory/bot-attempts.md for entries matching the issue number.
Each entry is a heading like ## #N: <title>. Count entries with
status: fail. If >= 3, do not re-delegate...
```

**After** (4 lines):
```markdown
### Count bot attempts
scripts/count-bot-attempts.sh <issue-number>
Output: integer. If >= 3, do not re-delegate.
```

The computation leaves. The decision stays. The SKILL.md gets shorter.

### Phase 7: Report

List scripts extracted, scripts reused, LLM-inconsistency findings,
and operations that stayed probabilistic with justifications. This
report is the durable artifact — future passes start from it.

## Validation: Integration Tests

Crystallize is tested against three real historical extractions where a
human identified a deterministic operation and built a script to replace
LLM prose work. Each test case has:

- **SKILL-before.md** — the skill doc before the human extracted
- **SKILL-after.md** — the skill doc after (ground truth)
- **MANIFEST.md** — what the human found and why
- **Fixtures** — snapshots of the scripts and TRACE data at extraction time

The test runs the audit against the before-state and checks:
- Did the audit find the same B-bucket operations the human found?
  (recall)
- Did it avoid flagging C-bucket operations as B? (precision)
- Did phase 2 discover the orphaned tools the human promoted?

Current test suite: 14/14 passing across delegate (prose → script
extraction), agent-trace (orphaned tool discovery), and boot-splash
(TypeScript module extraction).

## When Not to Crystallize

- **Short skills (<100 lines) that are mostly judgment.** Compaction
  has a floor. `decompose` is a good example — it's fundamentally about
  deciding how to split work, not computing anything.

- **Operations where a 200-line script full of heuristics would replace
  a 1-paragraph LLM instruction.** That's a sign the operation is
  actually probabilistic and the script is a brittle simulation of
  judgment. Revert, move to C-bucket.

- **Prose that documents pitfalls and design principles.** This isn't
  computation — it's institutional knowledge the LLM needs to make good
  decisions. Crystallize preserves it.

## Outcome

After a crystallize pass, every tool call in the skill is either:

**(a)** a deterministic script that takes structured input and produces
structured output, or

**(b)** a prose response that makes a judgment based on the structured
output of a prior script.

The LLM never does math. The LLM never counts. The LLM never compares
timestamps. The LLM never parses a format it could invoke a parser for.
Those are script jobs, and crystallize is the pass that finds them and
makes them so.
