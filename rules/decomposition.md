# Decomposition Patterns

## Sequential decomposition for coupled refactors

When a large change touches shared state across many files, decompose into sequential
steps where each is bot-sized and independently testable.

**Pattern from multi-session isolation (220+ refs across 11 files):**
1. Part A: Create the new abstraction alongside the old (additive, no breaking changes)
2. Part B: Migrate consumers from old to new (bulk mechanical change, existing tests verify)
3. Part C: Verify routing/integration (test-only, confirms B didn't break anything)

Each part merges to main before the next starts. This ensures:
- Each PR is reviewable (not a 500-line monster)
- Tests pass at every step
- If Part B breaks something, the blast radius is contained
- Bot agents can handle each part independently

## When to decompose

- >200 lines of change → decompose
- >5 files → decompose
- Shared state migration → always decompose (A: new, B: migrate, C: verify)
- Multiple independent concerns → parallelize, don't sequence

## Anti-patterns

- Don't decompose into steps that can't be merged independently
- Don't decompose so fine-grained that the overhead exceeds the work
- Don't sequence independent changes — parallelize them
