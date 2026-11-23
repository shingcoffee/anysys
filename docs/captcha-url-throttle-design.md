# Captcha URL throttle — design

**Date:** 2026-09-02  
**Status:** Locked (approach 1; user: do not wait for further confirmation)

## Problem

Public Page records and platform public forms currently embed a captcha widget whenever a boolean toggle is on. Ordinary traffic should pass. Captcha appears only after a per-URL, per-IP access throttle is exceeded. After a pass, the visitor continues to the original URL, including replaying the original POST (files included).

## Locked decisions

- Cover **Page records and platform forms** (sign-in, sign-up, passwords, MFA, checkout, unsubscribe, OAuth authorize, discovered GET+mutate public forms).
- URL identity: **templates** for platform forms (`/auth/sign_in`, `/:customer_id/payments/checkout`) and shared pages (`/:customer_id/page/{uuid}`); **exact** paths for customer-owned public pages (`/42/page/{uuid}`).
- Default: **100 requests / 5 minutes / IP**. No unlimited / off.
- Presets: 5/1 min, 20/1 min, 100/5 min, every hit, plus custom N (1–10,000) per M minutes (1–60).
- After pass: grant for the **rest of the window**; every-hit grant is **5 minutes**.
- Gate: **rack-attack** at the front; dedicated public challenge page; no widget on target pages.
- Over-limit POST: snapshot (params + Active Storage files) then **one-time server-side replay**.
- Admin UI: compact **select + custom fields**, save on change. Page-builder “Require captcha” removed.
- Settings cached **~60s**. Fail-open if cache/store or captcha vendor is down for pages; auth-grade surfaces fail-closed when over-limit and captcha is unavailable.

## Architecture

```
request
  → Rack::Attack (Captcha::RackGate)
       match URL → increment per IP+rule via Rack::Attack.cache (Rails.cache / MemoryStore in test)
       under limit or grant? → Rails
       over limit → snapshot POST if needed → 302 /captcha/challenge?return_to=&snapshot=
  → Captcha::ChallengesController
       widget + verify
       success → grant + replay POST or 302 GET return_to
```

`CaptchaProtectable` no longer requires a widget token on the target form. Target pages/forms never render `Captcha::WidgetComponent`. Only the challenge page does.

## Data

Table `captcha_url_throttles`:

| Column | Notes |
|---|---|
| `match_kind` | `template` or `exact` |
| `url_pattern` | stored URL |
| `limit_count` | null when `every_hit` |
| `period_seconds` | null when `every_hit` |
| `every_hit` | boolean |
| `customer_id` | **null** for platform templates and shared pages (platform-wide policy, same justification as `captcha_surface_settings`); set for tenant exact URLs |
| `surface_key` | optional, platform catalog identity |
| `page_id` | optional, Page identity |

Unique `(match_kind, url_pattern)`. Missing row → default 100/5 min.

Boolean `Captcha::SurfaceSettings.enabled?` and `Page#captcha_enabled` are **retired for enforcement**. Do not write them from the new UI.

Settings cache key `captcha/url_throttles`, TTL 60s, busted on write.

## Matching

Most specific wins:

1. Exact `url_pattern` == request path
2. Longest matching template (`:customer_id`, `:uuid`, `:token` → one path segment; shared page templates pin the UUID)
3. Unconfigured `/:customer_id/page/:uuid` → default
4. Unconfigured platform surface (catalog path, including sibling routes on the same surface such as `/auth/password` with `/auth/password/new`) → default

Skip: paths containing `/admin` or `/member`; `/captcha/challenge`; health; webhooks; Active Storage; `/rails/`; assets.

## Challenge, grant, replay

- `return_to` must be a relative path that matches a throttleable URL.
- Grant cache key: `captcha:grant:{rule_id_or_pattern}:{ip}`.
- POST snapshot: one-time token, bound to IP, TTL 10 minutes, 5MB per file. Rebuild `ActionDispatch::Http::UploadedFile` from blobs; inject current CSRF; `Rails.application.call` with grant already set so the gate allows the replay.
- Oversize snapshot: no replay; after pass, GET the form.

## Authorization

- Platform form + shared-page throttles: owner / `81721200` only (`PATCH` under platform captcha module settings).
- Customer exact URLs: `/:cid/admin/settings/modules/captcha` admin or owner-in-tenant; `Page.for_current_customer`; shared/cross-tenant → 404.
- Challenge: public.

## Out of scope

New vendors, fail-policy UI, verification-log changes, member settings, per-tenant overlay of a shared page throttle, site-wide non-URL throttle.
