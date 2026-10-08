---
name: doc-parity
description: Use when the user says "doc parity", "doc drift", "docs vs code", "pre-release docs check", "pre-release", or before any release or tag. Compares docs to code and code to docs in any devloop project (TS, Flutter, Kotlin, Python, Rust, C, shell/docs) - a mechanical script pass both ways, an agent audit of every feature claim and of undocumented code, and an optional external design review - and resolves every finding line by line.
---

# Doc parity

Every devloop project keeps its docs and its code saying the same thing. Two directions, both required:

- **Docs to code**: everything a doc claims exists and behaves as stated. Catches promised-but-unbuilt features and stale names.
- **Code to docs**: everything the system ships or calls is named in a doc. Catches undocumented scripts, knobs, subcommands and dead code.

Run it before every release (blocking) and in the fast gate (warning). Nothing found is dropped silently: each finding is fixed in code, fixed in docs, waived with a reason, or filed.

## Layers

1. **Mechanical** (script, both directions). Paths, script names, env vars, CLI subcommands, routes. Cheap, deterministic, gate-able.
2. **Semantic** (agent audit). Every feature and behaviour claim checked against code, including user-facing text shipped in code; every undocumented reachable surface checked for reachability. Pre-release only. The real misses are here: the script only sees names.
3. **External design review** (optional). A second model (e.g. codex) reviews design and correctness. Spends the owner's quota: run only on the owner's go, never in a gate.

## Layer 1: mechanical

Scripts operate on the git toplevel of the current directory:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/doc-parity/scripts/doc-parity.sh" --block   # both directions, exit 1 on findings
"${CLAUDE_PLUGIN_ROOT}/skills/doc-parity/scripts/doc-parity.sh" --warn    # fast gate: report, exit 0
"${CLAUDE_PLUGIN_ROOT}/skills/doc-parity/scripts/docs-to-code.sh" --kinds path,script
"${CLAUDE_PLUGIN_ROOT}/skills/doc-parity/scripts/code-to-docs.sh" --kinds called,file
```

Options: `--warn|--block` (default block), `--kinds k1,k2`, `--root DIR`, `--config FILE` (alternate config file). `doc-parity.sh --list docs|research|code|user-text` prints the inputs for layer 2.

Without Claude Code (a plain shell, a Codex, opencode or pi session, a cron job), there is no `${CLAUDE_PLUGIN_ROOT}`; resolve devloop with `devloop-path.sh` and run from the repo:

```bash
"$(devloop-path.sh)/skills/doc-parity/scripts/doc-parity.sh" --block
DEVLOOP_ROOT=~/workspace/devloop "$DEVLOOP_ROOT/skills/doc-parity/scripts/doc-parity.sh" --block   # a checkout instead of the plugin cache
```

The scripts need only bash, git, awk and grep. Config is read from the repo's `AGENTS.md` (`## Doc surfaces`), which Codex, opencode and pi load natively, so a non-Claude session finds the same configuration with no extra wiring. Layer 2 below is harness-neutral prose: any agent that can read files follows it.

Docs to code (`MISSING <kind> <value> <doc>:<line> (+N more)`):

- `path`: a repo path under a top-level directory (file with extension, or `dir/`) exists. A path relative to the naming doc's directory also resolves.
- `script`: a bare `<name>.sh|.bash|.py|.mjs` matches some file name.
- `env`: a word with the project env prefix appears in code.
- `cli`: `` `<tool>.sh <sub>` `` (backticks or code fence) is a subcommand the script dispatches; `<tool>.sh {a|b}` and `<tool>.sh <a|b>` claim each alternative.
- `route`: `GET|POST|PUT|DELETE|PATCH /x/y` has its static part in code.

Code to docs (`UNDOCUMENTED <kind> <value> <code>:<line>`):

- `called`: a path the system calls (`.claude/settings.json`, `hooks.json`, `hooks/`, `.claude/hooks/`, `.githooks/`, `.github/workflows/`, `package.json`, `Makefile`, `justfile`, any shell script, or an `ExecStart=` or `curl ... | sh` line in any code file) is named in a doc. `dart tools/x.dart` or `python tools/x.py` in a script makes `tools/x.dart` called.
- `file`: every file matching the `code` globs is named in a doc.
- `env`: prefixed words in non-test code, or (no prefix) getenv-style reads: sh `${X:-}` (not self-assigned), `os.environ`, `process.env`, `Platform.environment`/`fromEnvironment`, `System.getenv`, `env::var`, `os.Getenv`, `getenv`. OS, CI and toolchain variables (`HOME`, `PATH`, `CI`, `JAVA_HOME`, `ANDROID_HOME`, `NODE_ENV`, `GITHUB_*`, `CARGO_*`, ...) are never surfaces.
- `cli`: subcommands found by cheap heuristics: top-level sh `case "$1"|"$cmd"...` arms (a one-line arm that only forwards `"$@"` to another command, `build) exec flutter "$@" ;;`, is a pass-through and not counted), argparse `add_parser`, click/commander `command(`, Dart `addCommand`, clikt `name =`. A doc's `<tool>.sh {a|b}` or `<tool>.sh <a|b>` documents each alternative.

A file counts as documented by its full path, its file name, or a directory token above it (`scripts/test/`, `tools/`, `docs/specs/` cover everything under them, which keeps waivers small).

Sibling repos: `~/workspace/<repo>/...` and `../<repo>/...` are never claims, calls or documentation of this repo; `siblings` covers prose like `mobissh docs/x.md`.

`UNJUSTIFIED waiver <entry> <file>:<line>` means an ignore entry has no comment above it.

### Repo configuration

In `AGENTS.md` at the repo root (legacy fallback: `.claude/process.md` when `AGENTS.md` has no `## Doc surfaces`), one bullet per key (values replace the defaults; globs: `*` crosses `/`, `**/` is any depth, trailing `/` is a directory):

```markdown
## Doc surfaces
- env-prefix: MYAPP_
- code: *.sh app/lib/*.dart packages/*/src/*
- records: docs/reviews/
- research: docs/research/
- exclude: test-history/ .claude/rules/devloop/
- include: docs/*.txt
- siblings: mobissh opsurface
- ignore: .claude/doc-parity-ignore.txt
- user-text: web/*.html assets/legal/*
```

Defaults: no env prefix (getenv heuristics), `code: *.sh`, `records: docs/reviews/`, `research: docs/research/`, `ignore: .claude/doc-parity-ignore.txt`. Docs are every tracked `*.md` except records, changelogs/release notes, fixtures and `.claude/` internals (only `.claude/{rules,agents,skills}/` and legacy `.claude/process.md` count). Research docs make path and script claims only. `siblings` names other projects whose paths docs quote (`mobissh docs/x.md`). `user-text` lists user-facing text shipped in code for layer 2.

Ignore file: `kind:glob` (or a bare glob for any kind), one per line, a comment above each entry or block saying why (planned in #N with a date, a foreign path, an internal helper no reader needs). Remove an entry when its item lands.

### Migrating a repo doc-drift script

A repo-local two-way check (e.g. opsurface's doc-drift script) maps on directly:

- CALLED-BUT-UNDOCUMENTED is `UNDOCUMENTED called|file`; DOCUMENTED-BUT-MISSING is `MISSING path|script`.
- Hard-coded entrypoints (installer scripts, `tools/<x>/bin/*.dart`) become `code` globs.
- A lookbehind for a sibling repo name becomes `siblings`.
- The ignore file keeps its format: bare globs (`*` crosses `/`) waive any kind, a comment above each entry or block. Point `ignore:` at the old file, or move it; prefix `path:` to waive one direction only. Bash `[...]` classes are not supported. Entries the sibling rules now cover can go.

## Layer 2: semantic audit

Pre-release, an agent (or the orchestrator) reads every doc from `--list docs` plus every file from `--list user-text` (privacy pages, store listings, onboarding, help and error strings served from code) and:

1. **Claims**: lists each feature or behaviour claim (what the product does, platforms, install channels, limits, retention, security properties) and verifies it at a code line. Unbacked claims are removed or marked planned.
2. **Undocumented code**: for each surface layer 1 reported undocumented (and code areas no doc mentions), checks reachability. Reachable user features go in the user doc (README); build/debug/dev features go in the developer doc; unreachable code goes on a removal list (a release blocker until removed or the owner keeps it).
3. **Report**: a table, one row per claim, in the PR or `docs/reviews/<date>-doc-parity.md`:

```markdown
| claim | doc:line | verdict | evidence (code:line) |
|---|---|---|---|
| Pinch to zoom the font | README.md:42 | false, removed | no pinch handler; font size in settings_panel.dart:137 |
```

Verdicts: implemented, false (removed or built), stale (fixed), undocumented (added), dead (removal list), planned (marked).

## Layer 3: external design review

On the owner's go only. Write `docs/reviews/<date>-response.md` with one line per finding id, each exactly one of: `fixed in #<PR>` (name the covering test), `filed as #<issue>`, `rebutted: <reason with code line or doc section>`. Critical and high rebuttals go to the owner. Count response lines against findings: equal, or the layer is not done. A part that returned no review is re-run, never reported clean.

## Resolving findings

For each finding, one of:

- **Fix code**: the doc is right and the code never shipped it (build it, or file it and fix the doc).
- **Fix docs**: make the doc say what ships; name the thing where a reader would look.
- **Waive**: an ignore entry with a one-line reason. Never to make the exit 0 over a real gap.
- **File**: real but not for this release, via `/issue`; mark the doc claim planned or waive it with the issue number.

Then re-run layer 1: new doc lines are new claims. Repeat until both directions exit 0.

## Pass bar

- `doc-parity.sh --block` exits 0 (both directions, no unjustified waivers).
- Every layer 2 claim has a verdict with evidence; the removal list is empty or owner-approved.
- Layer 3, if run, has a response line per finding.

## Gate wiring

- CI (no plugin installed): `uses: flavordrake/devloop/.github/actions/setup@<full commit sha>` (a tag is a mutable convenience), then `"$DEVLOOP_ROOT/skills/doc-parity/scripts/doc-parity.sh" --block`.
- No Claude Code (Codex, opencode, pi, a shell): `"$(devloop-path.sh)/skills/doc-parity/scripts/doc-parity.sh" --block`, as above.
- Fast gate: `doc-parity.sh --warn` (or `--block --kinds path,script,called` once a repo is clean).
- Ship / release: `doc-parity.sh --block`, then layer 2 before the tag.
- Repo-specific checks stay in the repo (e.g. a coverage-map check that every spec has a coverage row).

## Traps

- Design proposals read as broken promises: mark them planned in the doc, or waive by path with the spec/issue and date.
- Research docs quote other tools' identifiers: keep them under `research`.
- Review records quote hallucinated paths: keep them under `records`, or every one is a finding forever.
- Word boundaries: `.sh` inside `.sha256`, URL tails (`https://x/docs/a.md`), `$VAR/x`, `~/x`, `scripts/*.sh` and `scripts/<name>.sh` are not claims; the scripts already skip them, keep it that way when extending.
- A script's own usage line is not a call; a mention of a non-existent path in code is a comment, not a call.
- Stale code comments naming deleted files slip past layer 1; layer 2 catches them.
- Exclude test-only env vars (tests are skipped for `env`); a CI or OS variable is not a project knob.
- Local runs also scan untracked, non-ignored files, so local counts can exceed CI. Without an `env-prefix`, getenv heuristics flag every knob; set the prefix before triaging a large `env` count.
- Test fixtures that create scratch git repos MUST `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE` first: under a git hook they otherwise write into the caller's repo (one flipped `core.bare` on a shared repo).
- Paths only is not parity: the costly misses (an unbuilt feature, a privacy promise living in served HTML, a self-update claim false for one install channel) are semantic.
