#!/usr/bin/env bash
# scripts/trace-cleanup.sh — Remove empty/abandoned TRACE directories
#
# Usage:
#   scripts/trace-cleanup.sh             # clean abandoned TRACEs
#   scripts/trace-cleanup.sh --dry-run   # show what would be cleaned
#
# Abandoned = no TRACE.md, or TRACE.md exists but has no frontmatter (no --- block)
# Designed to run frequently (e.g., from release skill)

set -euo pipefail
cd "$(dirname "$0")/.."

TRACES_DIR=".traces"
DRY_RUN=false

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

if [ ! -d "$TRACES_DIR" ]; then
  echo "No .traces/ directory found. Nothing to do."
  exit 0
fi

CLEANED=0

echo "Scanning for abandoned TRACEs..."

for trace_dir in "$TRACES_DIR"/trace-*/; do
  if [ ! -d "$trace_dir" ]; then
    continue
  fi

  trace_md="$trace_dir/TRACE.md"
  abandoned=false
  reason=""

  # Case 1: No TRACE.md at all
  if [ ! -f "$trace_md" ]; then
    abandoned=true
    reason="no TRACE.md"
  else
    # Case 2: TRACE.md exists but has no frontmatter
    has_frontmatter=false
    while IFS= read -r line; do
      if [ "$line" = "---" ]; then
        has_frontmatter=true
        break
      fi
      # Skip empty lines at the top
      if [ -n "$line" ]; then
        break
      fi
    done < "$trace_md"

    if [ "$has_frontmatter" = false ]; then
      abandoned=true
      reason="TRACE.md has no frontmatter"
    fi
  fi

  if [ "$abandoned" = true ]; then
    dirname=$(basename "$trace_dir")
    if [ "$DRY_RUN" = true ]; then
      echo "  [dry-run] Would clean: $dirname ($reason)"
    else
      # Remove individual files first, then empty dirs — no rm -rf
      find "$trace_dir" -type f -delete
      find "$trace_dir" -type d -empty -delete
      echo "  Cleaned: $dirname ($reason)"
    fi
    CLEANED=$((CLEANED + 1))
  fi
done

# Summary
TIMESTAMP=$(date +%Y%m%dT%H%M%S%z)
if [ "$DRY_RUN" = true ]; then
  echo "[$TIMESTAMP] Dry run complete: $CLEANED would be cleaned"
else
  echo "[$TIMESTAMP] Cleanup complete: $CLEANED cleaned"
fi
