#!/usr/bin/env bash
#
# health-check.sh PORT
#
# Polls http://127.0.0.1:PORT/health up to 30 times with 2 s gaps. Exits 0
# on first success; exits 1 with a loud message if /health never comes up.
#
set -euo pipefail

PORT="${1:-}"
if [[ -z "$PORT" ]]; then
  echo "usage: $0 <port>" >&2
  exit 2
fi

for attempt in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null; then
    echo "==> /health on :${PORT} is green (attempt ${attempt})"
    exit 0
  fi
  sleep 2
done

echo "ERROR: /health on :${PORT} never returned 200 after 30 attempts (~60 s)" >&2
exit 1
