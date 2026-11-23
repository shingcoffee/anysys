# Email (Transactional) Module — Aggressive Hardening & Refactor

**Date:** 2026-07-14
**Scope:** Full aggressive refactor of the transactional Email module to the payment/SMS bar.
**Status:** Design — implementation on `master` (no auto-commit; manual review).

## 1. Goal

Email is the least-modernized of the four vendor modules: a single hard-wired SMTP transport
(ActionMailer), no provider registry, no terminal-state guards, no suppression, no
bounce/complaint ingestion, no dead-letter/reconciliation, no instrumentation, and a confusing
`Email::` (services) vs `Emails::` (models/mailers) namespace split. This refactor brings it to
the SMS/Payments bar: a self-registering provider layer (SMTP + a real API vendor), a
terminal-guarded delivery state machine, a suppression list wired to bounce/complaint webhooks,
race-safe idempotency, dead-letter + reconciliation, and observability. It has a solid
Activity+Contract skeleton and a gem-based DKIM signer to build on.

Shared with `email_campaigns` (next module): `Emails::Message`, `Emails::Template`, the
`DeliveryMailer` transport, `Email::Gateway`. Changes here keep campaigns working; the
transactional/marketing boundary is finalized in the campaigns refactor.

## 2. Bugs fixed (from audit)

| # | Bug | Fix |
|---|-----|-----|
| 1 | `mark_*!` are bare `update!` — a retry/observer can regress `sent`/`delivered` | `TERMINAL_STATUSES` + monotonic guards; `delivered` is the success floor |
| 2 | Transactional idempotent send is racy — `RecordNotUnique` escapes as a 500 | Race-safe find-or-create returns the existing row (campaign path already does this) |
| 3 | No suppression list — hard bounces re-send forever | `Emails::Suppression` ledger + send-time check + auto-suppress on hard bounce/complaint |
| 4 | Daily cap counts campaign mail against the transactional cap | Cap counts only `message_type: transactional` (and excludes failed/suppressed) |
| 7 | `DkimSigner` RSA parse can raise mid-delivery, uncaught | Rescue `OpenSSL::PKey::PKeyError` → skip signing + log (consistent with `dkim_dns_txt_record`) |
| 8 | `mark_failed!` in the mailer rescue can clobber a `sent` row | Terminal guard makes `mark_failed!` a no-op once `sent`/`delivered` |

## 3. Provider abstraction (headline rebuild)

- `Emails::Providers::Base` + `Emails::Providers` registry + `register!`/`default!` (mirrors
  `Sms::Adapters`): `key`, `display_name`, `config_fields`, `credential_label`,
  `delivery_mechanism` (`:none` for SMTP — status stops at `sent`; `:webhook` for API vendors),
  `deliver(message:, credential:)` → `{ provider_message_id:, raw: }` (raises ApiError/TransportError),
  and webhook hooks `verify_webhook!` / `parse_events(request)` (delivery/bounce/complaint).
- `Emails::Providers::Smtp` — wraps the existing `DeliveryMailer`/SMTP path (`:none` mechanism).
- `Emails::Providers::Postmark` — one new file: send via the Messages API (OutboundHttp),
  `:webhook` mechanism, `parse_events` for Delivery/Bounce/SpamComplaint, signature/basic-auth
  verification. Proves the abstraction and lights up the bounce→suppression machinery.
- Delivery dispatch unified through `Emails::DeliverMessageJob(message_id, mode)` which resolves
  the provider from the credential and calls `provider.deliver`; SMTP delegates to the mailer.

## 4. Data model

- **`email_credentials`** → vendor-keyed: add `provider`, `config` (JSON: host/port/username/
  auth/ssl/starttls/domain/dkim_* for SMTP; server/stream for API), keep encrypted `password`
  (SMTP password / API token), `mode`, `status`; unique `(provider, mode)`. Backfill existing
  rows as `smtp`.
- **`email_messages`** → add `provider`, `provider_message_id` (+ index); `STATUSES` gain
  `complained` + `suppressed`; terminal guards.
- **`email_suppressions`** (new): `customer_id` (nullable = global), `email`, `reason`
  (`hard_bounce`/`complaint`/`manual`), `provider`, `created_at`; unique `(customer_id, email)`.
  NOT TenantScoped (webhook-written).

## 5. Delivery integrity

- **Suppression:** send checks `Emails::Suppression.suppressed?(customer_id:, email:)` before
  persisting → `suppressed` message, no dispatch. Bounce/complaint webhooks auto-suppress.
- **Webhooks** (public, category c) `Emails::WebhooksController`
  `POST /email/webhooks/:provider/:kind` (delivery|bounce|complaint) → `verify_webhook!` →
  `parse_events` updates messages by `provider_message_id` (terminal guards) and writes
  suppressions. Signature-verified; no auth.
- **Reconciliation + dead-letter:** `Emails::Cron::ReconcileMessages` dead-letters messages
  stuck in `queued` past a grace window (delivery job died) to `failed`. `config/recurring.yml`.
- **Observability:** `Emails::Instrumentation` subscriber on an `email.send` notification.

## 6. Namespace unification

Consolidate the service layer from `Email::` to `Emails::` (models/mailers are already
`Emails::`) so the module is single-namespaced like `Sms::`. Mechanical rename with the full
spec suite as the safety net; `email_campaigns` references updated in lockstep. (Deferred only
if blast radius proves unsafe — decided during implementation.)

## 7. Out of scope (noted)

- Per-tenant verified sender identity (one platform sender for now).
- Deep SPF/DMARC alignment beyond a From-domain vs DKIM-`d=` consistency check.

## 8. Testing

Provider registry + Base, Smtp + Postmark (send, event parse, signature), Message terminal
guards, idempotency race, Suppression model + send-time check, webhooks controller (signature
reject, bounce→suppress, delivery→delivered), reconcile/dead-letter cron, instrumentation,
daily-cap-by-type, DKIM parse-rescue; multi-tenant isolation on message/suppression lists.
i18n en/zh parity. JS 100% for any new Stimulus (provider-aware credential form).
