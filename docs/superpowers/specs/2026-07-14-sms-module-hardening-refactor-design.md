# SMS Module — Aggressive Hardening & Refactor

**Date:** 2026-07-14
**Scope:** Full aggressive refactor of the SMS module to the payment-module quality bar.
**Status:** Design — implementation in progress on `master` (no auto-commit; manual review).

## 1. Goal

The SMS module is competently built but **single-vendor (Aliyun hard-wired)** and sits below
the payment bar on vendor abstraction, delivery-receipt handling, terminal-state safety,
opt-out, and reconciliation. This refactor rebuilds it as a vendor-agnostic transactional SMS
platform: a self-registering adapter registry (so a new vendor is one file), delivery-status
integrity (terminal guards + reconciliation + DLR webhooks), regulatory opt-out handling, and
E.164 normalization. Schema may change freely (brand-new app). A real second vendor
(**Twilio**, webhook-DLR) is added to prove the abstraction end-to-end.

## 2. Bugs fixed (from audit)

| # | Bug | Fix |
|---|-----|-----|
| 1 | `mark_*!` do unconditional `update!` — a late DLR/query flips `delivered` back to `failed` | `TERMINAL_STATUSES` + monotonic guards; `delivered` is the success floor |
| 2 | Idempotency check-then-insert race → unhandled `RecordNotUnique` 500 | Race-safe find-or-create; activity returns the existing row on `RecordNotUnique` |
| 3 | `TransportError` leaves an orphaned `pending` row, no retry/reconcile | Reconciliation cron resolves ambiguous `pending`/`sent`; dead-letters stuck rows |
| 4 | Non-atomic rate-limit/daily-cap (TOCTOU) | Documented vendor-authoritative backstop; window check tightened; kept cheap on SQLite |
| 5 | No E.164 — rate-limit/idempotency keyed on raw `to`; prefix-variance bypass | `Sms::PhoneNumber` normalizes to E.164 at the contract boundary; all keys use it |
| 6 | No DLR webhook ingestion; `vendor_message_id` unindexed | Vendor-agnostic DLR webhook controller + index on `vendor_message_id` |
| 7 | No status reconciliation; `sent` never progresses | `Sms::Cron::ReconcileMessages` (poll vendors) wired into `config/recurring.yml` |
| 8 | No STOP/opt-out handling or suppression | `sms_opt_outs` ledger, send-time suppression, inbound STOP webhook |
| 9 | `daily_cap_for` swallows JSON parse errors | Quota resolver logs malformed tenant config instead of masking it |
| 11 | Per-phone windows hard-coded to Aliyun's numbers for all vendors | Windows declared per-adapter (`rate_limit_windows`) |

## 3. Vendor abstraction (the headline rebuild)

- `Sms::Adapters::Base` gains `key`, `display_name` (i18n), `default_display_name`,
  `config_fields`, `credential_label`, `rate_limit_windows`, `delivery_mechanism`
  (`:poll` | `:webhook`), `register!`, `default!` — mirroring `Captcha::Providers::Base`.
- `Sms::Adapters` registry: `for`, `keys`, `default_key`, `ensure_loaded!`.
- `Sms::Adapters::Aliyun` — `register!`/`default!`, `:poll` mechanism, config fields
  (sign_name, region), unchanged golden-tested signer.
- `Sms::Adapters::Twilio` — one new file: REST `Messages.json` (basic auth), `:webhook`
  mechanism, `parse_delivery_receipt` (MessageSid/MessageStatus) + `parse_inbound` (STOP),
  X-Twilio-Signature verification. Proves the abstraction with a webhook vendor.

## 4. Data model

- **`sms_credentials`** → vendor-keyed: add `provider`, `config` (JSON blob for sign_name/
  region/from/messaging_service_sid), keep `access_key_id` + encrypted `access_key_secret`,
  `mode`, `status`; unique `(provider, mode)`. (Backfill existing rows as `aliyun`.)
- **`sms_templates`** → `provider_template_codes` (JSON `{"aliyun":"SMS_123","twilio":"HX…"}`)
  replacing the vendor-specific `aliyun_template_code`; `adapter.provider_code(template)`.
- **`sms_messages`** → add `provider`, index `vendor_message_id`, index `status`;
  `mark_*!` terminal guards.
- **`sms_opt_outs`** (new): `customer_id`, `provider`, `phone_e164`, `reason`, `created_at`;
  unique `(customer_id, phone_e164)`.

## 5. Delivery integrity

- **Reconciliation cron** `Sms::Cron::ReconcileMessages` → for `:poll` vendors, query
  non-terminal messages older than a grace window and transition with terminal guards; a
  `pending` row with no `vendor_message_id` past a max-age is dead-lettered to `failed`
  (documented: Aliyun SendSms is not idempotent, so re-send isn't safe). `Sms::ReconcileMessagesJob`
  + `config/recurring.yml`.
- **DLR webhooks** (public, category c) `Sms::WebhooksController`
  `POST /sms/webhooks/:provider/:kind` (delivery|inbound) → `adapter.verify_webhook!` →
  `parse_delivery_receipt` updates messages by `vendor_message_id`; `parse_inbound` STOP →
  opt-out ledger. Signature-verified; no auth.

## 6. Opt-out & suppression

- Send activity checks the opt-out ledger before persisting → `Sms::Errors::Suppressed`
  (handoff returns a `suppressed` status; SendsController maps to 403/JSON).
- Inbound STOP webhook writes the ledger; admin read surface lists opt-outs
  (`/:cid/admin/modules/sms/opt_outs`).

## 7. UI / conventions

- Platform credential new/edit forms become a **provider-aware ViewComponent** rendering
  `config_fields` dynamically (like captcha's `SettingsComponent`) so adding a vendor needs
  no UI change. Provider selector on the index.
- Observability: `Sms::Instrumentation` subscriber on a `sms.send` notification.
- Module identity de-vendored: "SMS (Aliyun / China)" → "SMS".

## 8. Out of scope (noted)

- **Segment/cost accounting** — template bodies live vendor-side (Aliyun template codes), so
  segment counting isn't computable in-app; skipped deliberately.
- **Monthly quota / quiet-hours** — daily cap already exists; not expanded here.

## 9. Testing

Spec per layer + new: adapter registry, Aliyun (keep golden signer) + Twilio (send, DLR parse,
inbound STOP, signature), PhoneNumber, Message terminal guards, idempotency race, reconcile
cron (poll + dead-letter), webhooks controller (signature reject, DLR update, STOP→opt-out),
opt-out suppression, quota resolver, credential/component, request specs incl. multi-tenant
isolation on the message list + opt-out list. i18n en/zh-CN parity.
