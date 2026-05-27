# 01 — Customize the FHIR CapabilityStatement

## Goal

When a FHIR client hits `/tx/r4/metadata` (or any other endpoint exposed by the
`tx` module), the returned `CapabilityStatement` resource should identify
**FHIRTX** as the publisher and carry FHIRTX-branded contact, description, and
copyright — without breaking any upstream conformance.

## Approach

`tx/workers/metadata.js` builds the CapabilityStatement at request time from a
config object handed in by `tx/tx.js` (lines 172–185). All fields we care
about are already config-driven; we only need to:

1. Add the missing `publisher` and `copyright` fields to the builder.
2. Update the defaults in `tx/tx.js` so a fresh install of *this* fork
   ships with FHIRTX-flavored values out of the box.
3. Leave the fields overridable via `config.modules.tx.*` so the same binary
   can be re-branded for a different customer (e.g. EMS Health) with only a
   `config.json` edit.

No JSON CapabilityStatement file ships with the repo — it's all runtime —
so this is a code-defaults change, not a static-file change.

## Fields set

| FHIR field    | New default                                                            |
| ------------- | ---------------------------------------------------------------------- |
| `publisher`   | `"FHIRTX"`                                                             |
| `contact[]`   | `[{ name: "FHIRTX", telecom: [{ system: "email", value: "benjamin.arfa.pro@gmail.com" }, { system: "url", value: "https://fhirtx.example" }] }]` |
| `name`        | `"FHIRTXTerminologyServer"`                                            |
| `title`       | `"FHIRTX FHIR Terminology Server"`                                     |
| `description` | `"FHIRTX-branded FHIR terminology server, built on FHIRsmith."`        |
| `copyright`   | `"© 2026 FHIRTX. All rights reserved. Built on FHIRsmith (BSD-3)."`    |
| `software.name` | `"FHIRTX (FHIRsmith)"`                                               |

Existing fields untouched: `status`, `kind`, `fhirVersion`, `format`, `rest`,
`instantiates`, `extension` — all of these describe what the server *does*, not
who runs it.

## Estimation

- Coding: 20 min
- Manual smoke test (boot server, `curl /tx/r4/metadata`): 20 min
- Doc update + commit: 20 min
- **Total: ~1.5 h**

## Difficulty

**Easy.** All values are already parameterized; we're adding two new keys and
updating defaults. The only "gotcha" is keeping the CapabilityStatement valid
per FHIR R5 — `publisher` is a `string`, `copyright` is a `markdown`, both are
optional, both pass the existing validator.

## Steps

1. In `tx/workers/metadata.js#buildCapabilityStatement`, add:
   - `publisher: this.config.publisher`
   - `copyright: this.config.copyright`
   Both gated on truthy so the field is omitted if the config doesn't set it,
   keeping back-compat with existing configs.
2. In `tx/tx.js` where `MetadataHandler` is instantiated (~line 173), add
   `publisher`, `copyright` to the config object and update the existing
   `softwareName`/`name`/`title`/`description`/`contactUrl` defaults to FHIRTX
   values.
3. Smoke-test locally:
   ```bash
   FHIRSMITH_DATA_DIR=./data npm start &
   curl -s http://localhost:3000/tx/r4/metadata | jq '{publisher, contact, copyright, name, title}'
   ```
4. Commit with subject `feat(metadata): brand CapabilityStatement as FHIRTX`.

## Outcome

*(filled in by 90_trace.md after execution)*

- Both `publisher` and `copyright` were added to `buildCapabilityStatement`
  and gated on truthy values so omitting them in `config` produces a clean
  CapabilityStatement with no empty keys.
- Defaults in `tx/tx.js` now resolve to FHIRTX values when `config.modules.tx`
  does not override them. A re-brand requires zero code changes — only a
  `config.json` edit.
- Smoke test (booting the server end-to-end) was **skipped** because the tx
  module requires a populated library YAML and validator (out of scope for
  a config change). Instead, an isolated unit-style smoke was used: required
  `tx/workers/metadata.js`, called `new MetadataHandler(...).buildCapabilityStatement(...)`,
  and asserted the new fields appear. See `90_trace.md` for the script.
