# Payments Module — Aggressive Hardening & Refactor

**Date:** 2026-07-13
**Scope:** Full aggressive rebuild of the Payments module, delivered as sequenced workstreams.
**Status:** Workstreams 1–6 — **fully implemented & verified**. Nothing from the design
remains unbuilt.

**Delivery log (all committed on this branch, each slice suite-verified):**
- WS1 — correctness & security bug fixes (`fd976ba`)
- WS2a — recurring/webhook idempotency & safe deprovision (`409ff0c`)
- WS2b — webhook event dedup ledger + amount verification (`d14b374`)
- WS2c — async refund webhooks + PSP idempotency keys (`8d4c43e`)
- WS2d — vault hygiene (`7c15a7d`)
- WS3a — Money value object, gateway money DRY, Alipay replay window, capability truth-up (`e987346`)
- WS3b — amount-aware two-way reconciliation + ping DRY (`06ff3fe`)
- WS3c — shared JSON HTTP client on Base (`09b6666`)
- WS4a — dispute/chargeback recording, Stripe (`89b59de`)
- WS4b — admin disputes surface (`20003c4`)
- WS4c — PayPal dispute handling, routed via the disputed capture id (`c52ea5d`)
- WS4d — dispute badges on the transactions table (`3b64667`)
- WS5  — WeChat platform-certificate rotation (`d802a39`)
- WS6a — on-session SCA-recovery backend (`5f5be35`)
- WS6b — member SCA-recovery UI (Stripe.js Stimulus, 100% Vitest) (`cc5985a`)

**How the three "hard" items were ultimately solved:**
- **PayPal dispute routing** — dispute bodies carry no `custom_id`, but they DO carry the
  disputed capture id (`resource.disputed_transactions[].seller_transaction_id`), which we
  stored as the payment's `psp_transaction_id`. `PayPal#extract_merchant_id` now resolves the
  tenant from that capture id, so the dispatcher routes + verifies normally.
- **WeChat cert rotation** — avoided the credential-field I18n blocker by NOT adding admin
  fields: certs are auto-fetched from WeChat's `/v3/certificates`, AEAD-decrypted with the
  already-stored APIv3 key, cached per merchant, and selected by the `Wechatpay-Serial`
  header, with the stored key as bootstrap fallback.
- **On-session SCA-recovery** — Stripe's off-session `authentication_required` (402, PI in
  the error) is surfaced as recoverable with its `client_secret`, stashed on the paused sub's
  pending payment; the member completes 3DS via a `payments--sca-recovery` Stimulus controller
  (Stripe.js), and `payment_intent.succeeded` reactivates the subscription.

---

## 1. Goal

Bring the Payments module up to the standard of a professional, multi-tenant payment
platform: eliminate money-losing and cross-tenant defects first, then add the integrity
machinery a real PSP integration is expected to have, then consolidate the four gateways
onto a shared, DRY substrate. Schema may change freely (AGENTS.md: brand-new app, no
backward-compatibility burden).

The module was already **architecturally sound** — a vendor-agnostic `Payments::Gateway`
facade over a self-registering gateway registry, thin ActiveRecord models with `mark_*!`
transitions, stateless Trailblazer-style Activities, and genuinely good webhook
tenant-binding (`signing_matches_payment?`) and per-payment idempotency. This effort
hardens the correctness underneath that structure rather than rewriting the structure.

---

## 2. Refactor / Enhance Principles

These are the principles applied throughout (and the ones every subsequent workstream
must follow):

1. **Correctness before cleverness — money bugs first.** The confirmed financial and
   cross-tenant defects are fixed before any aesthetic refactor. A prettier gateway layer
   on top of a double-charge bug is worth nothing.
2. **Every fix is verified against real source, then a real test run.** Each finding from
   the audit was re-read in the actual code before acting (several "criticals" are
   verified; none were taken on faith), and no change is called done without a green spec
   run as evidence.
3. **Guarded, idempotent state machines.** State transitions never regress a settled
   record (a paid order can't be flipped to failed by a late attempt), terminal states
   short-circuit, and money-moving transitions serialize under `with_lock`.
4. **Fail safe with money.** When an off-session charge cannot complete cleanly
   (SCA required, dead card, decline), the system does **not** advance the billing period
   or grant service — it moves to dunning and stops retrying blindly.
5. **Validate money at the boundary, in the correct currency.** Refunds are capped at the
   captured amount; recurring charges carry the subscription's own currency; cents are
   rounded, never float-truncated.
6. **Tenant isolation is explicit, never implicit.** `TenantScoped` installs **no**
   `default_scope` (its doc comment claiming otherwise is misleading) — so every query
   that renders tenant data must call `for_current_customer` explicitly. Assume nothing.
7. **Least surprise across gateways.** Behaviour that one gateway hardens (webhook replay
   windows, response-code guards, amount checks) should be uniform across all four; a gap
   in one is a bug, not a style choice.
8. **Surgical diffs, honest comments.** Changes are minimal and local; comments explain
   *why* (the failure mode being prevented), and misleading comments are corrected rather
   than left to mislead the next reader.
9. **Stale tests are rewritten to the corrected contract, not deleted.** When a fix
   intentionally changes behaviour, the test that encoded the old (buggy) behaviour is
   updated to assert the new, correct behaviour — and a fresh regression test is added for
   the bug itself.
10. **Sequenced delivery, value first.** Ship the highest-risk fixes (leak, wrong-currency
    charge, over-refund) as a verified increment before starting the larger build-out, so
    each layer can be reviewed and can't be held hostage by the next.

---

## 3. Verified Findings (audit → disposition)

Severity and file references verified against source. "WS" = which workstream fixes it.

| # | Severity | Finding | File (anchor) | WS | Status |
|---|----------|---------|---------------|----|--------|
| L1 | 🔴 Critical | **Cross-tenant read leak**: transactions entries scope not tenant-scoped; `TenantScoped` has no `default_scope`, resolver adds none → any admin sees all tenants' payment logs | `feature_modules/payment/registration.rb:79` | 1 | ✅ Fixed |
| C1 | 🔴 Critical | **Wrong-currency recurring charge**: cron order omits `sub.currency` → USD sub charged in CNY off-session | `cron/charge_due_subscriptions.rb` (`ensure_order_for`) | 1 | ✅ Fixed |
| C3 | 🔴 Critical | **Agreement charge never recorded**: gateway result discarded; payment stuck `created`, order `pending`, yet `advance_next_charge!` runs | `cron/charge_due_subscriptions.rb` (`charge_agreement_subscription`) | 1 | ✅ Fixed |
| C4 | 🔴 Critical | **Unbounded refund**: no cap vs captured/remaining; multiple partials exceed the charge | `activities/refund.rb`, `refunds_controller.rb:13` | 1 | ✅ Fixed |
| C5 | 🔴 Critical | **Paid order flipped to failed** by a later failed attempt on same order | `models/payments/order.rb` (`mark_failed!`) | 1 | ✅ Fixed |
| C2 | 🔴 Critical | **SCA silently dropped**: off-session `requires_action` → `:pending` unhandled, sub advances = free service | `activities/charge_token.rb` | 1 | ✅ Fixed |
| H4 | 🟠 High | **WeChat `trade_state == nil` treated as SUCCESS** | `activities/handle_webhook.rb:53` | 1 | ✅ Fixed |
| BUG5 | 🟠 High | **Dead/removed card retried forever** with no state change | `cron/charge_due_subscriptions.rb` | 1 | ✅ Fixed (dunning pause) |
| BUG4 | 🟠 High | **`advance_next_charge!` drifts** (computes from `now`, not the anchor); missed periods collapse | `models/payments/subscription.rb` | 1 | ✅ Fixed |
| BUG1 | 🟠 High | **Reconcile cron aborts whole batch** on Stripe/PayPal accounts (provider whitelist raises non-Payments error) | `cron/download_bills.rb` | 1 | ✅ Fixed |
| H5 | 🟠 High | **Reconcile is amount-blind & float-truncates cents**; one-directional | `activities/reconcile.rb` | 1 (truncation) / 3 (amount diff) | ◑ Partial |
| — | 🟠 High | **Refund `:failed` stranded in processing** (no terminal branch) | `activities/refund.rb` | 1 | ✅ Fixed |
| H1 | 🟠 High | **No refund webhook handling** → async refunds stuck `processing` forever | `activities/handle_webhook.rb` | 2 | ▢ Planned |
| H3 | 🟠 High | **No amount verification** on webhook/query success → underpayment accepted | `activities/handle_webhook.rb`, `query.rb` | 2 | ▢ Planned |
| H2/M4 | 🟠 High | **No idempotency keys to PSP; no webhook-event dedup table**; cron double-charge under re-entrancy | gateways/*, `handle_webhook.rb`, cron | 2 | ▢ Planned |
| M2 | 🟡 Med | `signing_matches_payment?` ignores `mode` (sandbox/prod ambiguity) | `handle_webhook.rb:24` | 2 | ▢ Planned |
| #2 | 🟡 Med | No global unique index on active `(provider, merchant_id)` backing webhook routing | `models/payments/merchant_account.rb` | 2 | ▢ Planned |
| #3 | 🟡 Med | `Provisioner.revoke` hard-deletes live production credentials on module toggle | `feature_modules/payment/provisioner.rb` | 2 | ▢ Planned |
| M5/BUG6 | 🟡 Med | Pending vault rows are `active` (chargeable placeholder tokens); no reaper | `activities/vault_card.rb` | 2 | ◑ Guarded in WS1; reaper in WS2 |
| DRY | 🟡 Med | ~5 copies each of JSON-API client / `ping` / money-format / signing-string across gateways | `gateways/*.rb` | 3 | ▢ Planned |
| #5/#6 | 🟡 Med | Alipay lacks webhook replay window; WeChat ignores cert-serial rotation | `gateways/alipay.rb`, `wechat_pay.rb` | 3 | ▢ Planned |
| L3 | 🟢 Low | No dispute/chargeback handling; no `payment_intent.payment_failed` | `handle_webhook.rb` | 3 | ▢ Planned |

Legend: ✅ done · ◑ partial · ▢ planned

---

## 4. Workstream 1 — Correctness & Security (DONE)

Implemented surgically with regression tests; **542 payment-domain specs pass**.

**Production changes**
- `errors.rb` — added `PaymentRequiresAction`, `RefundNotAllowed`, `AmountMismatch`.
- `models/payments/order.rb` — `SETTLED_STATUSES`; `mark_paid!/failed!/closed!` now guarded &
  idempotent (C5).
- `models/payments/subscription.rb` — `mark_paused!` (dunning); `advance_next_charge!` now
  advances from the scheduled anchor, not `now` (BUG4).
- `models/payments/payment_method.rb` — `PENDING_TOKEN_PREFIX`, `confirmed?`, `chargeable?`,
  `chargeable`/`confirmed` scopes (BUG5/BUG6 guard).
- `activities/refund.rb` — `validate_refundable!` (captured-only, positive, cumulative-cap)
  inside the lock (C4); `:failed` terminal branch.
- `activities/charge_token.rb` — `:pending` (SCA) → raises `PaymentRequiresAction` (C2).
- `cron/charge_due_subscriptions.rb` — records agreement-charge success on the payment/order
  (C3); copies subscription currency onto the order (C1); guards unchargeable cards; on
  SCA/decline moves the sub to dunning (`paused`) instead of advancing; resets `Current`.
- `cron/download_bills.rb` — restricts to `ReconciliationBill::PROVIDERS` (BUG1); resets `Current`.
- `activities/reconcile.rb` — rounds cents instead of truncating (H5 partial).
- `activities/handle_webhook.rb` — WeChat requires an explicit `SUCCESS` (H4).
- `feature_modules/payment/registration.rb` — transactions scope now `for_current_customer` (L1).
- `admin/modules/payments/refunds_controller.rb` — rescues `RefundNotAllowed`/`ApiError` →
  I18n flash instead of 500. New keys `comp_payments.flash.refunded` / `refund_failed` (en + zh-CN).

**Tests added/updated** — over-refund cap (4 cases), order guarded transitions (4), SCA &
dead-card dunning (2), anchor-based advance & pause (2), `chargeable?`/scope (4), refund
`:failed`, WeChat no-implicit-success, C1/C3 recording assertions; two stale tests rewritten
to the corrected contract.

---

## 5. Workstream 2 — Payment Integrity Layer (PLANNED)

The machinery a professional platform needs. New schema is expected here.

1. **Webhook event ledger + dedup** — new `payment_webhook_events (provider, psp_event_id,
   received_at, payload, status)` with a unique index on `(provider, psp_event_id)`. The
   dispatcher records-then-processes; a duplicate event id is a no-op. Closes replay gaps
   that the per-payment-status check doesn't cover (refunds, setup-intent backfill,
   amount-mutating replays). (M4, L5)
2. **PSP idempotency keys** — send `Idempotency-Key` (keyed on `out_trade_no` /
   `out_refund_no`) on every Stripe/PayPal charge/refund so a transport retry after a
   committed PSP write cannot double-charge. (M4)
3. **Refund webhook handling** — per-gateway refund-notification parse → look up by
   `out_refund_no`/`psp_refund_id` → `mark_succeeded!`/`mark_failed!`, driving
   `recalc_order_status!` to `partial_refund`/`refunded`. (H1)
4. **Amount verification on success** — each success handler extracts the PSP-reported
   amount and refuses `mark_succeeded!` on mismatch (`AmountMismatch`). (H3)
5. **Cron re-entrancy safety** — `SELECT … FOR UPDATE SKIP LOCKED` (or advisory lock) per
   subscription with an in-lock due-recheck; rescue `RecordNotUnique`. (H2)
6. **Webhook routing invariant** — DB unique index on active `(provider, merchant_id)`;
   include `mode` in `signing_matches_payment?`. (#2, M2)
7. **Non-destructive deprovision** — `Provisioner.revoke` disables/archives rather than
   `destroy_all` of live credentials. (#3)
8. **Vault hygiene** — pending vault rows created non-chargeable + a reaper for stale
   `pending:` placeholders. (M5/BUG6)
9. **`Payments::Money` value object** — one currency/minor-unit-aware type wrapping the
   existing RubyMoney (`Billing::CurrencyResolver`), replacing the ad-hoc
   `format("%.2f", cents/100.0)` conversions. Foundation for WS3 gateway DRY.

---

## 6. Workstream 3 — Gateway Consolidation & Advanced Flows (PLANNED)

1. **Shared substrate on `Base`** — extract `JsonApiClient` (json/form body, bearer/basic),
   `ping_via(&probe)`, money formatting (via `Payments::Money`), signing-string builder, and
   `safe_parse`. Removes 3–5 duplicated copies each across the four gateways.
2. **Uniform webhook hardening** — replay/freshness window on Alipay; WeChat platform-cert
   rotation via `Wechatpay-Serial`; consistent response-code guards (Alipay `query`/`close`
   currently swallow failures); terminal refund-status mapping per gateway.
3. **Two-way, amount-aware reconciliation** — compare per-`out_trade_no` amounts, flag local
   successes absent from the PSP bill, compare aggregate totals; split bill types. (H5 full)
4. **Dispute / chargeback + SCA-recovery flows** — handle `charge.dispute.created`,
   `payment_intent.payment_failed`, and an on-session SCA recovery path for paused subs.
5. **Capability truth-up** — align `capabilities`/`supported_flows` with what each gateway
   actually implements (Stripe declares `:reconciliation` but raises; Alipay/WeChat
   implement bills but don't declare it).

---

## 7. Testing Strategy

- Ruby: model + activity + cron + request specs per slice; multi-tenant isolation and
  authorization scenarios are mandatory for any new controller/scope. Full suite
  (`bin/rails parallel:spec`) before final sign-off (cross-cutting state-machine changes).
- JavaScript: any new Stimulus (e.g. SCA-recovery widget) ships at 100% Vitest
  lines/branches per AGENTS.md.
- I18n: every new user-facing string keyed in en + zh-CN in the matching area file.
