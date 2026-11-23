# I18n (English + 简体中文) — Design

Date: 2026-07-09

## Goal

Support two UI languages across the whole application — **English (`en`, default)** and
**Simplified Chinese (`zh-CN`)** — so that every user-visible wording on admin, member, and
public pages is rendered through Rails I18n (`t(...)`) and localizes with the active locale.

`zh-CN` is already the established Chinese code in this repo (`captcha.zh-CN.yml`).

## Locale resolution (per request)

`SetLocale` controller concern (included in `ApplicationController`) resolves in priority order,
first hit wins:

1. `params[:locale]` — explicit switch (only if in `available_locales`)
2. `current_user.locale` — persisted per-user preference (signed-in users)
3. `cookies[:locale]` — anonymous / pre-sign-in preference
4. `Accept-Language` header — parsed via `http_accept_language`, best match among available
5. `I18n.default_locale` (`:en`)

Runs as `around_action` so the locale is reset after the request. Also sets `<html lang>`.

## Persistence & switching

- `users.locale` — nullable string column (nil = follow the fallback chain).
- `LocalesController#update` at **`PATCH /locale`** (public URL category — anonymous users may
  switch too). Persists to `current_user.locale` when signed in, always writes `cookies[:locale]`,
  then redirects back (`redirect_back fallback_location: root_path`). Only accepts a locale in
  `available_locales`.
- `LocaleSwitcherComponent` — ViewComponent (Tailwind + a small Stimulus dropdown controller)
  rendered in the admin Topbar, the Member shell, the auth/AppShell, and the public page layout.

## Config

- `config.i18n.available_locales = [:en, :"zh-CN"]`
- `config.i18n.default_locale = :en`
- `config.i18n.fallbacks = true` (missing `zh-CN` key falls back to `en` — no raw key ever shown)
- Gems: `rails-i18n` (zh-CN plurals/date/number formats), `http_accept_language` (header parsing).

## String extraction

Every visible string in `app/views/**` and `app/components/**` moves into locale YAML and is
referenced via `t(...)`. Locale files are **namespaced per area** (matching the existing
`captcha.*.yml` convention): `admin.en.yml`/`admin.zh-CN.yml`, `member.*`, `public.*`,
`components.*`, etc. This keeps parallel extraction batches from writing the same file.

**Invariant:** the `en` translation is kept byte-identical to the string it replaces, so the
default-locale render is unchanged and existing component/request specs that assert English copy
keep passing.

Out of scope: user-generated content (page names/descriptions, entity data, module entries),
log lines, code comments, admin-authored config values — only static UI chrome is localized.

## Testing

- Request spec for `LocalesController` (persist to user, cookie, invalid locale rejected, redirect back).
- Concern spec for the resolution chain precedence.
- Component spec for `LocaleSwitcherComponent`.
- Model spec for `users.locale` validation.
- Existing suite stays green (en invariant). A `zh-CN` smoke render of a representative page.
