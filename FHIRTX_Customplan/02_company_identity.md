# 02 — Custom company identity across the solution

## Goal

Beyond the FHIR CapabilityStatement, propagate the **FHIRTX** identity to every
surface where the FHIRsmith name appears to an operator, end user, or
container registry — without removing upstream attribution.

## Approach

Touch four classes of surface:

1. **Process** — startup banner in `server.js`, HTTP `Server:` response header,
   so `journalctl -u fhirsmith-prod` and `curl -I` both reveal FHIRTX.
2. **Container** — Dockerfile OCI image labels (`org.opencontainers.image.*`)
   so the image in GHCR carries FHIRTX metadata.
3. **package.json** — keep `name: "fhirsmith"` (upstream npm name, do not
   reuse) but add custom-fork metadata (`vendor`, `customization`,
   `customizedBy`) so `npm view` and tools that inspect package.json see the
   FHIRTX fork.
4. **README** — add a short top-of-file FHIRTX customization callout that
   *complements* the upstream README rather than replacing it. Upstream
   contribution flow and license remain untouched.

Logo/asset replacement is intentionally **out of scope** for this pass —
that's design work, not config work. The PNG (`FHIRsmith.png`) stays as-is
until a FHIRTX logo is provided.

## Fields / files touched

| File                          | Change                                                          |
| ----------------------------- | --------------------------------------------------------------- |
| `server.js` (startup banner)  | Add a "FHIRTX customization" line below the FHIRsmith banner    |
| `server.js` (middleware)      | Set `Server: FHIRTX/<version> (FHIRsmith)` response header      |
| `Dockerfile`                  | Add `org.opencontainers.image.*` labels                         |
| `package.json`                | Add `vendor`, `customization`, `customizedBy` keys              |
| `README.md`                   | Prepend short "FHIRTX customization" section                    |

## Estimation

- Coding: 45 min
- Manual verification (`curl -I`, `docker inspect` if a build is feasible): 30 min
- Commit: 15 min
- README copy: 30 min
- **Total: ~2 h**

## Difficulty

**Easy–Medium.** Most of this is one-line edits. The medium part is keeping
the FHIRsmith identity intact (it's BSD-3 and operators need to know what's
under the hood) while making FHIRTX visible — a content-design decision more
than a code one. Resolved by always saying `"FHIRTX (FHIRsmith)"` or
`"powered by FHIRsmith"`, never just `"FHIRTX"` standalone.

## Steps

1. **server.js startup banner**: add a line after the existing `FHIRsmith v…`
   line: `FHIRTX customization (powered by FHIRsmith v…)`.
2. **server.js HTTP header**: insert a small middleware that sets
   `Server: FHIRTX/<version>` for every response. Placed alongside the
   `X-Request-Id` middleware near top of the express app.
3. **Dockerfile labels**: add `LABEL` instructions for
   `org.opencontainers.image.title`, `description`, `vendor`, `source`,
   `licenses`, `authors`.
4. **package.json extra metadata**: add
   ```json
   "vendor": "FHIRTX",
   "customization": "FHIRTX",
   "customizedBy": "Benjamin Arfa <benjamin.arfa.pro@gmail.com>"
   ```
   Leave `"name": "fhirsmith"` and `"author"` unchanged.
5. **README**: prepend a short admonition-style section titled `## FHIRTX
   customization` that explains this is a branded fork and links to
   `FHIRTX_Customplan/` for details.
6. Commit with subject `feat(branding): FHIRTX identity across server, image, docs`.

## Outcome

*(filled in by 90_trace.md after execution)*

- `server.js` startup banner picks up FHIRTX from
  `packageJson.customization` so a re-brand (FHIRTX → EMS Health) is a
  single JSON edit, mirroring the CapabilityStatement story.
- `Server:` header middleware is `app.use(...)` registered before the body
  parsers so it applies even to error responses thrown by the parsers.
- Dockerfile OCI labels are written against `${VERSION}` (the existing
  `ARG VERSION`) so each image carries its own version, not a hard-coded one.
- `package.json` carries `vendor`/`customization`/`customizedBy` without
  changing the npm `name` (`fhirsmith`) or `author` (Health Intersections),
  so upstream npm semantics are preserved and rebasing onto upstream is
  one-shot.
- README customization callout is the very first H2, prepended above
  upstream's H1 banner so it can't be missed but doesn't displace anything.
