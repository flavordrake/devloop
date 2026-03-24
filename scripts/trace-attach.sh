#!/usr/bin/env bash
# scripts/trace-attach.sh — Download a testhost file into a TRACE's artifacts/ directory
#
# Usage:
#   scripts/trace-attach.sh <trace-dir> <file-url>
#
# Examples:
#   scripts/trace-attach.sh .traces/trace-issue-42/ http://localhost:9090/file/2026-03-24/screenshot.png
#   scripts/trace-attach.sh .traces/trace-issue-42/ http://localhost:9090/file/2026-03-24/log.txt
#
# The file is saved to <trace-dir>/artifacts/<original-filename>.
# If a file with the same name exists, a -1, -2 suffix is added.

set -euo pipefail
cd "$(dirname "$0")/.."

TRACE_DIR="${1:-}"
FILE_URL="${2:-}"

if [ -z "$TRACE_DIR" ] || [ -z "$FILE_URL" ]; then
  echo "Usage: scripts/trace-attach.sh <trace-dir> <file-url>"
  exit 1
fi

if [ ! -d "$TRACE_DIR" ]; then
  echo "Error: TRACE directory does not exist: $TRACE_DIR"
  exit 1
fi

ARTIFACTS_DIR="$TRACE_DIR/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# Extract filename from URL path
FILENAME=$(basename "$FILE_URL")
if [ -z "$FILENAME" ] || [ "$FILENAME" = "/" ]; then
  echo "Error: could not extract filename from URL: $FILE_URL"
  exit 1
fi

# Deduplicate filename
TARGET="$ARTIFACTS_DIR/$FILENAME"
if [ -f "$TARGET" ]; then
  EXT=""
  BASE="$FILENAME"
  if [[ "$FILENAME" == *.* ]]; then
    EXT=".${FILENAME##*.}"
    BASE="${FILENAME%.*}"
  fi
  I=1
  while [ -f "$TARGET" ]; do
    TARGET="$ARTIFACTS_DIR/${BASE}-${I}${EXT}"
    I=$((I + 1))
    if [ "$I" -gt 9999 ]; then
      echo "Error: too many duplicates for $FILENAME"
      exit 1
    fi
  done
fi

# Build curl args — pass auth token if set
CURL_ARGS=(-fsSL -o "$TARGET")
if [ -n "${TESTHOST_AUTH_TOKEN:-}" ]; then
  CURL_ARGS+=(-H "Authorization: Bearer $TESTHOST_AUTH_TOKEN")
fi

if ! curl "${CURL_ARGS[@]}" "$FILE_URL"; then
  echo "Error: failed to download $FILE_URL"
  exit 1
fi

echo "Saved: $TARGET"
