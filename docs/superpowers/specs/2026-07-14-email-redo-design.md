# Email Module — Professional Redo (Deep Pass)

**Date:** 2026-07-14
**Module:** 2 of 5
**Method:** Consolidated from three parallel adversarial audits (correctness+security, architecture+tests+i18n, feature-gaps). Top findings verified by direct code reading. Changes on `master`, uncommitted; suite green per slice.

## Overall assessment

A well-structured, vendor-agnostic transport module that already follows the project's best patterns: a clean single-file provider registry (SMTP + Postmark), DKIM via the mature `dkim` gem (crypto **not** hand-rolled — signature empirically verified by the security audit), encrypted credentials at rest, authenticated webhooks (secret verified *before* body is trusted, timing-safe compare), idempotency keys, retry/backoff → dead-letter, and broad, mostly-solid test coverage. Credentials are **platform-global** (one row per provider×mode, owner-only) and suppressions are **global by default** on the shared sending domain — both deliberate and correct for a shared-IP design. The real issues were a latent config-driven lockout, a shared primitive with no output escaping, and a webhook correlation edge case.

## Shipped in this pass (verified, tested, suite green — 572 email/campaign examples)

| # | Sev | Item | Fix |
|---|-----|------|-----|
| **E-ARCH-2** | High (latent) | Malformed `daily_send_cap` (e.g. `"unlimited"`) → `.to_i == 0` → cap 0 → **every send blocked** for the tenant | `daily_cap_for` now `Integer(cap) rescue default + warn`, mirroring the guard SMS already had. Spec added. |
| **E-ARCH-4 / E-BUG-1** | Med | `Gateway.send_raw` (admin test-send) skipped the suppression check its two sibling paths honor → delivers to hard-bounced/complained addresses | `send_raw` now records `status: "suppressed"` and skips dispatch for suppressed recipients. Specs added. |
| **E-SEC-1** | Med | `TemplateRenderer` interpolated variable values into `body_html` with **no escaping** → content/phishing HTML injection via a variable value | HTML-escape interpolated *values* on the `body_html` path only (author HTML + subject/text paths unchanged); plain-text derives from an unescaped interpolation. Specs added. |
| **E-BUG-2** | Low | Webhook event with a blank `MessageID` matched any NULL-`provider_message_id` row and wrongly transitioned it | Correlate only when `provider_message_id` is present. Spec added. |
| **E-SEC-3** | Low | Internal sequential `X-Anysys-Message-Id` header shipped on every SMTP email (volume/enumeration signal) | Interceptor strips it alongside `X-Anysys-Mode`. Spec added. |
| **E-I18N-1** | Med | Bare `f.label` on credential + template forms fell back to English `humanize` → zh-CN users saw English labels | Explicit `t()` labels (new `maint_platform.emails.credentials.form.*` keys in both locales; reused `common.labels.*` for the template form). |
| **E-TEST-1** | High (test) | `DeliverMessageJob` retry/dead-letter path untested; stale comment described the (already-fixed) `instrument` collision as a live bug | Added an end-to-end dead-letter test (transport error → 3 retries → `failed`); corrected the stale comment. |

## Considered and deliberately kept

- **E-SEC-2** (webhook writes a *global* suppression from a body-supplied email even without a correlated message): kept global suppression — on a shared sending IP a hard bounce/complaint is authoritative for every tenant, and the webhook secret is verified before the body is trusted. The uncorrelated-write risk is bounded by that auth; E-BUG-2 already removes the nil-id mis-match. Existing tests codify this behavior.
- **E-SEC-4** (provider error text may carry recipient PII into `failure_message`/logs) and **E-BUG-3** (daily-cap TOCTOU, best-effort) — low severity, left as-is; noted for a future scrub/atomic-counter pass.
- **E-ARCH-1** (dead `daily_limit` credential column, misleading UI) — the authoritative per-tenant cap is the module-config `daily_send_cap`; removing/wiring the platform-credential column is deferred (schema change) rather than rushed.

## Architecture follow-ups (designed, not yet built)

E-ARCH-3 dedupe the three message-creation paths into one persister (also closes the send_raw/campaign divergence structurally); E-ARCH-5 unify the Activity result convention; E-ARCH-6 forward the dropped `provider:` arg in `Gateway.send`; E-ARCH-7 drop vestigial `builder_data`/`scheduled_at` columns (confirm vs campaigns first).

## Maximum-enrichment build set (designed, not yet built)

Ordered by value-to-effort (from the feature-gap audit): (1) **Settings/Emails surface** — closes the four-URL-area violation (area b is missing today); (2) suppression-management UI (add/remove/import/export); (3) deliverability dashboard (SQL aggregates + inline-SVG, zero new schema); (4) open/click tracking (pixel + signed link rewrite, per-tenant toggle); (5) message timeline + provider events + resend (`email_events` table, stop discarding webhook `raw`); (6) template preview-with-vars + token linting + `Versionable` history; (7) scheduled/delayed send + rate throttle (wire the dead `scheduled_at`). Deferred: per-tenant sending domains + SPF/DMARC (refactors the platform-global credential), inbound/Action Mailbox, visual block editor.
