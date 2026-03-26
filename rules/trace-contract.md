# TRACE Contract

Every agent must understand and participate in the TRACE protocol. This is not
optional — it's part of the agent lifecycle, like committing code or running tests.

## Agent responsibilities

### Accept TRACE input
- Agents receive a TRACE directory path in their prompt (if one exists)
- Prior TRACE artifacts (specs, pivots, failure summaries) inform the agent's approach
- The orchestrator passes relevant TRACE context when spawning agents

### Generate TRACE output
- **On start**: Record initial plan in `strategy/initial_plan.md`
- **On pivot**: Create `strategy/pivot_N.md` when approach changes
- **On completion**: Populate `TRACE.md` with Why, Ambiguity Gap, Knowledge Seed
- **On failure**: TRACE is especially valuable — document what was tried and why it failed

### Update at key lifecycle points
- After reading the issue/spec (initial plan)
- After first test run (baseline captured)
- After each development cycle (delta from previous)
- After finding something unexpected (pivot)
- Before final commit (outcome classification)

## Checkpoint protocol

TRACE checkpoints fire at every decision point: commits, deploys, issue filings,
PR creation, agent spawns, and context compaction. They are **blocking** — the
agent must respond before proceeding.

### When checkpoints fire
- `git commit` / `git push`
- `container-ctl.sh restart` / `ensure` (deploy)
- `gh-ops.sh integrate` / `pr-create` / `pr-merge`
- `gh-file-issue.sh` (issue filed)
- `SubagentStart` (agent spawned)
- `PreCompact` (context about to compress)
- `SessionStart` (session begins/resumes)

### How to respond to a checkpoint

The checkpoint emits a one-line status:
```
TRACE (commit): 3 commits, 1 agents since last update 45m ago — update TRACE before next commit
```

**Valid responses:**
1. **Update TRACE.md** — summarize what changed, current decision, what's next
2. **Reasoned exception** — "TRACE updated 30s ago, no new decisions since"
   or "rapid iteration on same fix, will batch update after deploy"

**Invalid:** Ignoring it. Proceeding without acknowledging. Treating as informational.

### Escalation levels

| Level | Condition | Message |
|-------|-----------|---------|
| 0 (quiet) | <30m, <3 commits | Status only |
| 1 (drift) | 30-60m with 3+ commits | "update before next commit" |
| 2 (stale) | >60m OR >5 commits OR BOILERPLATE/CLOSED | "STOP and update TRACE.md now" |

### Script

```bash
scripts/trace-checkpoint.sh [trigger-label]
```

General-purpose, callable from hooks, agent prompts, or manual invocation.
All hooks delegate to this script. Returns one-line status to stdout.

### Hooks (installed in settings.json)

| Hook event | File | Trigger |
|------------|------|---------|
| PostToolUse:Bash | `hooks/trace-checkpoint.sh` | commit, push, deploy, gh-ops |
| PostToolUse:Write/Edit | `hooks/trace-signal.sh` | memory, settings, rules, CLAUDE.md |
| PreCompact | `hooks/trace-pre-compact.sh` | context compression + snapshot |
| SessionStart | `hooks/trace-session-start.sh` | session begin/resume/clear |
| SubagentStart | `hooks/trace-agent-spawn.sh` | agent spawned + log |

## Orchestrator responsibilities

### Initialize
```bash
scripts/trace-init.sh "objective-slug"
```
Pass the TRACE directory path to every agent spawned for this objective.
Update `CLAUDE.md` with the new trace path immediately.

### Respond to checkpoints
The orchestrator (main session) owns the TRACE. When a checkpoint fires,
the orchestrator updates TRACE.md or states why not. Subagents update their
own TRACE artifacts (strategy/, pivots) but the orchestrator maintains the
top-level TRACE.md.

### Harvest
After agents complete, extract:
1. **Knowledge Seeds** → project memory
2. **Pivots** → process improvement rules
3. **Security findings** → issue filing
4. **Ambiguity Gaps** → spec/issue quality improvements

### Persist
TRACE directories are local (gitignored). They're development artifacts,
not committed to the repo. The harvested insights go into durable storage
(memory, rules, issues).

## Why every agent

A develop agent that doesn't TRACE:
- Loses the reasoning behind its approach when context compresses
- Can't explain why it chose implementation A over B
- Produces no learning for future agents working on similar issues
- Has no artifact to review when the approach fails

A test agent that doesn't TRACE:
- Can't explain why it tested X but not Y
- Doesn't document edge cases it considered but skipped

A spec agent that doesn't TRACE:
- Can't explain what was ambiguous in the issue
- Loses the delta between "what the issue said" and "what it meant"

## Integration with skills

Every skill that spawns agents should:
1. Init a TRACE before spawning
2. Pass the TRACE dir to each agent
3. Check TRACE artifacts between phases
4. Harvest on completion

Skills: `/spec-develop`, `/cycle`, `/develop`, `/write-tests`, `/delegate`, `/integrate`

## Behavioral change checklist

When a TRACE documents a change that affects **initial system state** (startup
behavior, default configuration, entry points, expected preconditions), it must
include a **downstream impact** section:

1. **Which test harnesses assume the old state?** List by name and file.
2. **CI vs non-CI frequency:** Tests that run on every commit catch regressions
   immediately. Tests that run infrequently (manual, scheduled, device-specific)
   break silently — failures aren't discovered until someone runs them.
3. **Fixture updates needed?** If yes, file an issue immediately — don't wait for
   someone to manually discover the failure days later.

This checklist should also be part of the develop agent's self-review step.

See `rules/platform/` for platform-specific examples of this checklist.
