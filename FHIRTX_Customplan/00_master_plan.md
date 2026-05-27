# FHIRTX Customization — Master Plan

> Customization of `FHIRsmith` (upstream: `HealthIntersections/FHIRsmith`) for the
> **FHIRTX** brand. Maintained in the fork `benjamin-arfa/FHIRsmith`.
>
> Owner: Benjamin Arfa <benjamin.arfa.pro@gmail.com>
> Started: 2026-05-27
> FHIRsmith version at fork: v0.9.5 (`package.json:3`), tx version 1.9.1.

## Why this fork exists

This fork hosts the **FHIRTX** identity layered on top of FHIRsmith. The goal is to
keep diffs against upstream small and easy to rebase, so customization is concentrated
in three places:

1. **CapabilityStatement defaults** (`tx/tx.js` MetadataHandler config) so the
   FHIR `/metadata` response advertises FHIRTX as publisher/contact/copyright.
2. **Identity surface** (startup banner, HTTP `Server:` header, Dockerfile OCI
   labels, README customization section) so operators and ops dashboards see
   FHIRTX everywhere FHIRsmith is currently surfaced.
3. **Deployment workflow** (GitHub Actions on a **self-hosted runner** living on
   the same bare-metal box that already runs the RCBAS services) so pushes to
   `main` ship to staging and tagged releases ship to production, each on its
   own systemd unit, port, and data directory.

Upstream attribution (BSD-3 license, Health Intersections copyright on source
files) is preserved verbatim — FHIRTX adds branding *on top of* the upstream
notices, never replacing them.

## Sub-plans

| #  | File                              | Topic                              | Est. (h) | Difficulty |
| -- | --------------------------------- | ---------------------------------- | -------: | ---------- |
| 01 | `01_capability_statement.md`      | `/metadata` publisher/contact/etc. |      1.5 | Easy       |
| 02 | `02_company_identity.md`          | Branding across surface area       |      2.0 | Easy–Med   |
| 03 | `03_ci_staging_production.md`     | Self-hosted CI + systemd units     |      3.5 | Medium     |

**Total budget: ~7 hours** of focused work for the config + scaffolding pieces.
Items 01 and 02 are tightly coupled (both touch "company name") and are executed
as one branch / one developer's worth of work. Item 03 is independent enough
that it could be parallelized, but was kept serial here to avoid coordination
overhead on a one-day pass.

## Overall risk

- **Low** for items 01 and 02 — config defaults and metadata, no behavioural
  change to FHIR semantics.
- **Medium** for item 03 — touches systemd and runs on the same box as RCBAS,
  so a misconfigured unit or port collision could disturb an unrelated service.
  Mitigations: distinct ports (3001 staging, 3002 prod), distinct data dirs
  (`/var/lib/fhirsmith-staging`, `/var/lib/fhirsmith-prod`), distinct unit
  names, `systemctl status` health check after deploy, and runner registration
  documented as a **manual step** (token is one-time and from GitHub UI).

## Assumptions baked in (revisit if wrong)

1. Company name placeholder: **FHIRTX**. The CapabilityStatement reads from
   config so a swap to "EMS Health" or another brand is a JSON edit, no code
   change. Where the brand is hard-coded (startup banner default,
   Dockerfile labels), it is also a single-place change.
2. Contact: `benjamin.arfa.pro@gmail.com`. Website is a TBD placeholder
   (`https://fhirtx.example`) — note this in `01_capability_statement.md`.
3. Self-hosted runner has not yet been registered. The runner token is a
   manual step (must be fetched from GitHub UI under *Settings → Actions →
   Runners → New self-hosted runner*); the plan documents the install commands
   but does not execute them.
4. Production deploys are **tag-driven** (`v*`) and gated by a GitHub
   `production` environment for an approval step. Staging deploys
   automatically on push to `main`.
5. RCBAS continues to own ports 8000–8999 on this host. FHIRTX takes 3001
   (staging) and 3002 (prod) to stay clear.

## How to use this directory

- Start with this file for the big picture.
- Sub-plans (`01_*`, `02_*`, `03_*`) hold the actual steps and acceptance criteria.
- `90_trace.md` is the running log — each step's start/end appended as work
  progresses, including surprises and estimate-vs-actual time.
