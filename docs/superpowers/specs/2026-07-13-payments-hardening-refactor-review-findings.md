# Payments Module — Hardening Refactor Review Findings

- **Date:** 2026-07-13
- **Scope reviewed:** commits `fd976ba^..5977eaa` (WS1–WS6, 17 commits, ~2,700 insertions / 70 files) plus the full current state of the payment module (gateways, activities, models, controllers, cron, dispatcher, schema, specs).
- **Method:** three parallel reviews — correctness/security (diff + current files), AGENTS.md conventions, and staff-level payments-architecture review — with every critical/high claim independently re-verified against the source before inclusion.
- **Design doc under review:** `docs/superpowers/specs/2026-07-13-payments-module-hardening-refactor-design.md`

## Verdict

The refactor is genuinely well-engineered: cross-tenant webhook binding, two-layer idempotency, amount verification, and credential handling are above the bar for this app's scale, and AGENTS.md conventions compliance is a clean pass. However the review found **3 critical defects** (two introduced by this refactor, one operational), **2 high-severity issues**, and a set of medium/low items. The single most impactful finding is operational: **the payment cron jobs are never scheduled, so recurring billing, reconciliation, and vault cleanup do not run at all.**

Statuses: `[ ]` open · `[x]` fixed · `[-]` won't fix.

---

## Critical

### C1. Every JPY (zero-decimal currency) Stripe payment can never complete `[ ]`

- **Where:** `app/services/payments/activities/handle_webhook.rb:37-40` (`stripe_amount_cents`), consumed at `handle_webhook.rb:415-416`; same bug at `handle_webhook.rb:212` (`record_stripe_dispute`).
- **What:** Stripe declares `jpy` in `supported_currencies` (`app/services/payments/gateways/stripe.rb:34`), and charges correctly send `Money#smallest_unit` (¥1000 → `1000` whole yen). But the webhook comparator `stripe_amount_cents` takes Stripe's raw smallest-unit amount (`1000`) and compares it directly against our canonical `amount_cents` (major×100 = `100000`) in `amount_matches?`. The values can never match for a zero-decimal currency.
- **Failure scenario:** member pays ¥1000 by card via Stripe. Stripe captures the money and sends `payment_intent.succeeded` with `amount_received: 1000`. `1000 != 100000` → `reject_amount_mismatch` fires → the payment is **never marked succeeded** even though the money was captured. Since the webhook is the *only* completion path for Stripe card checkout (the synchronous `charge()` only creates the PaymentIntent; confirmation is client-side), this fires on essentially every real JPY Stripe payment. JPY dispute amounts are likewise stored 100× too small.
- **Introduced by:** WS2b (webhook amount verification). Not covered by any spec — `handle_webhook_spec.rb` has no zero-decimal case.
- **Fix direction:** convert the notified Stripe amount back to canonical cents using the inverse of `Money#smallest_unit`, keyed off `payment.payment_order.currency`, before comparing. Add JPY cases to the webhook and dispute specs.

### C2. A transient PSP error during a recurring charge grants a free billing period `[ ]`

- **Where:** `app/services/payments/cron/charge_due_subscriptions.rb:37-48` (`charge_one`), with `app/services/payments/activities/charge_token.rb`.
- **What:** if the gateway raises a raw `Payments::Errors::ApiError`/`TransportError` (transient PSP 5xx/timeout — not a structured decline), the just-created payment row is left at status `"created"` forever (neither `mark_succeeded!` nor `mark_failed!` runs), and the rescue in `perform` only logs — the subscription is *not* paused and stays `due_now`.
- **Failure scenario:** next cron tick on the same calendar day: `ensure_order_for` reuses the same `"sub-<id>-<date>"` order; the idempotency guard `order.payments.where(status: %w[created pending succeeded]).exists?` sees the stuck `"created"` row, treats the period as already settled, skips charging, and calls `sub.advance_next_charge!` — **a full billing period is granted with no charge ever completed.** This is exactly the outcome the WS2a idempotency design exists to prevent; the ApiError/TransportError path just isn't covered.
- **Introduced by:** WS2a. The existing spec (`charge_due_subscriptions_spec.rb:76-94`) only exercises the first tick, never the second tick where the bug fires.
- **Fix direction:** rescue `ApiError`/`TransportError` around the gateway call in both charge paths and `payment.mark_failed!` before re-raising (mirroring what `ChargeToken` already does on a structured `:failed`), and/or pause the subscription on any `Payments::Errors::Error`. Add a two-tick spec.

### C3. The payment cron jobs are never scheduled — recurring billing, reconciliation, and vault cleanup are inert `[ ]`

- **Where:** `app/services/payments/cron/{charge_due_subscriptions,download_bills,reap_stale_payment_methods}.rb`; `config/recurring.yml`.
- **What:** the three cron classes have **zero call sites** outside their own files and specs (verified by grep across `app/`, `config/`, `lib/`). `config/recurring.yml` schedules only `EmailCampaigns::SchedulerJob` and `Billing::DailyBillingJob`. There is no `app/jobs/payments/` wrapper, no rake task, no scheduler entry.
- **Impact:** as-built, recurring subscription charging, dunning, bill download/reconciliation, and stale-vault cleanup do not execute in production unless someone calls `.perform` by hand. A large slice of WS1–WS3 is dead code at runtime. The design doc never mentions job invocation, which is how this stayed invisible.
- **Fix direction:** add recurring solid_queue entries (and thin ActiveJob wrappers, mirroring `Billing::DailyBillingJob` / `app/jobs/billing/daily_billing_job.rb`).

---

## High

### H1. Double-refund hazard: the PSP refund call runs inside the DB transaction `[ ]`

- **Where:** `app/services/payments/activities/refund.rb:12-36`.
- **What:** `Refund.create!` (which mints `out_refund_no`, the PSP idempotency key) and `Gateway.refund` (external HTTP, up to ~35 s) both run inside `payment.with_lock` — i.e. inside one DB transaction.
- **Failure scenario:** the PSP processes the refund but the HTTP response is lost (ambiguous timeout → `TransportError`). The exception **rolls back the refund row, destroying the only copy of the idempotency key**. The admin retries: a *new* `out_refund_no` is minted, which the PSP treats as a brand-new refund. The over-refund ceiling (`validate_refundable!`) cannot see the vanished first refund, so for partial refunds this is a concrete double-refund path (pay 100 → refund 50 times out but processes → retry refund 50 passes the 50+50 ≤ 100 check → 100 refunded for a 50 intent). Secondary problem: a DB transaction/row lock is held across an external call — on SQLite this blocks every writer in the app for the duration.
- **Fix direction (industry standard):** persist the refund intent + idempotency key in its own committed transaction *before* calling the PSP; update status after. Reuse the persisted `out_refund_no` on retry so the PSP dedups.

### H2. Webhooks are processed fully inline, with destroy-on-error and no dead-lettering `[ ]`

- **Where:** `app/controllers/payments/webhooks_controller.rb:7`; `app/services/payments/webhook_dispatcher.rb:36-39`.
- **What:** verification, tenant resolution, business processing, and even *secondary outbound PSP calls* (PayPal verify endpoint `paypal.rb:208`, Stripe `fetch_payment_method` `handle_webhook.rb:299`, WeChat `/v3/certificates` fetch `wechat_pay.rb:182`) all run in the inbound request thread. On any `StandardError` the dedup row is destroyed and the error re-raised, so the PSP retries — forever, for a poison event: no retry ceiling, no dead-letter queue, no backoff control on our side.
- **Impact:** a slow PSP dependency stalls webhook threads; a permanently-failing event generates an unbounded retry/error stream with no operator surface.
- **Fix direction (Stripe/Adyen guidance):** verify signature + persist the event inline, ack 2xx immediately, process asynchronously (solid_queue) with bounded retries and a failed/DLQ state on `payment_webhook_events.status`.

---

## Medium

### M1. Terminal-state guards are asymmetric — a succeeded payment/refund can be regressed to failed `[ ]`

- **Where:** `app/models/payments/payment.rb:57` (`mark_failed!`), `app/models/payments/refund.rb:33` (`mark_failed!`).
- **What:** `Order#mark_failed!` refuses to overwrite settled statuses (`order.rb:39-42`), but `Payment#mark_failed!` and `Refund#mark_failed!` only guard `return if status == "failed"` — an already-`succeeded` record can be flipped to `failed`, desyncing it from its (correctly guarded) order: order stays `paid`/`refunded` while its payment/refund says `failed`. Not reachable via the guarded webhook happy paths today, but latent — exactly what a declared state machine would prevent.
- **Fix direction:** add the same terminal guard (`return if status.in?(%w[succeeded failed])`), or adopt a declared FSM for all `mark_*!` transitions.

### M2. A hard crash mid-webhook permanently wedges that event id `[ ]`

- **Where:** `app/services/payments/webhook_dispatcher.rb:15-22, 36-41`; `app/models/payments/webhook_event.rb`.
- **What:** the dedup row is created as `"received"` *before* processing and destroyed only when a rescued `StandardError` fires. A non-rescuable death (SIGKILL, OOM, deploy restart) leaves the `"received"` row in place; the dedup check ignores `status`, so **every PSP retry of that event gets `:duplicate` forever** and the event is never processed.
- **Fix direction:** treat only `"processed"` rows as duplicates (re-process `"received"` rows), or add a reaper that deletes stale `"received"` rows older than N minutes.

### M3. `reactivate_paused_subscription` does no tenant-ownership check `[ ]`

- **Where:** `app/services/payments/activities/handle_webhook.rb:427-437`.
- **What:** parses a subscription id from the order's `external_ref` (`/\Asub-(\d+)-/`) and looks it up `unscoped_by_tenant.find_by(id:)` without verifying `sub.customer_id == payment.customer_id` before reactivating and advancing it.
- **Exploitability today:** low — public checkout mints `ORD-<sha>` refs (`checkouts_controller.rb:272-274`) and only the cron mints `sub-…` refs. But any future surface that lets a caller choose `external_ref` (the Reform `Contracts::Charge` already exposes the property) turns this into cross-tenant subscription manipulation.
- **Fix direction:** one-line guard: `return unless sub.customer_id == payment.customer_id`.

### M4. Alipay never receives its required `success` acknowledgement `[ ]`

- **Where:** `app/controllers/payments/webhooks_controller.rb` (`head :ok`).
- **What:** Alipay's async-notify protocol requires the literal response body `success` to stop redelivery; an empty-body 200 is treated as failure, so Alipay re-delivers every notification on its ~24 h retry schedule. The dedup ledger absorbs the replays (no correctness loss), but it produces constant retry churn and log noise for every Alipay payment.
- **Fix direction:** respond `render plain: "success"` for the Alipay provider.

### M5. PayPal server-side capture in `query()` sends no idempotency key `[ ]`

- **Where:** `app/services/payments/gateways/paypal.rb:148`.
- **What:** `POST /v2/checkout/orders/:id/capture` is issued without a `PayPal-Request-Id`, though `charge`/`refund` correctly send one. `query` is reachable from the public, unauthenticated checkout status poll (`checkouts_controller.rb:172`), so two concurrent polls of an APPROVED order can race two capture calls.
- **Fix direction:** pass `PayPal-Request-Id: <out_trade_no>-capture` on the capture call.

### M6. Reconciliation reverse leg keys on local processing time, not settlement date `[ ]`

- **Where:** `app/services/payments/activities/reconcile.rb:29-33`.
- **What:** the "local successes absent from the PSP bill" leg filters on `paid_at ∈ bill_date`, but `paid_at` is stamped `Time.zone.now` at webhook-processing time, not the PSP settlement timestamp. A payment settled on the bill date whose webhook we process after midnight is falsely counted as a discrepancy.
- **Fix direction:** record the PSP-reported success time (all four gateways include it in the notification) and reconcile on that.

### M7. Admin transactions table hardcodes `¥` for every currency `[ ]`

- **Where:** `app/components/payments/admin/transaction_table_component.html.erb:24`.
- **What:** `¥<%= format('%.2f', p.amount_cents / 100.0) %>` renders USD/EUR/JPY rows with a yuan symbol. The line predates this refactor, but WS3+ multi-currency Stripe/PayPal support is what makes non-CNY rows common. The correct pattern already exists next door: `DisputeTableComponent#formatted_amount` uses `Billing::CurrencyResolver.format` (`dispute_table_component.rb:29-32`).
- **Fix direction:** apply the dispute table's formatter to the transaction row.

### M8. Dispute upsert ignores event ordering — resolved disputes can regress to open `[ ]`

- **Where:** `app/services/payments/activities/handle_webhook.rb:227-241` (`upsert_dispute`).
- **What:** `dispute.status = status` is applied unconditionally. Stripe/PayPal do not guarantee delivery order across *distinct* events (the dedup ledger only blocks exact re-deliveries), so a delayed `dispute.updated` arriving after `dispute.closed` regresses `won`/`lost` back to `open`/`under_review` while `resolved_at` stays stamped — an inconsistent record.
- **Fix direction:** never downgrade out of `RESOLVED_STATUSES` (or compare PSP event timestamps before overwriting).

---

## Low

### L1. `Disputes#index` is unbounded `[ ]`
`app/controllers/admin/modules/payments/disputes_controller.rb:19-24` has no pagination/limit, unlike the sibling `TransactionsController#index` (`.limit(100)`). Add Pagy or a limit.

### L2. Unknown WeChat cert serial triggers an outbound fetch per request `[ ]`
`app/services/payments/gateways/wechat_pay.rb:151` — `platform_certs(refresh: true)` bypasses the 12 h cache whenever the `Wechatpay-Serial` header is unknown, so an unauthenticated attacker posting bogus webhooks with random serials forces an outbound `/v3/certificates` call each time (amplification / WeChat rate-limit risk). Add a short negative-cache/cooldown on refresh attempts.

### L3. `WebhookEvent.customer_id` is never populated; no payload retention policy `[ ]`
`webhook_dispatcher.rb:51-54` never sets `customer_id` (the model comment says "backfilled" but nothing backfills it) — dead, indexed column; the ledger cannot be tenant-filtered. Event payloads (full decrypted PSP bodies) also accumulate forever with no pruning job.

### L4. `setup_intent` error path leaks raw exception text to the member `[ ]`
`app/controllers/member/payments/payment_methods_controller.rb` — `rescue => e; render json: { error: e.message }` returns internal error strings (and bypasses I18n) on a member-facing endpoint. Return a translated generic message; log the detail.

### L5. Timezone inconsistency in the period order ref `[ ]`
`charge_due_subscriptions.rb:93` uses `Date.today` (system TZ) while due-ness uses `Time.zone.now` — around midnight with differing zones, the same period can mint mismatched refs. Use `Time.zone.today`.

### L6. Concurrent-worker double-charge window in the cron (doc-acknowledged) `[ ]`
`charge_due_subscriptions.rb:40` check-then-act has no row lock (`FOR UPDATE SKIP LOCKED` unavailable on SQLite). Two overlapping cron runs can both pass the exists-check and double-charge. Safe today (single worker + crons unscheduled per C3), but must be addressed before any Postgres/multi-worker deploy.

---

## Architecture assessment (industry-standard lens)

### Strengths (verified in source)

1. **Cross-tenant webhook binding** — `signing_matches_payment?` (`handle_webhook.rb:61-77`) resolves the signing account by globally-unique `(provider, merchant_id)` and asserts it belongs to the payment's customer, uniformly across all four gateways. This is the hardest part of multi-tenant PSP integration and it is done correctly.
2. **Two-layer idempotency** — unique-index event ledger with race-safe `RecordNotUnique` handling (`webhook_dispatcher.rb:47-65`) plus per-payment terminal-state short-circuits; PSP idempotency keys (`Idempotency-Key` / `PayPal-Request-Id`) on charge and refund keyed on `out_trade_no`/`out_refund_no`.
3. **Amount verification on every success handler** (`amount_matches?`) — underpayment cannot mark an order paid; refuses-and-logs to avoid PSP retry storms.
4. **Compliance posture** — no PAN/CVV stored (SAQ-A via hosted elements); `encrypts :credentials`; signature-verify-before-trust ordering; WeChat AEAD `mchid`-to-account binding and platform-cert rotation; replay/freshness windows on all four gateways; PayPal cert-URL origin pinned.
5. **Money handling** — canonical integer `amount_cents`, no floats, zero-decimal awareness sourced from RubyMoney's ISO-4217 table (`money.rb`). (Internally consistent; C1 is a violation of this convention at one boundary, not a flaw in the convention.)
6. **Test fidelity** — webhook specs sign bodies with real fixture RSA keys and assert dedup and amount-mismatch behavior; 100+ payment spec files.
7. **Gateway abstraction held** — PayPal disputes (WS4c) and WeChat cert rotation (WS5) each stayed within their single vendor file; credentials stayed in the encrypted blob.

### Gaps vs. standard practice

- **Operational, not logical:** unscheduled crons (C3), synchronous webhook processing without DLQ (H2), DB transactions held across PSP calls (H1).
- **State machines:** ad-hoc per-method `mark_*!` guards instead of a declared FSM; the asymmetry in M1 is the symptom.
- **No immutable transition ledger:** state lives in mutable status columns + `raw_notify` JSON; no append-only who/when/from→to record, which weakens audit and dispute forensics. Acceptable at this scale, below real-PSP standard.
- **Observability:** interpolated-string `Rails.logger` only; no metrics/counters or alert hooks on payment-failure or webhook-error rates.

### Design doc vs implementation

- Doc claims WS1–WS6 "fully implemented & verified" — mostly accurate; ledger, idempotency keys, refund webhooks, amount verification, Money, disputes, cert rotation, SCA recovery are all present as described.
- **M2 in the doc** ("`signing_matches_payment?` ignores mode") is claimed fixed in-method; actually resolved *structurally* via the `(provider, merchant_id)` unique index — not an open defect, but the doc overstates the change.
- **WS2 item 5** (cron re-entrancy) is honestly downgraded in code to an existence check (see L6).
- **The doc never covers job invocation**, which is how C3 (unscheduled crons) stayed invisible.

## Conventions review (AGENTS.md) — PASS

No violations found. Verified: en/zh-CN key parity in `comp_payments.*.yml` and `feature_modules.*.yml` (including interpolation variables); all new UI strings routed through I18n; `sca_recovery_controller.js` at **100% Vitest lines/branches/functions** (real run: 89/89 lines, 27/27 branches, 8/8 functions, 12 tests passing); gateway single-file rule held for WS4c/WS5; `Payments::Dispute` tenant-scoped + indexed, `WebhookEvent`'s deliberate non-scoping justified in-model; the one new route sits correctly under the `/:cid/admin/` payments namespace with the global `RouteAuthorization` guard; components are pure ViewComponent/Tailwind with responsive column hiding; models stay thin.

---

## Recommended fix order

1. **C1 + C2** — small, deterministic bug fixes with new specs (JPY webhook case; two-tick cron case).
2. **C3** — `config/recurring.yml` entries + thin ActiveJob wrappers (mirror `Billing::DailyBillingJob`).
3. **H1** — restructure `Activities::Refund`: commit the refund row before the PSP call.
4. **M1–M8** — mostly one-to-few-line guards; M4/M5/M7 are trivial.
5. **H2** — the only real architectural change (async webhook processing + DLQ); schedule as its own workstream.
