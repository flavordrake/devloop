#!/usr/bin/env bash
# services/testhost/start.sh — Start the testhost file upload server
#
# Environment variables (all optional):
#   TESTHOST_PORT       — Listen port (default: 9090)
#   TESTHOST_UPLOAD_DIR — Upload directory (default: services/testhost/uploads)
#   TESTHOST_MAX_SIZE   — Max upload size in bytes (default: 52428800 = 50MB)
#   TESTHOST_AUTH_TOKEN — Auth token for non-local deployments (default: none)

set -euo pipefail
cd "$(dirname "$0")"

exec node server.js
