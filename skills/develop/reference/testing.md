# Testing Pitfalls

Run tests through the repo's declared gate tiers (`${CLAUDE_PLUGIN_ROOT}/rules/gates.md`), fast tier first.

- Test behavior the user or caller observes, not implementation details.
- Reset shared state between tests; tests must pass in any order.
- No real network calls in unit tests; mock the transport.
- Stub globals or environment before importing the module under test.
- Reuse the repo's fixtures and helpers; never duplicate mock server setup.
- Never force a click or interaction; an element that needs forcing is not actually reachable.
- Never raise timeouts or add sleeps to make a test pass; fix the timing issue.
- Never modify frozen baseline tests to make them pass.
- Bug fixes get a regression test that fails before the fix.
- Features get a smoketest (reachable) plus behavior tests (works).
- Style-only changes: verify visibility or layout, no unit test.
- A failure on one platform or browser but not another is usually a real bug, not flake.
- Outdated is not flaky: tests broken by an intended behavior change need updated assertions.
