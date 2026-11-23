# Captcha Protected public pages + skip — UX

**Date:** 2026-09-05  
**Nav area:** Maintenance / Platform / Module Settings  
**Audience:** owner on customer `81721200`

## Surface

Two stacked cards on `/81721200/admin/maintenance/platform/module_settings/:captcha_id` (Overview), replacing the single grouped rate list.

## Layout

```
┌ Protected public pages                              (3) ┐
│ Rate-limit these public URLs per IP. …                  │
│ [Search protected URLs                                 ]│
│ Authentication                                          │
│  Sign in  /auth/sign_in     [5/1m|20/1m|100/5m|…] [Skip]│
│ Shared pages                                            │
│  …                                                      │
└─────────────────────────────────────────────────────────┘

┌ Skip captcha                                        (1) ┐
│ These URLs never show a captcha. …                      │
│ [Search skipped URLs                                   ]│
│ Authentication                                          │
│  MFA setup  /:cid/auth/mfa/setup  [Sensitive] [Protect] │
└─────────────────────────────────────────────────────────┘
```

Full width on every breakpoint. Protected above Skip. No left/right split.

## Regions

- **Card header:** `card-header` + `section-header` + `text-caption` subtitle + count `BadgeComponent`.
- **Search:** `input-field` type=search, same pattern as the module catalog search.
- **Groups:** `text-label` on `bg-surface-subtle` bars.
- **Protected row:** name, mono path, optional launched badge, `ThrottlePickerComponent`, ghost **Skip**.
- **Skip row:** name, mono path, warning badge if `fail_closed`, ghost **Protect**.
- **Empty skip:** centered caption inside the skip card.
- **Search miss:** caption toggled by Stimulus.

## Actions

| Action | Where | Result |
|---|---|---|
| Change rate | Protected row picker | PATCH; stays in Protected |
| Skip | Protected row | PATCH `skipped=true`; row moves to Skip |
| Protect | Skip row | PATCH `skipped=false`; row moves to Protected |
| Search | Section input | Client-side filter |

## Empty / error

- Catalog empty: one card with existing empty copy.
- Skip empty: “No URLs skip captcha. Move a protected URL here to turn the challenge off.”
- Protected empty: “No URLs are captcha-protected. Move a skipped URL here to set a rate.”
- Search miss: “No URLs match this search.”

## Components

Reuse: `BadgeComponent`, `ButtonComponent` (ghost, sm, submit), `Captcha::ThrottlePickerComponent`.  
Rewrite: `Admin::Maintenance::Platform::Captcha::ProtectedPagesComponent`.  
New Stimulus: `captcha_page_list_controller.js` (one instance per section).
