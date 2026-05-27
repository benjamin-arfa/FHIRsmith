# FHIRTX deploy — operator runbook

This directory is the bare-metal deploy harness for the FHIRTX customization
of FHIRsmith. CI on `main` deploys to **staging**; tagged releases
(`v*.*.*`) deploy to **production** after a GitHub-side manual approval.

Both environments live on the same host (this server) and are isolated by
port, data dir, and systemd unit.

## Layout

| Env     | Port | Working dir              | Data dir                     | Systemd unit                 |
| ------- | ---- | ------------------------ | ---------------------------- | ---------------------------- |
| staging | 3001 | `/opt/fhirsmith-staging` | `/var/lib/fhirsmith-staging` | `fhirsmith-staging.service`  |
| prod    | 3002 | `/opt/fhirsmith-prod`    | `/var/lib/fhirsmith-prod`    | `fhirsmith-prod.service`     |

## One-time setup (manual, operator)

The plan ships the files for these steps but does **not** execute them —
they require root and a one-time GitHub token visible only in the web UI.

### 1. Create the working + data dirs

```bash
sudo mkdir -p /opt/fhirsmith-staging /opt/fhirsmith-prod
sudo mkdir -p /var/lib/fhirsmith-staging /var/lib/fhirsmith-prod
sudo chown -R ubuntu:ubuntu /opt/fhirsmith-staging /opt/fhirsmith-prod
sudo chown -R ubuntu:ubuntu /var/lib/fhirsmith-staging /var/lib/fhirsmith-prod
```

### 2. Install the systemd units

```bash
sudo cp deploy/systemd/fhirsmith-staging.service /etc/systemd/system/
sudo cp deploy/systemd/fhirsmith-prod.service    /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fhirsmith-staging fhirsmith-prod
```

### 3. Register the self-hosted GitHub runner

The registration token is one-time and visible only in the GitHub UI:

> github.com/benjamin-arfa/FHIRsmith → Settings → Actions → Runners →
> *New self-hosted runner* → Linux x64

Copy the suggested download/extract commands, then register with the
`fhirtx` label so the runner picks up these workflows (`runs-on:
[self-hosted, fhirtx]`):

```bash
./config.sh \
  --url https://github.com/benjamin-arfa/FHIRsmith \
  --token <PASTE-TOKEN-HERE> \
  --labels fhirtx \
  --name fhirtx-runner
```

Then install it as a systemd unit so it survives reboots:

```bash
sudo ./svc.sh install ubuntu
sudo ./svc.sh start
```

### 4. Configure the `production` GitHub environment

In the repo: *Settings → Environments → New environment → `production`*.
Add a required reviewer (yourself). That's the gate that holds back the
production workflow until you approve. No code-side branch protection is
needed — the workflow's `environment: production` block is what triggers
the reviewer prompt.

The `staging` workflow does not need a configured environment.

### 5. Grant the runner sudo for the deploy paths

`deploy.sh` uses `sudo` for `mkdir`, `rsync`, `bash -c npm ci`, and
`systemctl restart fhirsmith-*.service`. Add a narrow sudoers entry rather
than `NOPASSWD:ALL`:

```
# /etc/sudoers.d/fhirsmith
ubuntu ALL=(root) NOPASSWD: \
  /usr/bin/mkdir, \
  /usr/bin/rsync, \
  /usr/bin/bash, \
  /usr/bin/systemctl restart fhirsmith-staging.service, \
  /usr/bin/systemctl restart fhirsmith-prod.service
```

## What `deploy.sh` does

1. Validates `ENV` is `staging` or `prod` (exits 2 otherwise).
2. Maps `ENV` to its systemd unit, port, and data dir.
3. `rsync -a --delete` the working tree into `/opt/fhirsmith-${ENV}`
   (excluding `.git` and `node_modules`).
4. Runs `npm ci --omit=dev` in the target dir for clean runtime deps.
5. `systemctl restart fhirsmith-${ENV}.service`.
6. Calls `health-check.sh` to poll `/health` up to 30 times (2 s gaps).

It's safe to re-run on the same SHA — every step is idempotent.

## Manual rollback

If a deploy goes red, roll back by checking out the prior commit on the
runner and re-running:

```bash
git checkout <previous-good-sha>
npm ci --omit=dev
bash deploy/deploy.sh prod
```

## Verification

After the first deploy of each env:

```bash
curl http://127.0.0.1:3001/health
curl http://127.0.0.1:3002/health
journalctl -u fhirsmith-staging -n 50 --no-pager
journalctl -u fhirsmith-prod    -n 50 --no-pager
```
