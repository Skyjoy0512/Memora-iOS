#!/bin/bash
# Opt-in real-HTTPS check. Performs exactly one request to MEMORA_REAL_WEB_URL.
# Without it, exits 0 after explaining what to set; never uses a sample site or
# a cloud model. The on-device model answers the citation step.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ -z "${MEMORA_REAL_WEB_URL:-}" ]; then
  echo "MEMORA_REAL_WEB_URL is not set. Provide an approved HTTPS URL to run the real-source check."
  exit 0
fi
case "$MEMORA_REAL_WEB_URL" in
  https://*) ;;
  *) echo "MEMORA_REAL_WEB_URL must start with https://" >&2; exit 64 ;;
esac
exec npx e2e run tests/source-web-real.e2e.ts --reporter list
