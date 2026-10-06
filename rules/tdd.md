# TDD

The orchestrator owns the cycle; tests are written from the spec by a separate agent, so they test intended behavior, not the implementation just written.

1. Red: `/write-tests N` writes tests from the issue spec and confirms they fail.
2. Green: `/develop N` implements until they pass. It may fix a wrong test; it doesn't add net-new tests.

`/spec-develop N` runs spec → red → green in one pipeline. Repos may declare a variant in `AGENTS.md` (e.g. spec → red → green → device, using the `device` gate tier from `gates.md`); follow the repo's.

- Merge test-only PRs with `gh-ops.sh pr-merge`, not `integrate` (which closes the issue).
- Skip red when existing coverage already pins the behavior (pure refactor), for visual-only changes, or for script/infra fixes where the gate is the test.
