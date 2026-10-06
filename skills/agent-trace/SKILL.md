---
name: agent-trace
description: Opt-in protocol for capturing a complete development arc (TRACE). Includes telemetry, strategy pivots, logs, and performance metadata. Use this to record the "how and why" of an objective, especially for performance-critical or non-deterministic tasks.
---

# Agent TRACE (Trajectory & Runtime Artifact Collection Environment)

A TRACE records not just the final code but the decision chain behind it: intent,
hypotheses, pivots, telemetry, and outcome. TRACE is **opt-in**: nothing happens
until you start one, and the devloop hooks stay silent while no trace is active.

Use it for performance-critical work, non-deterministic or multi-session tasks,
and work likely to fail informatively. Skip it for routine changes.

## 1. Start, check, close

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/trace-init.sh" "objective-slug"
```

Run from anywhere inside the project. It creates
`.traces/trace-{slug}-{timestamp}/` at the project root (next to `CLAUDE.md`) and
writes an `> **Active TRACE**: \`.traces/trace-.../\`` line into the project
`CLAUDE.md`, replacing any previous one. That line is what activates the hooks.
Keep `.traces/` gitignored: TRACEs are local artifacts, their harvested insights
are what persist.

| Script | Purpose |
|---|---|
| `scripts/trace-init.sh <slug>` | Create a trace and mark it active |
| `scripts/trace-checkpoint.sh [label]` | One-line status; silent if no active trace |
| `scripts/trace-check.sh [trace-dir]` | Full health report: staleness, commits, empty sections, pivots |
| `scripts/trace-attach.sh <trace-dir> <url>` | Download a file into `artifacts/` |

**Close** a trace by setting `status: success` or `status: failure` in the
TRACE.md frontmatter (hooks go quiet), or remove the Active TRACE line.

## 2. Directory structure

```text
trace-dir/
├── TRACE.md           # Executive summary, metadata, and final outcomes
├── specs/             # Original requirements and identified ambiguities
├── strategy/          # Initial plan and pivots (the decision chain)
├── logs/              # Reasoning logs, build output, pre-compact snapshots
├── telemetry/         # Profiler reports and before/after measurements
└── artifacts/         # Success/failure code snapshots and sanitizer reports
```

### TRACE.md frontmatter

```yaml
id: [unique-id]
objective: [high-level-goal]
status: [in-progress | success | failure | partial]
skills-used: [list-of-skills]
resources:
  tokens: [total-token-count]
  compute_footprint:
    cpu_time: [format: 00m:00s]
    gpu_time: [format: 00m:00s]
metrics:
  target: [e.g., 900 TFLOPS]
  achieved: [actual-result]
```

## 3. Recording the arc

### Initial plan

`strategy/initial_plan.md` is a **pointer**, not a rewrite of the issue:

```markdown
# Initial Strategy
Issue: #165 — fix: test 5.1 uses relative URL that CDP rejects
Approach: as described in issue body
Assumptions that might be wrong: [only non-obvious assumptions]
```

The value is in the **delta** from the plan. If nothing changed, the trace is
short and that is fine. For HPC work also record tiling sizes, register budgets,
and memory alignment expectations.

### Telemetry (before/after)

Capture raw data before and after the change so deltas are visible at harvest.
Capture, do not analyze. Prefer zero-effort instrumentation: the project's test
suite duration at minimum, plus whatever profiler fits the stack.

For HPC/CUDA tasks: run Nsight Compute, Nsight Systems, or compute-sanitizer.
Save raw output to `telemetry/` and a bottleneck summary to `logs/`.

### Pivots

Whenever evidence contradicts the hypothesis, create `strategy/pivot_N.md` with:

1. **Triggering evidence** (e.g., "High Register Pressure", "59 headless test failures")
2. **Structural change** (e.g., "Reduced Block Size", "batched writes per frame")
3. **Quantified delta** in performance or correctness

### Final summary

The agent that lived the arc writes the summary; the harvester should not have
to re-derive it. Populate the TRACE.md body:

- **The "Why"**: why the final strategy succeeded or failed.
- **The "Ambiguity Gap"**: how specs were clarified; what was assumed vs. stated;
  what the user corrected.
- **The "Knowledge Seed"**: a one-sentence heuristic for future agents
  (e.g., "On sm_90, favor TMA over manual SMem loads for 10% gain").
- **Performance Delta**: one line, referencing `telemetry/`. "No measurable
  impact" is a valid result.
- **Security Summary**: one line on static analysis of changed files.
- **Outcome Classification**: `success` | `success-with-caveats` | `partial`
  (file issues for the remainder) | `failure-informative` (TRACE explains why,
  code on branch) | `failure`.

These one-liners are greppable across hundreds of traces.

### Behavioral change checklist

When the change affects **initial system state** (startup behavior, defaults,
entry points, preconditions), add a downstream impact section: which test
harnesses assume the old state, which of them run outside CI (those break
silently), and whether fixtures need updates (file an issue now). See
`rules/platform/` for platform examples.

## 4. Roles

**Orchestrator (main session)** owns the TRACE: initializes it, passes the trace
directory to every agent spawned for the objective, maintains top-level TRACE.md,
and harvests on completion.

**Agents** given a trace directory write `strategy/initial_plan.md` after reading
the issue, a pivot when the approach changes, and their outcome before the final
commit. Failure traces are the most valuable: document what was tried and why
it failed.

### Harvest

After a trace completes, extract:

1. **Knowledge Seeds** → project memory
2. **Pivots** → process improvements (skills, rules)
3. **Security findings** and **bug patterns** → issues
4. **Ambiguity Gaps** → spec and issue quality improvements

### Prior-run enrichment

When spawning an agent, check `.traces/` for prior runs on the same issue and
include a distilled summary in the prompt:

```
## Prior TRACE context
- trace-issue-N-20260315: FAIL — "touchstart preventDefault blocks scroll"
- trace-issue-N-20260316: PARTIAL — "tabindex=-1 prevents focus but not on all Android"

Session learnings: "User correction: ^keys go at end, not interspersed"
```

### Session traces

A trace can cover one agent on one issue (`trace-issue-N-*`) or a whole
orchestrator session (`trace-session-*`): issues and outcomes, **user
corrections** (the most valuable data), process improvements, and sequencing
decisions. Before compaction, write session learnings to the trace so the new
context starts from trace pointers, not raw history.

## 5. Checkpoints

With a trace active, the plugin hooks emit a one-line status:

| Event | Behavior |
|---|---|
| SessionStart | Status line as context |
| PostToolUse after a `git commit` | Status line as context |
| PreCompact | Writes `logs/compact-{timestamp}.md` with status and git state |

```
TRACE (commit): 1 pivots, 3 commits since last update 45m ago — update TRACE before next commit
```

| Level | Condition | Message |
|---|---|---|
| quiet | otherwise | status only |
| drift | >2 commits and >30m | "update TRACE before next commit" |
| stale | >60m or >5 commits | "[STALE] update TRACE.md now" |

Respond by updating TRACE.md, or state a reasoned exception ("updated 30s ago,
no new decisions"). No active, closed, or missing trace means no output.
