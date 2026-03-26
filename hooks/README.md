# devloop hooks

TRACE protocol hooks for Claude Code. Install in `settings.json` to enable
automatic TRACE checkpoints at decision points.

## Installation

Add to your workspace or project `settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "/path/to/devloop/hooks/trace-session-start.sh" }]
    }],
    "PreCompact": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "/path/to/devloop/hooks/trace-pre-compact.sh" }]
    }],
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "/path/to/devloop/hooks/enforce-hygiene.sh" }]
    }],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "/path/to/devloop/hooks/trace-signal.sh" }]
      },
      {
        "matcher": "Edit",
        "hooks": [{ "type": "command", "command": "/path/to/devloop/hooks/trace-signal.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "/path/to/devloop/hooks/trace-checkpoint.sh" }]
      }
    ],
    "SubagentStart": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "/path/to/devloop/hooks/trace-agent-spawn.sh" }]
    }]
  }
}
```

## Hook files

| File | Event | Purpose |
|------|-------|---------|
| `trace-session-start.sh` | SessionStart | Check TRACE status on session begin |
| `trace-pre-compact.sh` | PreCompact | Checkpoint + snapshot before context compression |
| `trace-checkpoint.sh` | PostToolUse:Bash | Checkpoint on commits, deploys, gh-ops |
| `trace-signal.sh` | PostToolUse:Write/Edit | Signal on memory, settings, rules, CLAUDE.md changes |
| `trace-agent-spawn.sh` | SubagentStart | Log agent spawn + checkpoint |
| `enforce-hygiene.sh` | PreToolUse:Bash | Command hygiene reminders |

All hooks delegate to `scripts/trace-checkpoint.sh` for the one-line status.

## Checkpoint protocol

See `rules/trace-contract.md` for the full protocol. Key points:
- Checkpoints are **blocking** — agent must respond before proceeding
- Valid response: update TRACE.md or state a reasoned exception
- Escalating severity: quiet → drift warning → STOP instruction
