# 03 — CI for Staging + Production on this server

## Goal

Two-environment CI for FHIRTX on the **same bare-metal host** that already
runs the RCBAS services:

- **Staging** — auto-deploys on every push to `main`.
- **Production** — deploys on a tagged release (`v*.*.*`), gated by a
  GitHub `production` environment that requires manual approval.

Each environment lives on its own systemd unit, its own port, and its own
data directory, so the two never share state and one rollout never
clobbers the other.

## Approach

- Use **GitHub Actions with a self-hosted runner** on this host. Reason: no
  outbound SSH key sprawl, runner is reachable from GitHub via long-poll
  outbound HTTPS, and the runner is the same identity that already has the
  workspace checkouts. This matches how RCBAS is deployed (bare metal,
  systemd) so the operator model is consistent.
- Two workflows: `deploy-staging.yml` and `deploy-production.yml`.
- Two systemd unit templates: `fhirsmith-staging.service` and
  `fhirsmith-prod.service`, shipped under `deploy/systemd/`.
- One deploy script: `deploy/deploy.sh ENV` (env in `staging|prod`), shipped
  under `deploy/`. Health-checks `/health` after restart.

The runner registration is a **manual step** — it requires a token from the
GitHub UI (*Settings → Actions → Runners → New self-hosted runner*) that
GitHub does not expose via API for security reasons. The plan documents
the exact commands and where to paste the token; it does not run them.

## File layout shipped

```
.github/workflows/
  deploy-staging.yml      # push:main → build, deploy to staging, health-check
  deploy-production.yml   # push:tag v*.*.* → manual approval → deploy to prod
deploy/
  deploy.sh               # idempotent deploy script, takes ENV arg
  health-check.sh         # curl /health, retry, fail loudly
  systemd/
    fhirsmith-staging.service
    fhirsmith-prod.service
  README.md               # one-time runner+systemd install steps
```

## Port / dir layout

| Env     | Port  | Data dir                      | Systemd unit                  |
| ------- | ----- | ----------------------------- | ----------------------------- |
| staging | 3001  | `/var/lib/fhirsmith-staging`  | `fhirsmith-staging.service`   |
| prod    | 3002  | `/var/lib/fhirsmith-prod`     | `fhirsmith-prod.service`      |

(RCBAS owns the 8xxx range on this host; FHIRTX takes 3001/3002 to stay clear.)

## Estimation

- Workflow YAML (two files): 45 min
- Deploy + health-check scripts: 45 min
- Systemd unit files: 30 min
- README for one-time setup: 45 min
- Local validation (yamllint on workflows, bash -n on scripts, systemd-analyze
  verify on units): 30 min
- **Total: ~3.5 h**

## Difficulty

**Medium.** Not because any single piece is hard, but because there are
three new technologies meeting (GitHub Actions self-hosted, systemd, the
deploy script's own state machine) and a misconfiguration in any one of
them silently breaks the rollout. Mitigations:

- Idempotent deploy script (re-running same SHA is a no-op).
- `health-check.sh` retries `/health` for 60 s and fails the workflow loud
  if it never comes up green.
- The `production` GitHub environment requires manual approval so a
  bad `v*.*.*` push can't immediately reach prod.
- Systemd `Restart=on-failure` with `RestartSec=10s` so a transient crash
  recovers without a human.

## Steps

1. Write the two systemd unit files.
2. Write `deploy/deploy.sh` and `deploy/health-check.sh`. `set -euo pipefail`,
   `npm ci --omit=dev`, `systemctl restart $SVC`, then `health-check.sh`.
3. Write `.github/workflows/deploy-staging.yml` (`runs-on:
   [self-hosted, fhirtx]`, triggers on `push: { branches: [main] }`).
4. Write `.github/workflows/deploy-production.yml` (same, but
   `runs-on: [self-hosted, fhirtx]`, triggers on `push: { tags: ['v*.*.*'] }`,
   with `environment: production` for the deploy job for manual approval).
5. Write `deploy/README.md` documenting:
   - one-time runner registration (`./config.sh --url ... --token ...
     --labels fhirtx`),
   - one-time `sudo cp deploy/systemd/*.service /etc/systemd/system/`,
   - one-time `sudo systemctl daemon-reload && sudo systemctl enable
     --now fhirsmith-staging fhirsmith-prod`,
   - GitHub `production` environment + reviewer config.
6. Local validation:
   - `bash -n deploy/*.sh`
   - `python3 -c 'import yaml; [yaml.safe_load(open(f)) for f in
     [".github/workflows/deploy-staging.yml", ".github/workflows/deploy-production.yml"]]'`
   - skip `systemd-analyze verify` because the unit files reference paths
     that may not yet exist on this host (the FHIRTX user, the data dirs);
     they'll be validated when the operator actually installs them.
7. Commit with subject `feat(ci): self-hosted staging+prod deploy pipeline`.

## Outcome

*(filled in by 90_trace.md after execution)*

- Six files shipped exactly as planned, plus a `deploy/README.md` that
  doubles as the operator runbook.
- Workflows tagged the runner as `fhirtx` (not the default `self-hosted`)
  so RCBAS-related runners (if any are ever added on this host) cannot
  accidentally pick up FHIRTX jobs and vice versa.
- The production workflow uses `environment: production` so the GitHub UI
  enforces the reviewer requirement — no code-side branch protection
  config needed.
- Manual-step list (runner registration, systemd install, env config) is
  consolidated in `deploy/README.md` so an operator does it once and the
  CI takes over.
- `deploy.sh` was written to be safe to run from a developer's laptop too
  (it errors loudly if `ENV` isn't `staging` or `prod`) so it can also be
  used for ad-hoc redeploys without going through GitHub.
