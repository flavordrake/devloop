---
name: release
description: Use when the user says "release", "tag a release", "cut a release", "bump version", "ship it", "publish", or "/release". Handles version bumping, changelog generation, validation, tagging, and GitHub release creation.
---

# Release

Labels and conventions come from `.claude/process.md`; gate tiers from
`${CLAUDE_PLUGIN_ROOT}/rules/gates.md`.

## 1. Version file

Use the version file declared in process.md. Otherwise probe in order and use the
first found: `pubspec.yaml`, `Cargo.toml`, `pyproject.toml`, `package.json`,
`build.gradle.kts`, `build.gradle`, `platformio.ini`. None found, or several that
disagree: ask the user.

## 2. Next version

```bash
git describe --tags --abbrev=0
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Semver: patch for fixes only; minor for features, refactors, new tooling; major for
breaking changes to public protocols, data formats, or deployment. Pre-1.0, minor is the norm.

## 3. Changelog

Group commits since the last tag by prefix: `feat` Features, `fix` Bug Fixes,
`refactor` Refactoring, `test` Testing, `chore`/`build`/`docs` Maintenance,
`security` Security. Skip merge commits. Include issue numbers; group related work
rather than listing every commit.

## 4. Validate

Run the `ship` tier (fall back to `full` if `ship` is not declared), and the
`device` tier if declared and a lease is available. Do not tag on any failure: fix,
commit, re-run.

## 5. Doc parity (required)

Run the doc-parity skill; release is blocked on unresolved drift.

## 6. Security review

Read `${CLAUDE_PLUGIN_ROOT}/rules/security.md`, then run `/security-review` against
the changes since the last tag. For each finding:
1. Deduplicate overlapping findings.
2. Verify by reading the cited file and line; drop anything not real given the architecture.
3. Classify: critical/high and medium get `bug` + `security`; low gets `chore` + `security`, batched into one issue or dropped as noise.
4. File each with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-file-issue.sh`, title `security: <brief>`, body with the analysis, verified location, and fix.

Critical or high findings block the tag unless the user accepts the risk. No real
findings: note "clean security review" in the release notes.

## 7. Bump, commit, tag

Update the version file, then:
```bash
git add <version file>
git commit -m "release: v{VERSION}"
git tag -a "v{VERSION}" -m "<full changelog section>"
```
Never amend a release commit; fix forward with a new patch release.

## 8. Close fixed issues

For each issue referenced in the changelog that is still open and fully fixed:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh close N --comment "Fixed in v{VERSION} ({SHA})"
${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh labels N --rm bot --rm divergence --add "v{VERSION}"
```
`gh-ops.sh labels` cannot create labels, so create the version label once first
(no wrapper exists for this): `gh label create "v{VERSION}" --color 0E8A16`.
Partially fixed issues stay open with a progress comment.

## 9. Push and publish

Show `git log origin/main..HEAD --oneline` and the new tag, and ask before pushing.
Then:
```bash
git push origin main --follow-tags
${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh release "v{VERSION}" --notes-file <changelog file>
```
If process.md declares a post-release deploy or verification step, run it.

## TRACE

Releases always get a TRACE: contents, bump rationale, known risks; pivots when
validation, doc parity, or security review blocks; outcome with what shipped, what
was held back, and a knowledge seed.
