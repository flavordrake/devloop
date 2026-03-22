# Workflow

## Fix the process, not the symptom
- **When a process failure occurs, diagnose and fix the process** — do not work around it by doing the task manually. If an agent fails because of CWD drift, fix the CWD guard, don't "just do the small change" yourself.
- **Separate concerns in persistent policy.** Rules about one language/framework don't belong mixed with application-specific state machine rules. Application conventions get their own scoped rule files.
- **Capture compound bash patterns as intent-named scripts** for reusability, not inline chains.

## Inferred constraints
- **Never silently adopt an inferred constraint** that impacts architecture, language, or testability.
- If a constraint wasn't explicitly stated by the user, call it out prominently: "I'm assuming X, this affects Y and Z. Confirm?"
- When writing rules, mark inferred-but-impactful constraints with [INFERRED] so they get reviewed.

## Issue workflow
- `bug: <description>` in user messages = file a GitHub issue, do NOT fix immediately.
- Bot tasks: use `/develop N` to spawn local develop agents, or `/delegate` to classify and dispatch in bulk.

## Know when to quit
- If a feature needs >2 fix cycles after initial implementation, pause and branch it off.
- If every fix introduces a new bug, the abstraction is wrong. Step back.
- Prefer contained changes; if a feature scatters guards across unrelated handlers, it's too coupled.

## After /clear
Read `.claude/skills/*/SKILL.md` descriptions and `.claude/agents/*.md` to re-establish awareness of available automation.
