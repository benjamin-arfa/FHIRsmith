#!/usr/bin/env bash
#
# deploy.sh ENV
#
# Idempotent deploy for FHIRTX (FHIRsmith fork). Called by the self-hosted
# GitHub Actions runner after checkout + `npm ci --omit=dev`. Safe to
# re-run on the same SHA — rsync + restart are no-ops when nothing changed.
#
set -euo pipefail

ENV="${1:-}"
if [[ "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  echo "usage: $0 <staging|prod>" >&2
  exit 2
fi

case "$ENV" in
  staging)
    SVC="fhirsmith-staging.service"
    PORT=3001
    DATA_DIR="/var/lib/fhirsmith-staging"
    ;;
  prod)
    SVC="fhirsmith-prod.service"
    PORT=3002
    DATA_DIR="/var/lib/fhirsmith-prod"
    ;;
esac

TARGET="/opt/fhirsmith-${ENV}"

echo "==> Deploying ${ENV} → ${TARGET} (port ${PORT}, data ${DATA_DIR})"

echo "==> Rsyncing working tree to ${TARGET}"
sudo mkdir -p "${TARGET}"
sudo rsync -a --delete \
  --exclude='.git' \
  --exclude='node_modules' \
  ./ "${TARGET}/"

echo "==> Installing runtime deps in ${TARGET}"
sudo bash -c "cd '${TARGET}' && npm ci --omit=dev"

echo "==> Restarting ${SVC}"
sudo systemctl restart "${SVC}"

echo "==> Health-checking on :${PORT}"
bash "$(dirname "$0")/health-check.sh" "${PORT}"

echo "==> ${ENV} is live on port ${PORT}"
