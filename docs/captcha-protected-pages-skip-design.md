# Captcha Protected public pages + skip — design

**Date:** 2026-09-05  
**Status:** Locked (user: implement; no further confirmation)

## Problem

The platform owner’s Captcha module settings card lists every catalog surface and shared public page with a cramped rate picker. There is no skip. Hardcoded matcher skips (`/admin`, `/member`, webhooks, assets, `/up`) sit beside that UI, so the card is not the source of truth for “should this public URL be captcha-protected?”

## Locked decisions

- Scope: **platform forms + shared public pages** only. Tenant-owned pages stay on Settings / Captcha.
- Layout: **two stacked full-width sections** (not left/right). Top = Protected public pages (rate + Skip). Bottom = Skip captcha (Protect). Every listed identity lives in exactly one section.
- New identities start **Protected** at **100 / 5 min**. Skip is an explicit owner move.
- Auth-grade forms may be skipped like any other row; show a **warning badge** (no confirm dialog).
- This card is the **source of truth** for those identities. Hardcoded policy skips for `/admin`, `/member`, `/rails`, `/assets`, `/up`, and webhook/track prefixes are removed.
- Infra exceptions that are **not** pages on this card:
  - `/captcha/challenge` — loop guard
  - RFC one-click `List-Unsubscribe` POST — mail-client protocol
- Unmatched paths are not challenged (the gate already no-ops when `UrlMatcher.match` is nil).
- Skip storage: `captcha_url_throttles.skipped` boolean (default false). Moving to Skip upserts the row, keeps the last rate, sets `skipped: true`. Protect sets `skipped: false` and restores that rate (or default).
- A skipped stored row **must** match and pass through. It must not fall through to the implicit default rule.

## Enforcement

1. Match platform form template, shared-page template, or tenant exact URL (unchanged).
2. If the matched row is `skipped`, pass through (no count, no challenge).
3. If protected (row or implicit default), apply the rate.
4. If nothing matched, do not challenge.
5. `skip?` is only `/captcha/challenge` (prefix). One-click unsubscribe stays in `RackGate`.

## UI

Two sibling cards, stacked with `gap-4`:

- **Protected public pages** — count, search, grouped rows, rate picker, Skip action.
- **Skip captcha** — count, search, grouped rows, warning badge on `fail_closed` catalog keys, Protect action.

Search is per section, client-side (Stimulus), case-insensitive name/path substring. Empty skip section has a calm empty state. Filter-no-matches has its own copy.

## Out of scope

Tenant Settings / Captcha redesign, freeform URLs, site-wide captcha off, new vendors, challenge-page changes.
