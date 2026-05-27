#!/usr/bin/env bash
#
# health-check.sh PORT
#
# Polls http://localhost:PORT/health for up to 60 s. Fails loud (exit 1) if
# the service never returns HTTP 200 — the calling workflow will mark the
# deploy red and the operator can roll back by re-pointing 'current' to
# the previous release dir.
#
set -euo pipefail

PORT="${1:-3001}"
DEADLINE=$(( SECONDS + 60 ))

while (( SECONDS < DEADLINE )); do
  if curl -fsS "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    echo "==> /health on :${PORT} is green"
    exit 0
  fi
  sleep 2
done

echo "ERROR: /health on :${PORT} never became green within 60 s" >&2
exit 1
