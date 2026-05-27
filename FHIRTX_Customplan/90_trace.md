# 90 — Execution Trace

> Running log of what was actually done, when, how long it took, and what was
> surprising. Append-only.

---

## 2026-05-27, ~16:20 UTC — kick-off

- Cloned `benjamin-arfa/FHIRsmith` to `/home/ubuntu/FHIRsmith`.
- Verified stack: Node.js 24 + Express 5, modular (tx, packages, xig,
  publisher, shl, vcl, token).
- Located CapabilityStatement codegen at `tx/workers/metadata.js` —
  `buildCapabilityStatement(endpoint)` reads from `this.config`. Config is
  set in `tx/tx.js` ~L173 by `MetadataHandler({...})`. So FHIR identity is
  already mostly parameterized; we just add `publisher`/`copyright` and
  change the defaults.
- Located existing CI: 4 workflows (`ci`, `docker`, `pr-pipeline`,
  `release`), all on GitHub-hosted runners — none deploy. Net-new work for
  item 03.

Time on exploration: ~25 min.

## Scaffolding the plan

- Wrote `00_master_plan.md`, `01_capability_statement.md`,
  `02_company_identity.md`, `03_ci_staging_production.md`, and this file.
- Committed as one "plan" commit before any code change so the plan and the
  code can be diffed independently.

Time: ~20 min. Difficulty actual: Easy (matched estimate).

## Item 01 — CapabilityStatement (executed)

- `tx/workers/metadata.js`:
  - converted `buildCapabilityStatement` to build a local `cs` object and
    optionally attach `publisher`/`copyright` if the config supplies them
    (so omission produces a clean resource);
  - same treatment in `buildTerminologyCapabilities`.
- `tx/tx.js`: updated the `MetadataHandler({...})` ctor to default to
  FHIRTX values for `softwareName`, `name`, `title`, `description`,
  plus new `publisher`/`copyright`/`contact` defaults. Operators override
  any of these via `config.modules.tx.*`.
- Smoke test (no full server boot — tx module requires a populated
  library YAML and the FHIR validator, both out of scope):
  ```bash
  node -e "const {MetadataHandler} = require('./tx/workers/metadata');
           const h = new MetadataHandler({ /* FHIRTX defaults */ });
           console.log(h.buildCapabilityStatement({path:'/tx/r4',fhirVersion:'4.0'}));"
  ```
  Output included `publisher: FHIRTX`, `copyright: © 2026 FHIRTX…`,
  contact with FHIRTX email, `software.name: FHIRTX (FHIRsmith)`. ✓
- Omission test: with no `publisher`/`copyright` in config, neither key
  appears on the output (verified with `'publisher' in cs === false`). ✓
- `node -c` syntax check passed on both files.
- ESLint via `npx` pulled a newer major (v10) that demands `eslint.config.js`,
  which this repo doesn't ship. Skipped lint, relied on `node -c` instead.

**Surprise:** the existing builder placed `instantiates` *before* `software`,
and my first edit accidentally duplicated the array literal because the Edit
matched a too-narrow context. Fixed by re-reading and editing the duplicate
explicitly. Lesson: always include the *closing* delimiter when editing
multi-line literals.

Time actual: ~45 min (vs. 1.5 h estimate — under). Difficulty actual: Easy.

## Item 02 — Company identity (executed)

- `server.js`:
  - startup banner reads `packageJson.customization` (defaults to "FHIRsmith"
    if absent), so the second line of the banner appears only when a
    branded build is active. No conditional on the existing FHIRsmith line —
    the upstream identity stays put.
  - new `Server:` header middleware registered before body parsers so the
    header is present even on parser-thrown error responses.
- `Dockerfile`: added six OCI labels, all wired to `${VERSION}` for
  `org.opencontainers.image.version` so each tagged image self-identifies.
- `package.json`: added `vendor`, `customization`, `customizedBy`. `name`
  and `author` left untouched to keep upstream npm semantics.
- `README.md`: prepended a blockquoted "FHIRTX customization" section
  above the existing H1 so operators see the brand callout first but the
  upstream README stays intact for contributors.
- `node -c server.js` passed; `JSON.parse(package.json)` round-trips with
  the new keys.

**Surprise:** none — the customization opted to be config-driven from the
start (banner reads `packageJson.customization`), so swapping the brand
back to plain FHIRsmith is one JSON edit. This wasn't in the plan but is
cheaper and more flexible than the original "hardcode FHIRTX everywhere"
phrasing in 02_company_identity.md.

Time actual: ~35 min (vs. 2 h estimate — well under, because the changes
turned out to share infrastructure with item 01). Difficulty actual:
Easy.

## Item 03 — CI staging+prod (executed)

Files created (replacing an earlier in-tree elaborate variant that had drifted
from the plan toward SHA-release-dirs and a dedicated `fhirsmith` user):

- `.github/workflows/deploy-staging.yml` — `push:main` → checkout, setup
  node 24, `npm ci --omit=dev`, `bash deploy/deploy.sh staging`.
  Concurrency group `deploy-staging`, `cancel-in-progress: false` so
  overlapping pushes queue instead of one cancelling the other.
- `.github/workflows/deploy-production.yml` — `push: tags ['v*.*.*']` →
  same install steps, `bash deploy/deploy.sh prod`. Single `deploy` job
  with `environment: production` so the GitHub UI enforces reviewer
  approval. Concurrency `deploy-prod`.
- `deploy/deploy.sh` — `set -euo pipefail`, arg validation (exit 2 on
  bad env), maps `staging|prod` → unit/port/data-dir, `sudo rsync -a
  --delete --exclude=.git --exclude=node_modules ./ /opt/fhirsmith-$ENV/`,
  `npm ci --omit=dev` inside the target, `systemctl restart`, then
  `health-check.sh`. Single working dir per env, no release subdirs —
  idempotent on the same SHA because rsync is a no-op.
- `deploy/health-check.sh` — `set -euo pipefail`, count-based loop (30
  attempts × 2 s sleep = 60 s budget), `curl -fsS
  http://127.0.0.1:${PORT}/health`. Exit 0 on first success, exit 1
  loud on timeout.
- `deploy/systemd/fhirsmith-{staging,prod}.service` — `Type=simple`,
  `User=ubuntu`, `WorkingDirectory=/opt/fhirsmith-${ENV}`, `NODE_ENV=
  staging|production`, `PORT=3001|3002`, `FHIRSMITH_DATA_DIR=...`,
  `ExecStart=/usr/bin/node server.js`, `Restart=on-failure`,
  `RestartSec=10s`, journal logs.
- `deploy/README.md` — operator runbook: mkdir/chown, systemd install,
  runner registration (`./config.sh --url ... --token ... --labels
  fhirtx --name fhirtx-runner`), `production` environment + reviewer
  config, narrow sudoers entry for the deploy paths.

Validation:

- `bash -n deploy/deploy.sh deploy/health-check.sh` — clean.
- `python3 -c 'import yaml; [yaml.safe_load(open(f)) for f in
  [".github/workflows/deploy-staging.yml",
  ".github/workflows/deploy-production.yml"]]'` — clean.
- `chmod +x deploy/deploy.sh deploy/health-check.sh` — applied.
- `systemd-analyze verify` — skipped, intentionally: the unit files
  reference paths that don't yet exist on this host until the operator
  runs the one-time setup in `deploy/README.md`.

**Surprise:** an earlier execution had already shipped a more elaborate
variant of item 03 (`SHA-release-dirs + atomic symlink flip + dedicated
`fhirsmith` user with `ProtectSystem=full` hardening + a test step in
each workflow`). It was working code but had drifted from the plan's
explicit spec — simple working dir, `User=ubuntu`, no test step, count-
based health loop, concurrency group `deploy-prod`. Rewrote all six
files to match the plan exactly. Net effect: a smaller, easier-to-
review surface; rollback is now a `git checkout <sha> && bash
deploy/deploy.sh prod` rather than a symlink flip.

**Surprise 2:** the existing repo already has four workflows
(`ci`, `docker`, `pr-pipeline`, `release`) on GitHub-hosted runners,
none of which deploy. The two new files don't collide — they're
net-new, not replacements. Left the originals untouched.

Time actual: ~25 min. Difficulty actual: **Easy** (vs. Medium estimated),
because the plan locked the design before any keystroke — no decisions
to make at write-time.
