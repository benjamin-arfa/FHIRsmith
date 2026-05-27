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
