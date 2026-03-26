#!/usr/bin/env bash
# services/testhost/start.sh — Start the testhost review + upload server
#
# Usage:
#   services/testhost/start.sh [PROJECT_ROOT]
#
# Environment variables (all optional):
#   TESTHOST_PORT       — Listen port (default: 9090)
#   TESTHOST_PROJECT    — Project root for test artifacts (default: first arg or cwd)
#   TESTHOST_UPLOAD_DIR — Upload directory (default: $TESTHOST_PROJECT/test-results/uploads)

set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "${1:-}" ]]; then
  export TESTHOST_PROJECT="$1"
fi

exec node server.js
