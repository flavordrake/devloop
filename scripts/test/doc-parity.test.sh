#!/usr/bin/env bash
# Tests for skills/doc-parity/scripts/{doc-parity,docs-to-code,code-to-docs}.sh
# against scratch git repos: a consistent fixture passes, each drift kind in
# each direction is reported with its location, waivers, boundaries, modes.
# Usage: scripts/test/doc-parity.test.sh   (exit 0 = all pass)
set -euo pipefail

S="$(cd "$(dirname "$0")/../.." && pwd)/skills/doc-parity/scripts"
# A git hook exports these; a scratch repo that inherits them writes into the
# caller's repo (a fixture once flipped core.bare on the shared repo).
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
T="$(mktemp -d -t doc-parity-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

# make_repo DIR: a small consistent repo (shell CLI, python server, a hook).
make_repo() {
  local d="$1"
  mkdir -p "$d/scripts/test" "$d/src" "$d/docs/reviews" "$d/docs/research" "$d/.claude"
  printf '#!/usr/bin/env bash\n# Usage: scripts/build.sh run|clean\nMODE="${APP_MODE:-dev}"\ncase "$1" in\n  run) echo "$MODE" ;;\n  clean) scripts/hook.sh ;;\n  -h|--help) exit 0 ;;\nesac\n' > "$d/scripts/build.sh"
  printf '#!/usr/bin/env bash\necho hook\n' > "$d/scripts/hook.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/test/a.test.sh"
  printf 'import os\nMODE = os.environ.get("APP_MODE")\nROUTES = ["/api/items"]\n' > "$d/src/server.py"
  printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "scripts/hook.sh"}]}]}}\n' > "$d/.claude/settings.json"
  printf '## Doc surfaces\n- env-prefix: APP_\n- code: *.sh src/*.py\n' > "$d/.claude/process.md"
  cat > "$d/README.md" <<'EOF'
# Fixture

Build with `scripts/build.sh run` or `build.sh clean`; the Stop hook runs hook.sh.
Set `APP_MODE`. The server answers `GET /api/items/<id>` from `src/server.py`.
Tests live in `scripts/test/`.
EOF
  (cd "$d" && git init -q && git add -A)
}

# run DIR SCRIPT ARGS...: run a checker from inside DIR, output to $T/out.
run() { local d="$1" s="$2"; shift 2; (cd "$d" && "$S/$s" "$@") > "$T/out" 2>&1; }

# expect_find LABEL DIR SCRIPT PATTERN: block mode exits 1 and prints PATTERN.
expect_find() {
  if run "$2" "$3" --block; then fail "$1: exit 0, expected 1: $(cat "$T/out")"
  elif grep -qE "$4" "$T/out"; then pass "$1"
  else fail "$1: no /$4/ in: $(cat "$T/out")"; fi
}
expect_clean() {
  if run "$2" "$3" --block; then pass "$1"; else fail "$1: $(cat "$T/out")"; fi
}

R="$T/clean"; make_repo "$R"
expect_clean "consistent repo passes both directions" "$R" doc-parity.sh

# Docs to code.
R="$T/d2c"; make_repo "$R"
printf 'Run `scripts/ghost.sh`, `phantom.py`, set `APP_GHOST`.\nCall `scripts/build.sh teleport` or `POST /api/ghosts`.\n' >> "$R/README.md"
if run "$R" docs-to-code.sh --block; then fail "docs-to-code drift: exit 0, expected 1"; fi
for p in '^MISSING path scripts/ghost\.sh README\.md:6$' '^MISSING script phantom\.py README\.md:6$' \
         '^MISSING env APP_GHOST README\.md:6$' '^MISSING cli build\.sh teleport README\.md:7$' \
         '^MISSING route /api/ghosts README\.md:7$'; do
  if grep -qE "$p" "$T/out"; then pass "docs-to-code $p"; else fail "docs-to-code $p: $(cat "$T/out")"; fi
done

# Boundaries: none of these are claims.
R="$T/bound"; make_repo "$R"
printf 'See build.sha256, https://example.com/scripts/x.sh, $HOME/scripts/y.sh, ~/scripts/z.sh.\nUse `scripts/*.sh` and `scripts/<name>.sh`; mobissh docs/other.md is theirs.\n' >> "$R/README.md"
printf -- '- siblings: mobissh\n' >> "$R/.claude/process.md"
expect_clean "boundary tokens (.sha256, URL tail, \$VAR, ~, glob, placeholder, sibling) are not claims" "$R" docs-to-code.sh

# Records make no claims; research makes no env/route/cli claims.
R="$T/rec"; make_repo "$R"
printf 'Codex said scripts/hallucinated.sh exists.\n' > "$R/docs/reviews/2026-01-01.md"
printf 'Other tools read APP_FOREIGN and serve GET /v9/x.\n' > "$R/docs/research/tool.md"
(cd "$R" && git add -A)
expect_clean "records and research identifiers are skipped" "$R" docs-to-code.sh
printf 'It lives at scripts/gone.sh.\n' >> "$R/docs/research/tool.md"
expect_find "research path claims are still checked" "$R" docs-to-code.sh '^MISSING path scripts/gone\.sh docs/research/tool\.md:2$'

# Code to docs.
R="$T/c2d"; make_repo "$R"
printf '#!/usr/bin/env bash\n# Usage: scripts/secret.sh\ncase "$1" in\n  frob) echo "${APP_HIDDEN:-x}" ;;\nesac\n' > "$R/scripts/secret.sh"
printf 'import os\nos.environ.get("APP_ALSO")\n' > "$R/src/extra.py"
(cd "$R" && git add -A)
if run "$R" code-to-docs.sh --block; then fail "code-to-docs drift: exit 0, expected 1"; fi
for p in '^UNDOCUMENTED file scripts/secret\.sh scripts/secret\.sh:1$' '^UNDOCUMENTED file src/extra\.py ' \
         '^UNDOCUMENTED env APP_HIDDEN scripts/secret\.sh:4$' '^UNDOCUMENTED env APP_ALSO src/extra\.py:2$' \
         '^UNDOCUMENTED cli secret\.sh frob scripts/secret\.sh:4$'; do
  if grep -qE "$p" "$T/out"; then pass "code-to-docs $p"; else fail "code-to-docs $p: $(cat "$T/out")"; fi
done
if grep -q 'called scripts/secret.sh' "$T/out"; then fail "a usage line is not a call"; else pass "a script's own usage line is not a call"; fi

R="$T/called"; make_repo "$R"
sed 's/the Stop hook runs hook.sh/the Stop hook runs a hook/' "$R/README.md" > "$R/README.md.new"
mv "$R/README.md.new" "$R/README.md"
expect_find "a hook-called script no doc names" "$R" code-to-docs.sh '^UNDOCUMENTED called scripts/hook\.sh (\.claude/settings\.json|scripts/build\.sh):[0-9]+$'

# Without env-prefix, getenv-style reads are the env surfaces.
R="$T/noprefix"; make_repo "$R"
printf '## Doc surfaces\n- code: *.sh\n' > "$R/.claude/process.md"
printf 'const p = process.env.PORT_KNOB;\n' > "$R/src/app.ts"
(cd "$R" && git add -A)
expect_find "process.env read without a prefix" "$R" code-to-docs.sh '^UNDOCUMENTED env PORT_KNOB src/app\.ts:1$'

# Waivers: a justified entry suppresses, an unjustified one is a finding.
R="$T/waive"; make_repo "$R"
printf 'Planned: `scripts/later.sh`.\n' >> "$R/README.md"
printf '# planned in #12 (2026-10-06); remove when it lands\npath:scripts/later.sh\n' > "$R/.claude/doc-parity-ignore.txt"
(cd "$R" && git add -A)
expect_clean "a justified waiver suppresses the claim" "$R" docs-to-code.sh
printf '\nscripts/other.sh\n' >> "$R/.claude/doc-parity-ignore.txt"
expect_find "an unjustified waiver is a finding" "$R" docs-to-code.sh '^UNJUSTIFIED waiver scripts/other\.sh \.claude/doc-parity-ignore\.txt:4$'

# Modes, and a GIT_DIR inherited from a hook must not redirect the file list.
R="$T/modes"; make_repo "$R"
printf 'Run `scripts/ghost.sh`.\n' >> "$R/README.md"
if run "$R" doc-parity.sh --warn && grep -q '^MISSING path scripts/ghost.sh' "$T/out"; then pass "--warn reports and exits 0"; else fail "--warn: $(cat "$T/out")"; fi
if (cd "$R" && GIT_DIR="$T/clean/.git" "$S/docs-to-code.sh") > "$T/out" 2>&1; then fail "GIT_DIR leak: $(cat "$T/out")"
elif grep -q 'scripts/ghost.sh' "$T/out"; then pass "an inherited GIT_DIR is ignored"; else fail "GIT_DIR: $(cat "$T/out")"; fi
if run "$R" docs-to-code.sh --kinds env; then pass "--kinds env skips path claims"; else fail "--kinds: $(cat "$T/out")"; fi
if run "$R" doc-parity.sh --list docs && grep -qx 'README.md' "$T/out" && ! grep -q 'reviews' "$T/out"; then pass "--list docs"; else fail "--list docs: $(cat "$T/out")"; fi

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "all doc-parity cases passed"
