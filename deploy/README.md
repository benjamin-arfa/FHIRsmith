# FHIRTX deploy — operator runbook

This directory is the bare-metal deploy harness for the FHIRTX customization
of FHIRsmith. CI on `main` deploys to **staging**; tagged releases (`v*.*.*`)
deploy to **production** after a GitHub-side manual approval.

Both environments live on the same host (this server) and are isolated only
by user, port, data dir, and systemd unit. See the layout table below.

## Layout

| Env     | Port | Data dir                     | Systemd unit                 | Release root                |
| ------- | ---- | ---------------------------- | ---------------------------- | --------------------------- |
| staging | 3001 | `/var/lib/fhirsmith-staging` | `fhirsmith-staging.service`  | `/opt/fhirsmith-staging`    |
| prod    | 3002 | `/var/lib/fhirsmith-prod`    | `fhirsmith-prod.service`     | `/opt/fhirsmith-prod`       |

Inside each release root:

```
releases/<sha>/   ← one directory per deployed commit (keep last 5)
current  →  releases/<active-sha>/   ← atomic symlink flipped by deploy.sh
```

## One-time setup (manual)

These steps require root and a token from the GitHub UI. Run them once when
this host is first onboarded.

### 1. Create the runtime user + dirs

```bash
sudo useradd --system --home-dir /var/lib/fhirsmith-prod --shell /usr/sbin/nologin fhirsmith
sudo mkdir -p /opt/fhirsmith-staging/releases /opt/fhirsmith-prod/releases
sudo mkdir -p /var/lib/fhirsmith-staging /var/lib/fhirsmith-prod
sudo chown -R fhirsmith:fhirsmith /opt/fhirsmith-staging /opt/fhirsmith-prod
sudo chown -R fhirsmith:fhirsmith /var/lib/fhirsmith-staging /var/lib/fhirsmith-prod
```

### 2. Seed each data dir with a config.json

```bash
sudo -u fhirsmith cp config-template.json /var/lib/fhirsmith-staging/config.json
sudo -u fhirsmith cp config-template.json /var/lib/fhirsmith-prod/config.json
# Edit each config to match the env (ports already come from systemd Environment=
# overrides, but module enabling and DB paths are per-env).
```

### 3. Install the systemd units

```bash
sudo cp deploy/systemd/fhirsmith-staging.service /etc/systemd/system/
sudo cp deploy/systemd/fhirsmith-prod.service    /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable fhirsmith-staging.service fhirsmith-prod.service
# Do NOT start them yet — there is no `current` symlink until the first
# deploy.sh run; systemd will start them as part of the first deploy.
```

### 4. Register the self-hosted GitHub runner

The token is **one-time** and visible only in the GitHub UI:

> github.com/benjamin-arfa/FHIRsmith → Settings → Actions → Runners →
> *New self-hosted runner* → Linux x64

Copy the suggested commands; this runbook uses the label `fhirtx` to match
the `runs-on:` in the workflows.

```bash
sudo -u fhirsmith bash <<'EOF'
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz
tar xzf actions-runner-linux-x64.tar.gz
./config.sh \
  --url https://github.com/benjamin-arfa/FHIRsmith \
  --token <PASTE-TOKEN-HERE> \
  --name "fhirtx-$(hostname)" \
  --labels fhirtx \
  --unattended
EOF
```

Then install the runner as a systemd unit so it survives reboots:

```bash
sudo /home/fhirsmith/actions-runner/svc.sh install fhirsmith
sudo /home/fhirsmith/actions-runner/svc.sh start
```

### 5. Grant the runner passwordless sudo for the deploy paths

`deploy.sh` uses `sudo` for `rsync`, `mkdir`, `chown`, `ln`, `mv`,
`systemctl restart fhirsmith-*.service`, and the retention `rm -rf`. Add a
narrow sudoers entry rather than NOPASSWD:ALL:

```
# /etc/sudoers.d/fhirsmith
fhirsmith ALL=(root) NOPASSWD: \
  /usr/bin/rsync, \
  /usr/bin/mkdir, \
  /usr/bin/chown, \
  /usr/bin/ln, \
  /usr/bin/mv, \
  /usr/bin/systemctl restart fhirsmith-staging.service, \
  /usr/bin/systemctl restart fhirsmith-prod.service, \
  /usr/bin/bash -c ls\ -1dt\ */opt/fhirsmith-*/releases/*/\ |\ tail*
```

(The last entry is intentionally permissive on `bash -c` for the retention
cleanup; tighten further with a dedicated script if needed.)

### 6. Configure the `production` GitHub environment

In the repo on GitHub: *Settings → Environments → New environment →
`production`*. Add a required reviewer (yourself). That's the manual gate
that holds back the prod deploy until you approve.

The `staging` workflow does not need a configured environment — it deploys
unconditionally on push to `main`.

## What `deploy.sh` does

1. Validates `ENV` is `staging` or `prod`.
2. `rsync`-copies the checked-out tree into
   `/opt/fhirsmith-${ENV}/releases/${SHA}/` (excluding `.git`, `node_modules`,
   `data`, `FHIRTX_Customplan`, `deploy`).
3. Installs runtime deps in that release dir with `npm ci --omit=dev`.
4. Atomically flips the `current` symlink (via `mv -Tf`).
5. `systemctl restart fhirsmith-${ENV}.service`.
6. Calls `health-check.sh` to poll `/health` for up to 60 s.
7. Trims the release dir to the 5 most recent.

A failed health check exits non-zero, which marks the workflow red but
**does not auto-rollback** — that is intentional. Rollback is a one-liner:

```bash
sudo ln -sfn /opt/fhirsmith-prod/releases/<prev-sha> /opt/fhirsmith-prod/current
sudo systemctl restart fhirsmith-prod.service
deploy/health-check.sh 3002
```

## Verification

After the first deploy of each env:

```bash
curl -I http://localhost:3001/        # Server: FHIRTX/<v> (FHIRsmith)
curl  http://localhost:3001/health
curl  http://localhost:3002/health
journalctl -u fhirsmith-staging -n 50 --no-pager
journalctl -u fhirsmith-prod    -n 50 --no-pager
```

If the tx module is enabled in either config:

```bash
curl -s http://localhost:3001/tx/r4/metadata | jq '{publisher, copyright, contact, name, title}'
```

should echo the FHIRTX defaults (or whatever the env's `config.json`
overrides them with).
