# State Management

## Don't infer state from boolean combinations

When multiple booleans (`connected`, `wsOpen`, `authenticated`, `wasConnected`) are
checked in different combinations across the codebase, the system is missing an explicit
state machine. Each new feature adds another boolean and another matrix of possible states.

**Symptoms:**
- A flag is cleared before checking it (order-dependent bugs)
- `if (a && !b && c)` conditions that nobody can reason about
- "Zombie" states where an entity exists in one data structure but is invalid in another
- The same state check duplicated with slight variations across files

**Fix:** Replace boolean combinations with an explicit lifecycle enum:
```typescript
type SessionState = 'idle' | 'connecting' | 'authenticating' | 'connected'
  | 'soft_disconnected' | 'reconnecting' | 'failed' | 'closed';
```

All transition logic goes through a single `transition(from, to)` function.
UI reads the state directly instead of inferring it.

## Server↔client contracts need sync checks

When server and client share a message protocol (WebSocket message types, REST endpoints),
add an automated sync check script that verifies both sides define the same types.

**Pattern:** Extract type names from both codebases with grep, diff them, fail the gate
if they diverge. Mark sync points in code with comments (`[SERVER_MESSAGE]`, `[SFTP_MSG]`)
so the script knows where to look.

Non-1:1 patterns (streaming with meta/chunk/end) need the check to understand the
relationship, not just assume `handler → handler_result`.
