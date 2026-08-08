#!/usr/bin/env bash
# scripts/trace-archive.sh — Archive completed TRACEs and prune old archives
#
# Usage:
#   scripts/trace-archive.sh              # archive completed, prune expired
#   scripts/trace-archive.sh --dry-run    # show what would happen
#   scripts/trace-archive.sh --commit <trace-dir>  # opt-in commit a TRACE to git
#
# Completed = TRACE.md frontmatter contains status: success|failure|partial
# Archive TTL configurable via TRACE_ARCHIVE_TTL_DAYS (default: 30)

set -euo pipefail
cd "$(dirname "$0")/.."

TRACES_DIR=".traces"
ARCHIVE_DIR="$TRACES_DIR/archive"
TTL_DAYS="${TRACE_ARCHIVE_TTL_DAYS:-30}"
DRY_RUN=false
COMMIT_DIR=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --commit)
      if [ -z "${2:-}" ]; then
        echo "ERROR: --commit requires a trace directory argument"
        exit 1
      fi
      COMMIT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: scripts/trace-archive.sh [--dry-run] [--commit <trace-dir>]"
      exit 1
      ;;
  esac
done

# Handle --commit mode
if [ -n "$COMMIT_DIR" ]; then
  if [ ! -d "$COMMIT_DIR" ]; then
    echo "ERROR: Directory does not exist: $COMMIT_DIR"
    exit 1
  fi
  if [ ! -f "$COMMIT_DIR/TRACE.md" ]; then
    echo "ERROR: No TRACE.md in $COMMIT_DIR"
    exit 1
  fi

  echo "Committing TRACE to git: $COMMIT_DIR"

  # Add .gitattributes rules for large binary files
  GITATTR=".gitattributes"
  LFS_PATTERNS=("*.webm" "*.mp4")
  NEEDS_LFS=false

  for pattern in "${LFS_PATTERNS[@]}"; do
    match_count=$(find "$COMMIT_DIR" -name "$pattern" 2>/dev/null | wc -l)
    if [ "$match_count" -gt 0 ]; then
      NEEDS_LFS=true
      attr_line="$COMMIT_DIR/$pattern filter=lfs diff=lfs merge=lfs -text"
      if [ -f "$GITATTR" ]; then
        if ! grep -qF "$attr_line" "$GITATTR"; then
          echo "$attr_line" >> "$GITATTR"
          echo "  Added LFS rule: $attr_line"
        fi
      else
        echo "$attr_line" > "$GITATTR"
        echo "  Created $GITATTR with LFS rule: $attr_line"
      fi
    fi
  done

  # Check for large PNG files (>1MB)
  while IFS= read -r png_file; do
    if [ -z "$png_file" ]; then
      continue
    fi
    file_size=$(stat -c %s "$png_file")
    if [ "$file_size" -gt 1048576 ]; then
      NEEDS_LFS=true
      attr_line="$png_file filter=lfs diff=lfs merge=lfs -text"
      if [ -f "$GITATTR" ]; then
        if ! grep -qF "$attr_line" "$GITATTR"; then
          echo "$attr_line" >> "$GITATTR"
          echo "  Added LFS rule for large PNG: $attr_line"
        fi
      else
        echo "$attr_line" > "$GITATTR"
        echo "  Created $GITATTR with LFS rule for large PNG: $attr_line"
      fi
    fi
  done < <(find "$COMMIT_DIR" -name "*.png" 2>/dev/null)

  if [ "$NEEDS_LFS" = true ]; then
    git add "$GITATTR"
    echo "  Staged .gitattributes"
  fi

  git add "$COMMIT_DIR"
  echo "  Staged $COMMIT_DIR"
  echo "  Ready to commit. Run: git commit -m 'trace: archive <objective>'"
  exit 0
fi

# Main archive + prune flow
if [ ! -d "$TRACES_DIR" ]; then
  echo "No .traces/ directory found. Nothing to do."
  exit 0
fi

ARCHIVED=0
PRUNED=0
NOW=$(date +%s)
TTL_SECONDS=$((TTL_DAYS * 86400))

# Phase 1: Archive completed TRACEs
echo "Scanning for completed TRACEs (TTL: ${TTL_DAYS} days)..."

for trace_dir in "$TRACES_DIR"/trace-*/; do
  if [ ! -d "$trace_dir" ]; then
    continue
  fi

  trace_md="$trace_dir/TRACE.md"
  if [ ! -f "$trace_md" ]; then
    continue
  fi

  # Check frontmatter for status
  status=""
  in_frontmatter=false
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if [ "$in_frontmatter" = true ]; then
        break
      fi
      in_frontmatter=true
      continue
    fi
    if [ "$in_frontmatter" = true ]; then
      case "$line" in
        status:*)
          status=$(echo "$line" | sed 's/^status:[[:space:]]*//')
          break
          ;;
      esac
    fi
  done < "$trace_md"

  case "$status" in
    success|failure|partial)
      dirname=$(basename "$trace_dir")
      if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would archive: $trace_dir (status: $status)"
      else
        mkdir -p "$ARCHIVE_DIR"
        mv "$trace_dir" "$ARCHIVE_DIR/$dirname"
        echo "  Archived: $dirname (status: $status)"
      fi
      ARCHIVED=$((ARCHIVED + 1))
      ;;
  esac
done

# Phase 2: Prune expired archives
if [ -d "$ARCHIVE_DIR" ]; then
  echo "Checking archived TRACEs for expiry..."

  for archived_dir in "$ARCHIVE_DIR"/trace-*/; do
    if [ ! -d "$archived_dir" ]; then
      continue
    fi

    # Use the most recent mtime of any file in the archive
    latest_mtime=0
    while IFS= read -r f; do
      mtime=$(stat -c %Y "$f")
      if [ "$mtime" -gt "$latest_mtime" ]; then
        latest_mtime=$mtime
      fi
    done < <(find "$archived_dir" -type f)

    if [ "$latest_mtime" -eq 0 ]; then
      continue
    fi

    age_seconds=$((NOW - latest_mtime))
    if [ "$age_seconds" -gt "$TTL_SECONDS" ]; then
      dirname=$(basename "$archived_dir")
      age_days=$((age_seconds / 86400))
      if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would prune: $dirname (${age_days}d old)"
      else
        # Remove individual files first, then empty dirs — no rm -rf
        find "$archived_dir" -type f -delete
        find "$archived_dir" -type d -empty -delete
        echo "  Pruned: $dirname (${age_days}d old)"
      fi
      PRUNED=$((PRUNED + 1))
    fi
  done
fi

# Summary
echo ""
TIMESTAMP=$(date +%Y%m%dT%H%M%S%z)
if [ "$DRY_RUN" = true ]; then
  echo "[$TIMESTAMP] Dry run complete: $ARCHIVED would be archived, $PRUNED would be pruned"
else
  echo "[$TIMESTAMP] Archive complete: $ARCHIVED archived, $PRUNED pruned"
fi
