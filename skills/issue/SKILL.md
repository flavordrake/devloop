---
name: issue
description: Use when the user says "bug:", "feature:", "feat:", "fix:", "issue:", "chore:", or explicitly "/issue". File an issue (GitHub or the repo's local backlog) without interrupting the current workflow. Run as a background Task so the main conversation continues unblocked.
---

# Issue Filing

Labels, domain labels, and the issue tracker come from the repo's `.claude/process.md`.

File an issue from an in-conversation observation. The user types something like
`bug: default URL is missing /ssh` and expects it handled without derailing current work.

## Execution Model

Spawn `subagent_type: devloop:issue-manager` with `run_in_background: true`. If it fails on
permissions, run it in foreground or file directly in the main conversation.

## Step 1: Parse the trigger

Apply exactly one **Type** label:

| Prefix | Type label | Title prefix |
|---|---|---|
| bug: | `bug` | bug: |
| fix: | `bug` | fix: |
| feature: | `feature` | feature: |
| feat: | `feature` | feat: |
| chore: | `chore` | chore: |
| issue: | (classify from description) | (classify from description) |

Add **Domain** labels from the domain list in `.claude/process.md` when the description
matches. If process.md declares none, add none.

Add **Shape** labels when applicable:

| Condition | Label |
|---|---|
| Needs research before code can be written | `spike` |
| Needs emulator/device/hardware validation | `device` |
| Too large for one develop pass | `composite` |

Do NOT apply `bot` or `divergence` -- `/delegate` and `/integrate` manage those.

## Step 2: Gather context

Concise body, no filler:

- **Context line**: what was being worked on (branch, feature, test).
- **Description**: clear problem statement or feature request with known technical details
  (paths, functions, config values).
- **Reproduction**: steps for bugs, user need for features.
- **Version**: `scripts/gh-ops.sh version` (code hash; flags a stale running build if the
  repo reports one).
- **Evidence**: if the repo declares repro artifacts (test reports, screenshots, recordings,
  logs) in `.claude/process.md`, attach recent ones (last ~30 minutes) clearly tied to the
  issue. Otherwise omit.

## Step 3: Duplicate check and file

Search first (`scripts/gh-ops.sh search "<key phrase>"`, or grep the local backlog). If a
match exists, ask whether to file or comment on the existing one.

Body template:

```
Filed while working on <context> (<branch>).

<Problem statement or feature description with technical details.>

## Reproduction
<Steps, or user need.>

## Version
<version output>

## Evidence
<Only if Step 2 found relevant artifacts.>
```

**Tracker `github`** (default): write the body to a file, then
`scripts/gh-file-issue.sh --title "<prefix>: <title>" --label "<type>" [--label "<domain>"] --body-file <file>`.

**Tracker `local:<path>`**: append an entry to `<path>` following the format already used
in that file (title line with type/labels, then the body). Commit it only if the repo's
process.md says backlog edits are committed.

## Step 4: Report back

`Filed: <issue-url or path:line>`. On failure, report the error; don't retry silently.

## Edge Cases

- Bare prefix with no description (just `bug:`) -- ask for at least a phrase
- `gh` not authenticated -- report immediately
- Only use labels defined in `.claude/process.md`
