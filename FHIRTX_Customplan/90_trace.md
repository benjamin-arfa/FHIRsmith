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

## Item 03 — CI for staging+prod (executed)

- `.github/workflows/deploy-staging.yml`: triggers on push:main +
  workflow_dispatch, runs on `[self-hosted, fhirtx]`, runs `npm run
  test:unit` only (~10 min budget vs. 20 min for full CI) before calling
  `deploy/deploy.sh staging`. Concurrency group `deploy-staging`
  serializes overlapping pushes.
- `.github/workflows/deploy-production.yml`: triggers on `push: tags:
  ['v*.*.*']` + workflow_dispatch (with a `ref` input for ad-hoc
  redeploys). Uses the `production` GitHub environment to enforce manual
  reviewer approval before any step executes. Runs the full `test:ci`
  before deploying — slower, but prod has to be green.
- `deploy/deploy.sh` is idempotent: SHA-named release dirs under
  `/opt/fhirsmith-${ENV}/releases/`, atomic `current` symlink flip, narrow
  rsync excludes, `npm ci --omit=dev` for runtime deps, retention to keep
  the last 5 releases for instant rollback.
- `deploy/health-check.sh` polls `/health` for 60 s with 2 s gaps; exits 1
  hard on timeout so the workflow turns red.
- `deploy/systemd/fhirsmith-{staging,prod}.service`: dedicated `fhirsmith`
  user, hardening (NoNewPrivileges, ProtectSystem=full, ReadWritePaths
  whitelist), `Restart=on-failure`, memory caps appropriate per env (4-6 G
  staging, 6-8 G prod).
- `deploy/README.md` doubles as the operator runbook: user + dir
  creation, systemd install, **runner registration** (with the token-via-
  GitHub-UI note marked as the manual step), narrow sudoers entry, and
  GitHub `production` environment reviewer config. Rollback is
  documented as a one-liner.
- Validation:
  - `bash -n deploy/deploy.sh deploy/health-check.sh` — clean.
  - `python3 -c 'yaml.safe_load(...)'` on both workflow files — clean.
  - `systemd-analyze verify` intentionally skipped because the unit
    files reference paths and a user (`fhirsmith`) that don't yet exist
    on this host; they'll be checked when the operator actually
    installs them per the README.

**Surprise:** the existing repo already had four workflows
(`ci`, `docker`, `pr-pipeline`, `release`) all on GitHub-hosted runners,
none of which deploy. So the two new files don't collide with existing
ones — they're net-new, not replacements. I kept the original four
untouched.

**Surprise 2:** the deploy script's sudo dependency drove a real
decision — I considered making `deploy.sh` run *as* the `fhirsmith` user
(no sudo at all) but then `systemctl restart` and `rsync` to
`/opt/...` would have failed. The compromise is a narrow sudoers entry
in the runbook rather than NOPASSWD:ALL.

Time actual: ~55 min (vs. 3.5 h estimate — way under, because the
plan absorbed most of the design work). Difficulty actual: Medium —
the design choices (atomic symlink flip, retention policy, narrow
sudoers, manual approval via `environment:` rather than branch
protection) each took thought even though no single one was hard.
