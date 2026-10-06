#!/usr/bin/env bash
# skills/doc-parity/scripts/lib.sh: shared by docs-to-code.sh and code-to-docs.sh.
# Resolves the repo root, reads the `## Doc surfaces` section of
# .claude/process.md, and writes the file lists both directions compare.
# Portable: bash 3.2, POSIX awk, BSD or GNU grep/sed (no -P, no mapfile, no
# associative arrays, no find -printf, no xargs -d).

# dp_grep: grep where "no match" is an empty result, not a failure under
# set -euo pipefail (the one sanctioned `|| true`; real errors still print).
dp_grep() { grep "$@" || true; }

# dp_xgrep <list file> <grep args...>: grep over every file named in the list.
# xargs exits 123 when one batch matched nothing: same exception as dp_grep.
dp_xgrep() {
  local list="$1"; shift
  [[ -s "$list" ]] || return 0
  tr '\n' '\0' < "$list" | { xargs -0 grep "$@" || true; }
}

# Awk helper shared by every program: glob to anchored ERE. `*` crosses `/`,
# `**/` is zero or more directories, a trailing `/` is a directory prefix.
DP_AWK_GLOB='
function g2re(g,   r, i, c, n) {
  r = ""; n = length(g)
  for (i = 1; i <= n; i++) {
    c = substr(g, i, 1)
    if (c == "*" && substr(g, i, 3) == "**/") { r = r "(.*/)?"; i += 2 }
    else if (c == "*") r = r ".*"
    else if (c == "?") r = r "[^/]"
    else if (index(".+()^$|{}[]\\", c)) r = r "\\" c
    else r = r c
  }
  if (substr(g, n) == "/") return "^" r
  return "^" r "$"
}
function anyglob(s, globs,   a, k, m) {
  m = split(globs, a, " ")
  for (k = 1; k <= m; k++) if (a[k] != "" && s ~ g2re(a[k])) return 1
  return 0
}'

# dp_config <file>: print "key<TAB>value" for each `- key: value` bullet in the
# file's `## Doc surfaces` section (backticks stripped).
dp_config() {
  [[ -f "$1" ]] || return 0
  awk '
    /^## / { on = ($0 ~ /^## +Doc surfaces[[:space:]]*$/); next }
    on && /^[-*] +[a-z-]+:/ {
      line = $0; sub(/^[-*] +/, "", line)
      key = line; sub(/:.*/, "", key)
      val = line; sub(/^[a-z-]+:[[:space:]]*/, "", val); gsub(/`/, "", val)
      print key "\t" val
    }' "$1"
}

# dp_init <work dir> [config file]: cd to the git toplevel of the caller's cwd
# (or the --root already cd-ed into), load config, write the lists:
#   files     every tracked or untracked-not-ignored file that exists
#   docs      the markdown that makes claims and documents code
#   research  docs that quote other projects (path/script claims only)
#   code      every other text-ish file (non-markdown, not fixtures)
dp_init() {
  DP_WORK="$1"
  local cfg="${2:-}" top
  # A scratch repo under a git hook must not read the hook's GIT_DIR.
  top="$(unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR; git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cd "$top"
  DP_ROOT="$top"
  [[ -n "$cfg" ]] || cfg=".claude/process.md"

  DP_RECORDS="docs/reviews/"
  DP_RESEARCH="docs/research/"
  DP_ENV_PREFIX=""
  DP_IGNORE=".claude/doc-parity-ignore.txt"
  DP_CODE="*.sh"
  DP_INCLUDE=""
  DP_EXCLUDE=""
  DP_SIBLINGS=""
  DP_USER_TEXT=""
  local key val
  while IFS="$(printf '\t')" read -r key val; do
    case "$key" in
      records) DP_RECORDS="$val" ;;
      research) DP_RESEARCH="$val" ;;
      env-prefix) DP_ENV_PREFIX="$val" ;;
      ignore) DP_IGNORE="$val" ;;
      code) DP_CODE="$val" ;;
      include) DP_INCLUDE="$val" ;;
      exclude) DP_EXCLUDE="$val" ;;
      siblings) DP_SIBLINGS="$val" ;;
      user-text) DP_USER_TEXT="$val" ;;
      *) echo "! doc-parity: unknown key '$key' in $cfg ## Doc surfaces" >&2; return 2 ;;
    esac
  done < <(dp_config "$cfg")

  if (unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR; git rev-parse --git-dir >/dev/null 2>&1); then
    (unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR; git ls-files --cached --others --exclude-standard) > "$DP_WORK/files.raw"
  else
    find . -type f -not -path './.git/*' | sed 's#^\./##' > "$DP_WORK/files.raw"
  fi
  # Generated, vendored and other sessions' trees are never docs or code.
  awk -v ex="$DP_EXCLUDE" "$DP_AWK_GLOB"'
    $0 ~ /^(\.claude\/(worktrees|projects)\/|\.traces\/|\.git\/)/ { next }
    $0 ~ /(^|\/)(node_modules|\.dart_tool|build|target|dist|\.venv|venv|__pycache__|\.gradle|\.pio)\// { next }
    $0 == ".claude/settings.local.json" { next }
    anyglob($0, ex) { next }
    { print }' "$DP_WORK/files.raw" | while IFS= read -r f; do
      if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
    done | sort -u > "$DP_WORK/files"

  # Docs: every *.md except records, changelogs and .claude/ internals (only its
  # rules, agents, skills and process.md are this repo's docs), plus include globs.
  awk -v rec="$DP_RECORDS" -v inc="$DP_INCLUDE" "$DP_AWK_GLOB"'
    anyglob($0, inc) { print; next }
    $0 !~ /\.md$/ { next }
    anyglob($0, rec) { next }
    $0 ~ /(^|\/)(fixtures|test-fixtures|testdata)\// { next }
    $0 ~ /(^|\/)CHANGELOG[^\/]*$|release-notes[^\/]*$/ { next }
    $0 ~ /^\.claude\// && $0 !~ /^\.claude\/(rules|agents|skills)\// && $0 != ".claude/process.md" { next }
    { print }' "$DP_WORK/files" > "$DP_WORK/docs"
  awk -v res="$DP_RESEARCH" "$DP_AWK_GLOB"'anyglob($0, res)' "$DP_WORK/docs" > "$DP_WORK/research"
  # Code: everything else that is not markdown, a record or a fixture.
  awk -v rec="$DP_RECORDS" "$DP_AWK_GLOB"'
    NR == FNR { doc[$0] = 1; next }
    ($0 in doc) || $0 ~ /\.md$/ || anyglob($0, rec) { next }
    $0 ~ /(^|\/)(fixtures|test-fixtures|testdata)\// { next }
    { print }' "$DP_WORK/docs" "$DP_WORK/files" > "$DP_WORK/code"
}

# dp_ignore_check: print one UNJUSTIFIED line per ignore entry that has no
# comment above it (directly, or above the run of entries it belongs to).
dp_ignore_check() {
  local f
  for f in $DP_IGNORE; do
    [[ -f "$f" ]] || continue
    awk -v file="$f" '
      /^[[:space:]]*$/ { ok = 0; next }
      /^[[:space:]]*#/ { ok = 1; next }
      !ok { print "UNJUSTIFIED waiver " $0 " " file ":" NR }' "$f"
  done
}

# dp_ignores: every entry of every ignore file, one per line ("kind:glob" or a
# bare glob that waives any kind).
dp_ignores() {
  local f
  for f in $DP_IGNORE; do
    [[ -f "$f" ]] || continue
    dp_grep -vE '^[[:space:]]*(#|$)' "$f" | sed 's/[[:space:]]*$//'
  done
}

# dp_report <tag> <findings file> <checked count> <label> <mode>: print the
# findings (already formatted), a summary, and return the mode's exit code.
dp_report() {
  local tag="$1" findings="$2" checked="$3" label="$4" mode="$5" n
  n="$(awk 'END { print NR }' "$findings")"
  cat "$findings"
  if [[ "$n" -eq 0 ]]; then
    echo "+ ${tag}: consistent (${checked} ${label} checked)"
    return 0
  fi
  echo "! ${tag}: ${n} finding(s) of ${checked} ${label}:$(awk '{ c[$1 " " $2]++ } END { for (k in c) printf " %s=%d", k, c[k] }' "$findings")"
  [[ "$mode" == block ]] && return 1
  return 0
}

# dp_args: shared option parsing. Sets MODE, KINDS (empty = all), CONFIG, LIST.
dp_args() {
  MODE="block"; KINDS=""; CONFIG=""; LIST=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --warn) MODE="warn"; shift ;;
      --block) MODE="block"; shift ;;
      --kinds) KINDS="$2"; shift 2 ;;
      --root) cd "$2"; shift 2 ;;
      --config) CONFIG="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
      --list) LIST="$2"; shift 2 ;;
      -h|--help) return 3 ;;
      *) echo "! unknown option: $1" >&2; return 2 ;;
    esac
  done
}

# dp_want <kind>: true when --kinds is empty or names the kind.
dp_want() { [[ -z "$KINDS" || ",${KINDS}," == *",$1,"* ]]; }

# dp_subcommands <list of code files>: "tool<TAB>sub<TAB>file:line" for each
# CLI subcommand a cheap per-stack heuristic finds. Shell: arms of
# `case "$1"|"$cmd"|"$sub"...` (tool = script file name). Python argparse
# add_parser / click command(name), Dart addCommand, TS/JS commander
# .command(), Kotlin clikt name = (tool = file stem; documented by any
# backticked mention).
dp_subcommands() {
  local list="$1"
  dp_grep -E '\.(sh|bash)$' "$list" > "$DP_WORK/sh-files"
  if [[ -s "$DP_WORK/sh-files" ]]; then
    tr '\n' '\0' < "$DP_WORK/sh-files" | xargs -0 awk '
      FNR == 1 { depth = 0; fn = 0; n = split(FILENAME, p, "/"); tool = p[n] }
      # `case "$1"` inside a function reads the function argument, not the CLI
      # (rejected: counting them; a main() dispatcher is missed instead).
      /^(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*\(\)/ && !/}[[:space:]]*$/ { fn = 1 }
      /^}/ { fn = 0 }
      depth && /^[[:space:]]*case[[:space:]]/ { depth++; next }
      !fn && tolower($0) ~ /^[[:space:]]*case[[:space:]]+"?\$\{?(1|cmd|sub|subcmd|subcommand|command|action|verb)[}:" -]/ { depth = 1; next }
      depth && /^[[:space:]]*esac/ { depth--; next }
      depth == 1 && /^[[:space:]]*[a-z][a-z0-9|_-]*\)/ {
        arm = $0; sub(/^[[:space:]]*/, "", arm); sub(/\).*/, "", arm)
        m = split(arm, a, "|")
        for (k = 1; k <= m; k++) if (a[k] ~ /^[a-z][a-z0-9_-]*$/) print tool "\t" a[k] "\t" FILENAME ":" FNR
      }'
  fi
  dp_grep -vE '\.(sh|bash)$' "$list" > "$DP_WORK/other-files"
  dp_xgrep "$DP_WORK/other-files" -nHIE "(add_parser|addCommand|\.command|command)\(\s*(name\s*=\s*)?['\"][a-z][a-z0-9_-]*['\"]|CliktCommand\(\s*name\s*=\s*\"[a-z][a-z0-9_-]*\"" \
    | awk '{
        loc = $0; sub(/:[0-9]+:.*/, "", loc); line = $0; sub(/^[^:]*:/, "", line); ln = line; sub(/:.*/, "", ln); sub(/^[0-9]+:/, "", line)
        if (match(line, /['\''"][a-z][a-z0-9_-]*['\''"]/)) {
          s = substr(line, RSTART + 1, RLENGTH - 2); n = split(loc, p, "/"); stem = p[n]; sub(/\.[^.]*$/, "", stem)
          print stem "\t" s "\t" loc ":" ln
        }
      }'
}
