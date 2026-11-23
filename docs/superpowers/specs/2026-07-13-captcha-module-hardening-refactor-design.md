# Captcha Module — Aggressive Hardening & Refactor

**Date:** 2026-07-13
**Scope:** Full aggressive refactor of the Captcha module to the payment-module quality bar.
**Status:** Design — implementation in progress on `master` (no auto-commit; manual review).

## 1. Goal

Bring Captcha up to a professional, multi-tenant bot-defense standard: eliminate the
security-relevant bugs first (the fake off-switch, the fail-open-on-4xx bypass, the
non-functional multi-provider abstraction), then add the integrity machinery a real captcha
integration is expected to have (request context, replay/single-use, configurable fail
policy, audit log, real health probe, observability), then prove the vendor abstraction with
a genuine second provider. Schema may change freely (AGENTS.md: brand-new app, no
backward-compat burden). The single-file "add a vendor" contract is preserved.

The module is **architecturally sound** already — `Captcha::Providers::Base` + a
self-registering registry, a thin `ProviderSettings` model, a stateless `Verify` activity,
and a vendor-agnostic `WidgetComponent`. This effort hardens the correctness underneath that
structure and makes the multi-provider promise actually work end-to-end.

## 2. Bugs fixed (from audit)

| # | Bug | Fix |
|---|-----|-----|
| B1 | `enabled` is a dead flag — off-switch does nothing (`verify.rb`, `widget_component.rb` gate only on `configured?`) | `enabled` becomes the real switch: `ProviderSettings.active` returns the enabled+configured row; verify + widget gate on it |
| B2 | No active-provider selection — `.active` is hardwired to the default (Aliyun) | Platform owner selects the active provider (single-active, enforced by partial unique index + update activity); `.active` respects the selection |
| B3 | Fail-open on `:configuration_error` (4xx) is an attacker-reachable bypass | Configurable **fail policy** (`fail_open`/`fail_closed`); sensitive actions default fail-closed; 4xx no longer silently passes under fail-closed |
| B4 | Hot-row `update_columns` on the single global row on every public submit | Replaced with a `captcha_verifications` audit log; health tracking moves to a real **test-connection** probe off the request path |
| B5 | Hard-coded English strings (`" updated."`, provider `display_name`/`config_fields` labels, contract messages) | All I18n (en byte-identical + zh-CN parity); providers declare stable keys, translated in the accessor at call time |
| B6 | `find_or_create_by!` race on `.active`/`.for_provider` | Rescue `RecordNotUnique` → retry find (idempotent create) |
| B7 | `pages_with_captcha_count` is an unindexed `LIKE` scan + in-Ruby filter | `json_extract` on the JSON payload (per repo convention) |
| B8 | Promised fail-open flash keys (`unreachable`/`configuration`) are never shown | Surface the localized fail-open notice to the user |
| B9 | Config field can't be cleared back to blank | Explicit blank-clear supported (secrets still keep-existing on blank) |

## 3. Industry-standard enhancements

- **Verification request context** — a `Captcha::VerificationContext` value object carries
  `verify_param`, `remoteip`, `user_agent`, `hostname`, `action`. Threaded through
  `Verify.call(context:)` → `provider.verify(settings:, context:)`. This is the prerequisite
  for any score-based / remoteip-validating provider (the single biggest structural gap).
- **Replay / single-use** — app-layer defense-in-depth: a verified token's SHA-256 digest is
  recorded with a unique index; reuse within the window is rejected (`:replayed` → block).
- **Configurable fail policy** — per-provider default (`fail_open`) + per-action override;
  auth-grade actions (`sign_up`, `password_reset`) default `fail_closed`.
- **Risk score model** — provider results may carry `score`; a `score_threshold` config gates
  score-based providers generically (Aliyun 2.0 is binary, so unused there; wired for the
  next provider).
- **Second provider: Cloudflare Turnstile** — one new file
  `app/services/captcha/providers/turnstile.rb` (siteverify + remoteip + hostname/action
  validation) + `captcha_turnstile_controller.js`, proving active-provider selection and
  context threading end-to-end under the single-file rule.
- **Real test-connection probe** — `Captcha::Activities::TestConnection` does a lightweight
  credential probe (off the request path), writes `last_health_check_*`; platform-owner
  "Test connection" button mirrors Payments' gateway connection test.
- **Observability** — a `Captcha::Instrumentation` subscriber consumes the already-emitted
  `captcha.verify` notification (currently unconsumed): structured logging + counters.
- **Reusable, action-aware protection** — `CaptchaProtectable` becomes generic
  (`protect_with_captcha action:, fail:`), records request context, dedupes the
  module-enabled check onto the shared `FeatureModules::Module.enabled?` helper. Wiring
  captcha into the auth sign-up / password-reset forms is delivered with the **authentication**
  module refactor (those views live there); the mechanism ships ready here.

## 4. Data model

- **New** `captcha_verifications` (audit log + replay ledger): `customer_id` (nullable —
  verification happens in a tenant context but config is global), `provider`, `action`,
  `outcome`, `score`, `remoteip`, `token_digest`, `hostname`, `created_at`. Unique index on
  `(token_digest)` for single-use; index on `(customer_id, created_at)`. **Not** TenantScoped
  (written on the public request path before/around tenant resolution; `customer_id` best-effort).
- **`captcha_provider_settings`** gains `fail_policy` (string, default `open`) and
  `score_threshold` (decimal, nullable). `enabled` keeps its column but gains real meaning +
  a partial unique index `where enabled = true` (single active provider).

## 5. Out of scope (noted, not built here)

- **App-wide rate limiting** (rack-attack) — a cross-cutting infra concern, not captcha-owned.
- **Wiring captcha into auth forms** — delivered with the authentication refactor (task #9).

## 6. Testing

Spec per layer (model, activity, contract, provider incl. Turnstile golden request, concern,
component, request), plus: `enabled=false` disables; active-provider switch; attacker 4xx →
fail-closed blocks; replay rejection; fail-policy matrix; i18n parity. JS at 100% Vitest
lines/branches for both Stimulus controllers.
