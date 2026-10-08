#!/usr/bin/env bash
# skills/doc-parity/scripts/docs-to-code.sh: every mechanical claim a doc makes
# must exist in the repo (doc-parity skill, layer a, direction docs to code).
# Claim kinds:
#   path    a repo-relative path whose first segment is a top-level directory
#           (a file with an extension, or a directory ending in /): exists
#   script  a bare name.sh|.bash|.py|.mjs: some file in the repo has that name
#   env     a word with the configured env-prefix: some code file names it
#   cli     `tool.sh <sub>` in backticks or a code fence, for a script whose
#           subcommands are enumerable: the script dispatches <sub>;
#           `tool.sh {a|b}` and `tool.sh <a|b>` claim each alternative
#   route   GET|POST|PUT|DELETE|PATCH /x/y: the static part appears in code
# Research docs make path and script claims only. Records dirs make none.
# Prints `MISSING <kind> <value> <doc>:<line> (+N more)` per claim, and
# `UNJUSTIFIED waiver ...` per ignore entry with no comment above it.
# Usage: docs-to-code.sh [--warn|--block] [--kinds k1,k2] [--root DIR]
#                        [--config FILE] [--list KIND]
#   --block (default) exits 1 on findings; --warn always exits 0.
#   --list KIND prints every claimed value of that kind and exits 0.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
rc=0; dp_args "$@" || rc=$?
if [[ "$rc" -eq 3 ]]; then sed -n '2,19p' "$0"; exit 0; fi
if [[ "$rc" -ne 0 ]]; then exit "$rc"; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/doc-parity-d2c.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
dp_init "$WORK" "$CONFIG"

# Path claims are anchored on the repo's own top-level directories, plus
# scripts/ and docs/ so a doc naming a never-created scripts/x.sh is caught.
# (Rejected: a fixed list with src/, lib/, test/: package READMEs name
# package-relative src/x.ts, which then read as broken root paths.)
ROOTS="scripts docs $(awk -F/ 'NF > 1 { print $1 }' "$WORK/files" | sort -u | tr '\n' ' ')"

# claims: "kind<TAB>value<TAB>doc:line"
dp_claims() {
  [[ -s "$WORK/docs" ]] || return 0
  tr '\n' '\0' < "$WORK/docs" | xargs -0 awk -v roots="$ROOTS" -v pfx="$DP_ENV_PREFIX" \
    -v sibs="$DP_SIBLINGS" -v resfile="$WORK/research" '
    BEGIN {
      n = split(roots, a, " "); for (k = 1; k <= n; k++) root[a[k]] = 1
      np = split(pfx, P, " "); ns = split(sibs, S, " ")
      while ((getline l < resfile) > 0) research[l] = 1
    }
    FNR == 1 { fence = 0; res = (FILENAME in research) }
    /^[[:space:]]*```/ { fence = !fence }
    {
      loc = FILENAME ":" FNR; line = $0; rest = line; off = 0
      # Path and script claims: maximal runs of path characters, so URL tails
      # (https://x/docs/a.md), $VAR/x, ~/x, user@host:x and foo.sha256 never
      # look like a claim.
      while (match(rest, /[A-Za-z0-9_.\/~@:$-]+/)) {
        tok = substr(rest, RSTART, RLENGTH); before = substr(line, 1, off + RSTART - 1)
        post = substr(rest, RSTART + RLENGTH, 1)
        off += RSTART + RLENGTH - 1; rest = substr(rest, RSTART + RLENGTH)
        if (tok ~ /:\/\// || tok ~ /^[~@$\/]/ || tok ~ /[@$]/) continue
        sub(/:.*/, "", tok); sub(/^\.\//, "", tok); sub(/[.,]+$/, "", tok)
        if (tok == "" || tok ~ /^\.\.\// || post ~ /[*<{]/) continue
        sib = 0
        for (k = 1; k <= ns; k++) if (before ~ ("(^|[^A-Za-z0-9_-])" S[k] "[ /]$")) sib = 1
        if (sib) continue
        if (index(tok, "/")) {
          first = tok; sub(/\/.*/, "", first)
          last = tok; sub(/.*\//, "", last)
          if ((first in root) && (tok ~ /\/$/ || last ~ /[A-Za-z0-9_-]\.[A-Za-z0-9]+$/)) print "path\t" tok "\t" loc
        } else if (tok ~ /^[A-Za-z0-9][A-Za-z0-9_.-]*\.(sh|bash|py|mjs)$/) print "script\t" tok "\t" loc
      }
      if (res) next
      if (np) {
        rest = line
        while (match(rest, /[A-Za-z0-9_]+/)) {
          w = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
          for (k = 1; k <= np; k++) if (index(w, P[k]) == 1 && w ~ /^[A-Z0-9_]*[A-Z0-9]$/ && length(w) > length(P[k])) print "env\t" w "\t" loc
        }
      }
      rest = line
      while (match(rest, /(^|[^A-Za-z])(GET|POST|PUT|DELETE|PATCH) \/[^ \t`'\''",;)?]*/)) {
        r = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        sub(/^[^\/]*/, "", r); sub(/[<{:*].*/, "", r); sub(/[\/.]+$/, "", r)
        if (length(r) > 1) print "route\t" r "\t" loc
      }
      # cli claims only from code contexts: a fence, or inline backtick spans.
      if (fence) code = line
      else { code = ""; t = line; while (match(t, /`[^`]+`/)) { code = code "|" substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH) } }
      alt = code
      while (match(alt, /[A-Za-z0-9_.\/-]*[A-Za-z0-9_-]\.sh +[{<][a-z][a-z0-9_\\-]*([|][a-z][a-z0-9_\\-]*)+[}>]/)) {
        c = substr(alt, RSTART, RLENGTH); alt = substr(alt, RSTART + RLENGTH)
        tool = c; sub(/ .*/, "", tool); sub(/.*\//, "", tool); sub(/^[^{<]*[{<]/, "", c); sub(/[}>]$/, "", c); gsub(/\\/, "", c)
        m = split(c, alts, "|"); for (k = 1; k <= m; k++) print "cli\t" tool " " alts[k] "\t" loc
      }
      while (match(code, /[A-Za-z0-9_.\/-]*[A-Za-z0-9_-]\.sh +[a-z][a-z0-9_-]*/)) {
        c = substr(code, RSTART, RLENGTH); code = substr(code, RSTART + RLENGTH)
        if (code ~ /^[A-Za-z0-9_.\/-]/) continue
        tool = c; sub(/ .*/, "", tool); sub(/.*\//, "", tool); s = c; sub(/.*[ ]/, "", s)
        print "cli\t" tool " " s "\t" loc
      }
    }'
}
dp_claims > "$WORK/claims"

if [[ -n "$LIST" ]]; then
  awk -F'\t' -v k="$LIST" '$1 == k { print $2 }' "$WORK/claims" | sort -u
  exit 0
fi

# What the code has: env-prefixed words, subcommands, routes present.
: > "$WORK/words"
for p in $DP_ENV_PREFIX; do
  dp_xgrep "$WORK/code" -ohIE "[A-Za-z0-9_]*${p}[A-Za-z0-9_]*" | awk -v p="$p" 'index($0, p) == 1' >> "$WORK/words"
done
dp_subcommands "$WORK/code" | cut -f1,2 | sort -u > "$WORK/subs"
awk -F'\t' '$1 == "route" { print $2 }' "$WORK/claims" | sort -u | while IFS= read -r r; do
  if [[ -n "$(dp_xgrep "$WORK/code" -lF -- "$r")" ]]; then printf '%s\n' "$r"; fi
done > "$WORK/routes"
dp_ignores > "$WORK/ignores"
# Consumers call devloop scripts through the plugin, not a repo copy, so a doc
# naming one (scripts/gh-ops.sh, doc-parity.sh) is not a missing file.
PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd)"
{ cat "$WORK/files"
  (cd "$PLUGIN_ROOT" && find scripts skills/*/scripts -type f -name '*.sh' 2>/dev/null) # absent dirs are fine
} | sort -u > "$WORK/known"
dp_ignore_check > "$WORK/findings"

# One row per (kind, value): first doc:line and mention count; resolve each.
awk -F'\t' -v kinds="$KINDS" -v countfile="$WORK/checked" "$DP_AWK_GLOB"'
  FILENAME == ARGV[1] { f[$0] = 1; b = $0; sub(/.*\//, "", b); base[b] = 1
    d = $0; while (sub(/\/[^\/]*$/, "", d)) dir[d "/"] = 1; next }
  FILENAME == ARGV[2] { word[$0] = 1; next }
  FILENAME == ARGV[3] { hassubs[$1] = 1; subc[$1 " " $2] = 1; next }
  FILENAME == ARGV[4] { route[$0] = 1; next }
  FILENAME == ARGV[5] { ign[++ni] = $0; next }
  {
    if (kinds != "" && index("," kinds ",", "," $1 ",") == 0) next
    if ($1 == "cli") { tool = $2; sub(/ .*/, "", tool); if (!(tool in hassubs)) next }
    # A path relative to the naming doc (a package README) resolves there.
    if ($1 == "path") { dd = $3; sub(/:[0-9]+$/, "", dd); if (sub(/\/[^\/]*$/, "", dd) && (((dd "/" $2) in f) || ((dd "/" $2) in dir))) next }
    k = $1 "\t" $2
    if (!(k in first)) { first[k] = $3; order[++n] = k }
    cnt[k]++
  }
  END {
    for (i = 1; i <= n; i++) {
      k = order[i]; split(k, kv, "\t"); kind = kv[1]; v = kv[2]; checked++
      skip = 0
      for (j = 1; j <= ni; j++) {
        e = ign[j]
        if (e ~ /^(path|script|env|cli|route|file|called|subcommand):/) { if ((kind ":" v) ~ g2re(e)) skip = 1 }
        else if (v ~ g2re(e)) skip = 1
      }
      if (skip) continue
      if (kind == "path") ok = (v in f) || (v in dir)
      else if (kind == "script") ok = (v in base)
      else if (kind == "env") ok = (v in word)
      else if (kind == "cli") ok = (v in subc)
      else if (kind == "route") ok = (v in route)
      if (ok) continue
      more = cnt[k] > 1 ? " (+" cnt[k] - 1 " more)" : ""
      print "MISSING " kind " " v " " first[k] more
    }
    print checked + 0 > countfile
  }' "$WORK/known" "$WORK/words" "$WORK/subs" "$WORK/routes" "$WORK/ignores" "$WORK/claims" > "$WORK/candidates"

# A path that git ignores but exists on disk (a local config) is not missing.
while IFS= read -r line; do
  read -r _ kind value _ <<< "$line"
  if [[ "$kind" == path && -e "$value" ]]; then continue; fi
  printf '%s\n' "$line"
done < "$WORK/candidates" >> "$WORK/findings"

dp_report docs-to-code "$WORK/findings" "$(cat "$WORK/checked")" "claim(s)" "$MODE"
