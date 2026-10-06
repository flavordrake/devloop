#!/usr/bin/env bash
# skills/doc-parity/scripts/code-to-docs.sh: every code surface must be named in
# a doc (doc-parity skill, layer a, direction code to docs). Surface kinds:
#   called  a path the system calls: named by .claude/settings.json, hooks.json,
#           hooks/, .claude/hooks/, .githooks/, .github/workflows/, package.json,
#           Makefile, justfile, or any shell script (a script's own usage line
#           is not a call; a mention of a path that does not exist is dropped)
#   file    every file matching the `code` globs (default *.sh)
#   env     with env-prefix: every prefixed word in non-test code; without:
#           variables read via getenv-style calls (sh ${X:-}, os.environ,
#           process.env, Platform.environment, System.getenv, env::var, ...)
#   cli     every enumerable subcommand (lib.sh dp_subcommands)
# A file is documented by its path, its file name, or a doc directory token
# (`scripts/test/`) above it. Prints `UNDOCUMENTED <kind> <value> <code>:<line>`.
# Usage: code-to-docs.sh [--warn|--block] [--kinds k1,k2] [--root DIR] [--config FILE]
#   --block (default) exits 1 on findings; --warn always exits 0.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
rc=0; dp_args "$@" || rc=$?
if [[ "$rc" -eq 3 ]]; then sed -n '2,17p' "$0"; exit 0; fi
if [[ "$rc" -ne 0 ]]; then exit "$rc"; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/doc-parity-c2d.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
dp_init "$WORK" "$CONFIG"

# Env vars a test invents for its own cases are not surfaces.
TEST_RE='(^|/)(test|tests|__tests__|spec|integration_test)/|(_test|\.test|\.spec)\.[A-Za-z]+$|(^|/)test_[^/]*\.py$'

surfaces() {
  # called: path-shaped tokens in the call sites, resolved against the root and
  # the calling file's own directory; only paths that exist count.
  awk -v t="$TEST_RE" '
    $0 ~ /^(\.claude\/settings\.json|hooks\.json|package\.json|Makefile|justfile)$/ ||
    $0 ~ /^(hooks|\.claude\/hooks|\.githooks|\.github\/workflows)\// || $0 ~ /\.(sh|bash)$/' "$WORK/code" > "$WORK/callers"
  if [[ -s "$WORK/callers" ]]; then
    tr '\n' '\0' < "$WORK/callers" | xargs -0 awk -v filelist="$WORK/files" '
      BEGIN { while ((getline l < filelist) > 0) f[l] = 1 }
      FNR == 1 { dir = FILENAME; if (!sub(/\/[^\/]*$/, "", dir)) dir = "" }
      {
        rest = $0
        while (match(rest, /[A-Za-z0-9_.\/-]*[A-Za-z0-9_-]\.(sh|bash|py|mjs|dart|rb|pl)/)) {
          tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
          if (rest ~ /^[A-Za-z0-9_]/) continue
          hit = ""
          for (c = tok; c != ""; ) {
            sub(/^\.\//, "", c)
            if (c in f) { hit = c; break }
            if (dir != "" && ((dir "/" c) in f)) { hit = dir "/" c; break }
            if (!sub(/^[^\/]*\//, "", c)) break
          }
          if (hit != "" && hit != FILENAME) print "called\t" hit "\t" FILENAME ":" FNR
        }
      }'
  fi
  awk -v g="$DP_CODE" "$DP_AWK_GLOB"'anyglob($0, g) { print "file\t" $0 "\t" $0 ":1" }' "$WORK/files"
  awk -v t="$TEST_RE" '$0 !~ t' "$WORK/code" > "$WORK/code-no-tests"
  if [[ -n "$DP_ENV_PREFIX" ]]; then
    for p in $DP_ENV_PREFIX; do
      dp_xgrep "$WORK/code-no-tests" -noHIE "[A-Za-z0-9_]*${p}[A-Z0-9_]*[A-Z0-9]" \
        | awk -v p="$p" '{ v = $0; sub(/^[^:]*:[0-9]+:/, "", v); if (index(v, p) != 1 || v == p) next
            loc = $0; sub(/:[^:]*$/, "", loc); print "env\t" v "\t" loc }'
    done
  else
    dp_xgrep "$WORK/code-no-tests" -noHIE \
      "(environ\.get|environ\[|getenv|env::var|env!|option_env!|Getenv|environment\[|fromEnvironment)\(? *['\"][A-Z][A-Z0-9_]*['\"]|process\.env\.[A-Z][A-Z0-9_]*|process\.env\[['\"][A-Z][A-Z0-9_]*" \
      | awk '{ loc = $0; sub(/:[0-9]+:.*/, "", loc); ln = $0; sub(/^[^:]*:/, "", ln); sub(/:.*/, "", ln)
          v = $0; sub(/^[^:]*:[0-9]+:/, "", v); if (match(v, /[A-Z][A-Z0-9_]*[A-Z0-9]['\''"]?$/)) { v = substr(v, RSTART); gsub(/['\''"]/, "", v); print "env\t" v "\t" loc ":" ln } }'
    dp_grep -E '\.(sh|bash)$' "$WORK/code-no-tests" > "$WORK/sh-no-tests"
    # Shell: ${X:-default} read in a file that never assigns X itself (the knob
    # idiom X="${X:-d}" refers to itself and still counts as a read).
    if [[ -s "$WORK/sh-no-tests" ]]; then
      tr '\n' '\0' < "$WORK/sh-no-tests" | xargs -0 awk '
        function flush(  v) { for (v in rd) if (!(v in asg)) print "env\t" v "\t" rd[v]; delete rd; delete asg }
        FNR == 1 && NR > 1 { flush() }
        {
          if (match($0, /^[[:space:]]*(export[[:space:]]+|local[[:space:]]+|readonly[[:space:]]+|declare[[:space:]]+(-[a-zA-Z]+[[:space:]]+)?)?[A-Z][A-Z0-9_]*=/)) {
            a = substr($0, RSTART, RLENGTH - 1); sub(/.*[[:space:]]/, "", a)
            if (index($0, "${" a) == 0) asg[a] = 1
          }
          rest = $0
          while (match(rest, /\$\{[A-Z][A-Z0-9_]*:?[-=?]/)) {
            v = substr(rest, RSTART + 2, RLENGTH - 2); sub(/[:=?-]+$/, "", v); rest = substr(rest, RSTART + RLENGTH)
            if (!(v in rd)) rd[v] = FILENAME ":" FNR
          }
        }
        END { flush() }'
    fi
  fi
  dp_subcommands "$WORK/code-no-tests" | awk -F'\t' '{ print "cli\t" $1 " " $2 "\t" $3 }'
}
# Variables the OS, CI, Claude Code or a well-known toolchain set are not this
# project's knobs.
surfaces | awk -F'\t' '$1 != "env" || $2 !~ /^(HOME|PATH|USER|TMPDIR|PWD|SHELL|TERM|LANG|CI|EDITOR|PAGER|HOSTNAME|ANDROID_HOME|ANDROID_SDK_ROOT|JAVA_HOME|APKSIGNER|PUB_CACHE|FLUTTER_ROOT|PYTHONPATH|VIRTUAL_ENV|NODE_ENV|(CLAUDE|GITHUB|RUNNER|XDG|LC|CARGO)_.*)$/' > "$WORK/surfaces"

# What the docs name: path-ish tokens (and their file names), words, backtick
# words, and `tool.sh sub` pairs.
if [[ -s "$WORK/docs" ]]; then tr '\n' '\0' < "$WORK/docs" | xargs -0 cat > "$WORK/blob"; else : > "$WORK/blob"; fi
dp_ignores > "$WORK/ignores"
dp_ignore_check > "$WORK/findings"

awk -F'\t' -v kinds="$KINDS" -v countfile="$WORK/checked" "$DP_AWK_GLOB"'
  FILENAME == ARGV[1] {
    rest = $0
    while (match(rest, /[A-Za-z0-9_.\/-]+/)) {
      t = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
      sub(/^\.\//, "", t); sub(/[.,:]+$/, "", t); tok[t] = 1; b = t; sub(/.*\//, "", b); if (b != "") base[b] = 1
      # `src/` in `src/*.py` or `src/<name>` is a pattern, not a directory claim.
      if (t ~ /\/$/ && rest !~ /^[*<{]/) dirtok[t] = 1
    }
    rest = $0; while (match(rest, /[A-Za-z0-9_]+/)) { word[substr(rest, RSTART, RLENGTH)] = 1; rest = substr(rest, RSTART + RLENGTH) }
    rest = $0; while (match(rest, /`[^`]+`/)) { s = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
      while (match(s, /[A-Za-z0-9_-]+/)) { bw[substr(s, RSTART, RLENGTH)] = 1; s = substr(s, RSTART + RLENGTH) } }
    rest = $0; while (match(rest, /[A-Za-z0-9_-]+\.(sh|bash) +[a-z][a-z0-9_-]*/)) { p = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH); gsub(/ +/, " ", p); pair[p] = 1 }
    next
  }
  FILENAME == ARGV[2] { ign[++ni] = $0; next }
  {
    if (kinds != "" && index("," kinds ",", "," $1 ",") == 0) next
    # A called path is also a file: report it once, as called.
    key = ($1 == "file" || $1 == "called") ? "f\t" $2 : $1 "\t" $2
    if (key in seen) next
    seen[key] = 1; checked++
    kind = $1; v = $2; skip = 0
    for (j = 1; j <= ni; j++) {
      e = ign[j]
      if (e ~ /^(path|script|env|cli|route|file|called):/) {
        if ((kind ":" v) ~ g2re(e) || (kind == "called" && ("file:" v) ~ g2re(e))) skip = 1
      } else if (v ~ g2re(e)) skip = 1
    }
    if (skip) next
    if (kind == "file" || kind == "called") {
      b = v; sub(/.*\//, "", b); ok = (v in tok) || (b in base)
      if (!ok) for (d in dirtok) if (index(v, d) == 1) { ok = 1; break }
    } else if (kind == "env") ok = (v in word)
    else if (kind == "cli") {
      tool = v; sub(/ .*/, "", tool); s = v; sub(/.* /, "", s)
      ok = tool ~ /\.(sh|bash)$/ ? (v in pair) : (s in bw)
    }
    if (!ok) print "UNDOCUMENTED " kind " " v " " $3
  }
  END { print checked + 0 > countfile }' "$WORK/blob" "$WORK/ignores" "$WORK/surfaces" >> "$WORK/findings"

dp_report code-to-docs "$WORK/findings" "$(cat "$WORK/checked")" "surface(s)" "$MODE"
