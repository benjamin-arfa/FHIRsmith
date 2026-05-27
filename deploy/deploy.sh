#!/usr/bin/env bash
#
# deploy.sh ENV
#
# Idempotent deploy script for FHIRTX (FHIRsmith fork). Called by the
# self-hosted GitHub Actions runner after a successful checkout/build on
# this host. Safe to re-run with the same SHA (the rsync + restart is a
# no-op if nothing changed).
#
# Layout per env:
#   /opt/fhirsmith-${ENV}/releases/<sha>/  ← this checkout
#   /opt/fhirsmith-${ENV}/current          → symlink to active release
#   /var/lib/fhirsmith-${ENV}              ← data dir (config.json lives here)
#
set -euo pipefail

ENV="${1:-}"
if [[ "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  echo "usage: $0 <staging|prod>" >&2
  exit 2
fi

SVC="fhirsmith-${ENV}.service"
RELEASE_ROOT="/opt/fhirsmith-${ENV}"
DATA_DIR="/var/lib/fhirsmith-${ENV}"
PORT_DEFAULT_STAGING=3001
PORT_DEFAULT_PROD=3002
PORT=$([[ "$ENV" == "staging" ]] && echo "$PORT_DEFAULT_STAGING" || echo "$PORT_DEFAULT_PROD")

SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
RELEASE_DIR="${RELEASE_ROOT}/releases/${SHA}"

echo "==> Deploying ${ENV} @ ${SHA} (port ${PORT}, data ${DATA_DIR})"

# Sanity: data dir must already exist (one-time operator setup).
if [[ ! -d "$DATA_DIR" ]]; then
  echo "ERROR: data dir ${DATA_DIR} missing. Run the one-time setup in deploy/README.md." >&2
  exit 1
fi

# Stage the release.
sudo mkdir -p "$RELEASE_DIR"
sudo rsync -a --delete \
  --exclude='.git' --exclude='node_modules' --exclude='data' \
  --exclude='FHIRTX_Customplan' --exclude='deploy' \
  ./ "$RELEASE_DIR/"
sudo chown -R fhirsmith:fhirsmith "$RELEASE_DIR"

# Install runtime deps in the release dir (clean, deterministic).
sudo -u fhirsmith bash -c "cd '$RELEASE_DIR' && npm ci --omit=dev --no-audit --no-fund"

# Flip the 'current' symlink atomically.
sudo ln -sfn "$RELEASE_DIR" "${RELEASE_ROOT}/current.new"
sudo mv -Tf "${RELEASE_ROOT}/current.new" "${RELEASE_ROOT}/current"

# Restart the unit.
sudo systemctl restart "$SVC"

# Wait for healthy.
"$(dirname "$0")/health-check.sh" "$PORT"

# Retention: keep the 5 most recent releases per env.
sudo bash -c "ls -1dt ${RELEASE_ROOT}/releases/*/ | tail -n +6 | xargs -r rm -rf"

echo "==> ${ENV} @ ${SHA} is live on port ${PORT}"
