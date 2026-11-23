# Payments Review Findings — Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 19 findings (C1–C3, H1–H2, M1–M8, L1–L6) from `docs/superpowers/specs/2026-07-13-payments-hardening-refactor-review-findings.md`.

**Architecture:** Four independent workstreams — A (webhook domain: amount conversion, async processing, dispute/tenant guards), B (billing/refund domain: cron idempotency redesign, refund-outside-transaction, job scheduling), C (controller hardening), D (component formatting) — followed by QA, release verification, and parallel review. Key design decisions: PSP-side idempotency via **stable payment rows / out_trade_no reuse** for retry safety (C2/L6), **commit-before-PSP-call** for refunds (H1), and **verify-inline / process-async with a dead-letter status** for webhooks (H2, which also resolves M2).

**Tech Stack:** Rails 8.1 / solid_queue recurring jobs / RSpec. No new gems.

**Conventions that bind every task:** every fix keeps tenant scoping (`for_current_customer` / explicit `customer_id` checks), no new user-facing strings without en + zh-CN I18n keys, thin models, targeted specs run before claiming done.

---

## Workstream A — Backend: webhook domain
*(Owner: anysys-backend-developer #1. Files: `app/services/payments/money.rb`, `app/services/payments/activities/handle_webhook.rb`, `app/services/payments/webhook_dispatcher.rb`, `app/models/payments/webhook_event.rb`, `app/jobs/payments/process_webhook_event_job.rb` (new), `app/services/payments/gateways/wechat_pay.rb`, matching specs.)*

### Task A1: `Money.cents_from_smallest_unit` (fixes C1, part 1)

**Files:** Modify `app/services/payments/money.rb`; Test `spec/services/payments/money_spec.rb`

- [ ] **Step 1: Failing spec** — add to `spec/services/payments/money_spec.rb`:

```ruby
describe ".cents_from_smallest_unit" do
  it "returns the value unchanged for 2-decimal currencies" do
    expect(described_class.cents_from_smallest_unit(1234, "USD")).to eq(1234)
  end

  it "rescales zero-decimal currencies back to canonical major*100" do
    expect(described_class.cents_from_smallest_unit(1000, "JPY")).to eq(100_000)
  end

  it "round-trips with #smallest_unit" do
    money = described_class.new(100_000, "jpy")
    expect(described_class.cents_from_smallest_unit(money.smallest_unit, "jpy")).to eq(100_000)
  end

  it "returns nil for nil" do
    expect(described_class.cents_from_smallest_unit(nil, "JPY")).to be_nil
  end
end
```

Run: `bundle exec rspec spec/services/payments/money_spec.rb` → new examples FAIL (NoMethodError).

- [ ] **Step 2: Implement** — add to `app/services/payments/money.rb` below `cents_from_major`:

```ruby
# Inverse of #smallest_unit: convert a PSP-reported SMALLEST-unit integer
# (Stripe's `amount`/`amount_received` field — cents for 2-decimal, whole
# units for zero-decimal) back to canonical amount_cents (major×100).
def self.cents_from_smallest_unit(value, currency)
  return nil if value.nil?

  cents = value.to_i
  Billing::CurrencyResolver.zero_decimal?(currency.to_s) ? cents * 100 : cents
end
```

- [ ] **Step 3: Run** `bundle exec rspec spec/services/payments/money_spec.rb` → PASS. Commit: `fix(payments): Money.cents_from_smallest_unit — zero-decimal-aware inverse of smallest_unit`

### Task A2: Zero-decimal-aware Stripe webhook amounts (fixes C1, part 2)

**Files:** Modify `app/services/payments/activities/handle_webhook.rb:37-40, 199-213, 400-420`; Test `spec/services/payments/activities/handle_webhook_spec.rb`

- [ ] **Step 1: Failing spec** — add a JPY case (mirror the existing stripe `payment_intent.succeeded` spec setup, but order/payment currency `"JPY"`, `amount_cents: 100_000`, webhook `"amount_received" => 1000`): assert the payment IS marked `succeeded`. Add the inverse mismatch case (`"amount_received" => 999`) asserting it is NOT marked succeeded. Add a JPY dispute case asserting `Payments::Dispute.last.amount_cents == 100_000` for a webhook `"amount" => 1000`.
- [ ] **Step 2: Implement** — in `handle_webhook.rb` replace `stripe_amount_cents`:

```ruby
def self.stripe_amount_cents(object, currency)
  amt = object["amount_received"] || object["amount"]
  amt.nil? ? nil : Payments::Money.cents_from_smallest_unit(amt, currency)
end
```

In `handle_stripe_payment_intent_succeeded`, compute once and reuse:

```ruby
notified = stripe_amount_cents(object, payment.payment_order.currency)
return reject_amount_mismatch(payment, notified) unless amount_matches?(payment, notified)
```

In `record_stripe_dispute`, replace `amount_cents: object["amount"].to_i` with:

```ruby
amount_cents: Payments::Money.cents_from_smallest_unit(object["amount"], payment.payment_order.currency).to_i,
```

- [ ] **Step 3: Run** `bundle exec rspec spec/services/payments/activities/handle_webhook_spec.rb` → PASS. Commit: `fix(payments): rescale zero-decimal Stripe webhook amounts to canonical cents (C1)`

### Task A3: Tenant guard on subscription reactivation (fixes M3)

**Files:** Modify `app/services/payments/activities/handle_webhook.rb:427-437`; Test `spec/services/payments/activities/handle_webhook_spec.rb`

- [ ] **Step 1: Failing spec** — a paused subscription belonging to customer B, a succeeding stripe payment for customer A whose order `external_ref` is `"sub-#{b_sub.id}-x"`: assert B's subscription stays `"paused"` and `next_charge_at` unchanged. Companion positive spec: same-tenant sub IS reactivated (should already exist — extend if present).
- [ ] **Step 2: Implement** — in `reactivate_paused_subscription`:

```ruby
sub = Payments::Subscription.unscoped_by_tenant.find_by(id: match[1])
return unless sub && sub.customer_id == payment.customer_id
return unless sub.status == "paused"
```

- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): bind SCA-recovery reactivation to the payment's tenant (M3)`

### Task A4: PSP-reported settlement time on `mark_succeeded!` (fixes M6)

**Files:** Modify `app/services/payments/activities/handle_webhook.rb` (all four success handlers); Test `spec/services/payments/activities/handle_webhook_spec.rb`

- [ ] **Step 1: Failing spec** — WeChat success payload with `"success_time" => "2026-07-12T23:50:00+08:00"`: assert `payment.reload.paid_at.to_date == Date.new(2026, 7, 12)` (not processing day). One equivalent Alipay case using `"gmt_payment"`.
- [ ] **Step 2: Implement** — add helper:

```ruby
# PSP-reported completion time (fallback: now). paid_at drives the
# reconciliation reverse leg, so it must reflect PSP settlement time, not
# local webhook-processing time.
def self.psp_time(value)
  return Time.zone.now if value.blank?

  Time.zone.parse(value.to_s) || Time.zone.now
rescue ArgumentError
  Time.zone.now
end
```

Call sites:
- WeChat: `payment.mark_succeeded!(psp_id: psp_id, at: psp_time(payload.dig("resource", "success_time") || payload["success_time"]), notify: payload)`
- Alipay: `at: psp_time(payload["gmt_payment"] || payload["notify_time"])`
- Stripe PI succeeded: `at: object["created"].present? ? Time.zone.at(object["created"].to_i) : Time.zone.now`
- PayPal capture: `at: psp_time(resource["create_time"])`

- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): stamp paid_at from PSP-reported settlement time (M6)`

### Task A5: Dispute status never downgrades out of resolved (fixes M8)

**Files:** Modify `app/services/payments/activities/handle_webhook.rb:227-241`; Test `spec/services/payments/activities/handle_webhook_spec.rb`

- [ ] **Step 1: Failing spec** — dispute already `"won"`; deliver a (distinct-event-id) `charge.dispute.updated` with status `"under_review"`: assert status stays `"won"`. Positive: `"open"` → `"under_review"` still advances; `"won"` → `"lost"` (resolved→resolved) still applies.
- [ ] **Step 2: Implement** — in `upsert_dispute`, replace the status/resolved_at block:

```ruby
# Out-of-order guard: PSP events are deduped per event id but NOT ordered —
# a delayed non-terminal event must not reopen a resolved dispute.
resolved_already  = dispute.persisted? && Payments::Dispute::RESOLVED_STATUSES.include?(dispute.status)
incoming_resolved = Payments::Dispute::RESOLVED_STATUSES.include?(status)
dispute.status = status unless resolved_already && !incoming_resolved
if Payments::Dispute::RESOLVED_STATUSES.include?(dispute.status) && dispute.resolved_at.nil?
  dispute.resolved_at = Time.zone.now
end
dispute.save!
```

- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): never downgrade a resolved dispute on out-of-order events (M8)`

### Task A6: Async webhook processing with dead-letter status (fixes H2, M2, L3-backfill)

**Files:** Create `app/jobs/payments/process_webhook_event_job.rb`; Modify `app/services/payments/webhook_dispatcher.rb`, `app/models/payments/webhook_event.rb`; Test `spec/services/payments/webhook_dispatcher_spec.rb`, `spec/models/payments/webhook_event_spec.rb`, new `spec/jobs/payments/process_webhook_event_job_spec.rb`

Design: signature verification + event recording stay inline (they need raw headers/body and must gate the ack). Business processing moves to a queued job. The queue owns retries (fixing M2's stuck-`received` wedge — solid_queue persists jobs across crashes); after 5 attempts the event dead-letters as `status: "failed"`, and a redelivery of a failed event id re-drives it instead of being dropped as duplicate.

- [ ] **Step 1: Failing specs**
  - Dispatcher spec (adapt existing, honouring the stale-test policy): a valid signed notification **enqueues** `Payments::ProcessWebhookEventJob` and returns `:accepted`; with `perform_enqueued_jobs` the payment ends `succeeded` and the event `processed` with `customer_id` populated; a duplicate delivery of a `processed`/`received` event returns `:duplicate` and enqueues nothing; a redelivery of a `failed` event resets it to `received`, enqueues, and returns the event (re-drive).
  - Job spec: processing error → job retries; after final attempt the event ends `status: "failed"` (use `perform_enqueued_jobs` + a `HandleWebhook` stub that always raises); already-`processed` event → no-op.
- [ ] **Step 2: Implement**

`app/jobs/payments/process_webhook_event_job.rb`:

```ruby
# frozen_string_literal: true

module Payments
  # Asynchronous webhook processing (the dispatcher verifies + records inline,
  # then hands off here). The queue owns retries; after ATTEMPTS failures the
  # event dead-letters as status "failed" — visible for operator re-drive via
  # PSP redelivery (the dispatcher re-accepts failed event ids).
  class ProcessWebhookEventJob < ApplicationJob
    queue_as :default

    ATTEMPTS = 5

    retry_on StandardError, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
      event = Payments::WebhookEvent.find_by(id: job.arguments.first)
      event&.update!(status: "failed")
      Rails.logger.error(
        "[payments.webhook_job] event=#{job.arguments.first} dead-lettered: #{error.class}: #{error.message}"
      )
    end

    def perform(event_id, signing_merchant_id)
      event = Payments::WebhookEvent.find_by(id: event_id)
      return if event.nil? || event.status == "processed"

      Payments::Activities::HandleWebhook.call(
        provider:            event.provider,
        verified_payload:    event.payload,
        signing_merchant_id: signing_merchant_id
      )
      event.mark_processed!(customer_id: Current.customer&.id)
    ensure
      Current.reset
    end
  end
end
```

`webhook_dispatcher.rb` — replace the processing block of `call` and `record_event`:

```ruby
def self.call(provider:, headers:, body:)
  normalized_headers = normalize_headers(headers)
  gateway_class      = Payments::Gateways.for(provider)
  merchant_id        = gateway_class.extract_merchant_id(normalized_headers, body)
  gateway            = Payments::Gateway.gateway_for_merchant(provider: provider, merchant_id: merchant_id)
  payload            = gateway.verify_notification(headers: normalized_headers, body: body)

  event = record_event(provider, gateway_class, payload)
  return :duplicate if event == :duplicate

  if event
    # Verified + persisted: ack the PSP now, process async. The queue owns
    # retries; a crash cannot strand the event (solid_queue persists the job)
    # and a poison event dead-letters after bounded attempts instead of
    # driving the PSP into an endless retry loop.
    Payments::ProcessWebhookEventJob.perform_later(event.id, merchant_id)
    :accepted
  else
    # Gateway exposes no event id — nothing to hang a job on; process inline
    # (per-payment terminal-state checks still guard replays).
    Payments::Activities::HandleWebhook.call(
      provider: provider, verified_payload: payload, signing_merchant_id: merchant_id
    )
    :ok
  end
end

def self.record_event(provider, gateway_class, payload)
  event_id = gateway_class.event_id(payload)
  return nil if event_id.blank?

  event = Payments::WebhookEvent.new(
    provider: provider, psp_event_id: event_id,
    event_type: gateway_class.event_type(payload), status: "received", payload: payload
  )
  return event if event.save
  return redrive_or_duplicate(provider, event_id, payload) if event.errors.of_kind?(:psp_event_id, :taken)

  raise ActiveRecord::RecordInvalid.new(event)
rescue ActiveRecord::RecordNotUnique
  redrive_or_duplicate(provider, event_id, payload)
end

# Redelivery of a known event id: drop as :duplicate unless the prior
# processing dead-lettered ("failed"), in which case the redelivery (PSP
# retry or operator resend) re-drives it through the queue.
def self.redrive_or_duplicate(provider, event_id, payload)
  existing = Payments::WebhookEvent.find_by(provider: provider, psp_event_id: event_id)
  return :duplicate unless existing&.status == "failed"

  existing.update!(status: "received", payload: payload)
  existing
end
```

(The `begin/rescue → event.destroy` block and `event&.mark_processed!` in `call` are removed entirely.)

`webhook_event.rb` — replace `mark_processed!`:

```ruby
def mark_processed!(customer_id: nil)
  update!(status: "processed", processed_at: Time.current,
          customer_id: customer_id || self.customer_id)
end
```

Also update the model's header comment (no longer "kept only if processing succeeds").

- [ ] **Step 3: Run** `bundle exec rspec spec/services/payments/webhook_dispatcher_spec.rb spec/models/payments/webhook_event_spec.rb spec/jobs/payments/process_webhook_event_job_spec.rb spec/services/payments/activities/handle_webhook_spec.rb` → PASS. Commit: `feat(payments): async webhook processing with bounded retries + dead-letter (H2, M2, L3)`

### Task A7: Cooldown on WeChat platform-cert refresh (fixes L2)

**Files:** Modify `app/services/payments/gateways/wechat_pay.rb:149-174`; Test `spec/services/payments/gateways/wechat_pay_spec.rb`

- [ ] **Step 1: Failing spec** — two consecutive `verify_notification` calls with an unknown serial (stub `download_platform_certs`): assert the download is attempted only once within the cooldown (second call raises `SignatureInvalid` without re-downloading). Use `ActiveSupport::Cache::MemoryStore` via `allow(Rails).to receive(:cache).and_return(...)`.
- [ ] **Step 2: Implement** — in `resolve_platform_key`, replace `platform_certs(refresh: true)[serial]` with `refreshed_platform_certs[serial]` and add:

```ruby
REFRESH_COOLDOWN = 5.minutes

# Unknown serials force a re-download, but at most once per cooldown window
# per merchant — an unauthenticated caller spraying bogus serials must not
# be able to make us hammer WeChat's /v3/certificates endpoint.
def refreshed_platform_certs
  cooldown_key = "#{platform_certs_cache_key}/refresh_cooldown"
  return {} if Rails.cache.exist?(cooldown_key)

  Rails.cache.write(cooldown_key, true, expires_in: REFRESH_COOLDOWN)
  platform_certs(refresh: true)
end
```

- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): rate-limit WeChat platform-cert re-downloads (L2)`

---

## Workstream B — Backend: billing & refund domain
*(Owner: anysys-backend-developer #2. Files: `app/models/payments/payment.rb`, `app/models/payments/refund.rb`, `app/services/payments/activities/refund.rb`, `app/services/payments/activities/charge_token.rb`, `app/services/payments/cron/charge_due_subscriptions.rb`, `app/services/payments/gateways/paypal.rb`, new migration, new job files, `config/recurring.yml`, new `app/services/payments/cron/prune_webhook_events.rb`, matching specs.)*

### Task B1: Terminal-state guards on Payment/Refund `mark_failed!`/`mark_closed!` (fixes M1)

**Files:** Modify `app/models/payments/payment.rb:57-68`, `app/models/payments/refund.rb:33-36`; Test `spec/models/payments/…`

- [ ] **Step 1: Failing specs** — `payment` with `status: "succeeded"`: `mark_failed!(reason: "x")` leaves it `succeeded`; `mark_closed!` leaves it `succeeded`. `refund` with `status: "succeeded"`: `mark_failed!(notify: {})` leaves it `succeeded`.
- [ ] **Step 2: Implement**

`payment.rb`:

```ruby
TERMINAL_STATUSES = %w[succeeded failed closed].freeze

def mark_failed!(reason:, notify: {})
  with_lock do
    return if status.in?(TERMINAL_STATUSES)
    update!(status: "failed", failure_reason: reason, raw_notify: notify)
    payment_order.with_lock { payment_order.mark_failed! }
  end
end

def mark_closed!
  return if status.in?(TERMINAL_STATUSES)
  update!(status: "closed", closed_at: Time.zone.now)
end
```

`refund.rb`:

```ruby
def mark_failed!(notify:)
  with_lock do
    return if status.in?(%w[succeeded failed])
    update!(status: "failed", failed_at: Time.zone.now, raw_notify: notify)
  end
end
```

- [ ] **Step 3: Run model specs → PASS.** Commit: `fix(payments): terminal-state guards on Payment/Refund mark_failed!/mark_closed! (M1)`

### Task B2: Commit refund row before the PSP call (fixes H1)

**Files:** Modify `app/services/payments/activities/refund.rb`; Test `spec/services/payments/activities/refund_spec.rb`

- [ ] **Step 1: Failing specs** — (a) gateway raises `Payments::Errors::TransportError`: the `Payments::Refund` row **persists** with status `"requested"`; a retried call reuses the SAME row (same `out_refund_no`, `Refund.count` unchanged). (b) gateway raises `ApiError`: the row persists with status `"failed"`. (c) existing behavior (succeeded/processing/over-refund ceiling/concurrency) still passes.
- [ ] **Step 2: Implement** — replace `Payments::Activities::Refund.call`:

```ruby
def self.call(customer:, payment:, amount_cents:, reason: nil)
  # Serialize concurrent requests on the payment row, but ONLY around local
  # bookkeeping — the refund row (and its out_refund_no idempotency key)
  # must be COMMITTED before the PSP call, so an ambiguous transport failure
  # cannot roll it back and a retry re-uses the same PSP-side idempotency
  # key instead of minting a new one (double-refund).
  refund = payment.with_lock do
    validate_refundable!(payment, amount_cents)

    Payments::Refund.where(payment_id: payment.id, amount_cents: amount_cents,
                           reason: reason, status: %w[requested processing]).first ||
      Payments::Refund.create!(
        payment: payment,
        out_refund_no: Payments::OutTradeNo.generate(prefix: "rf", customer_id: customer.id),
        amount_cents: amount_cents, reason: reason
      )
  end

  begin
    res = Payments::Gateway.refund(customer: customer, payment: payment, refund: refund)
  rescue Payments::Errors::ApiError => e
    # Definitive PSP error response — the refund was not processed. Release
    # the reserved amount so a corrected retry is not blocked by the ceiling.
    refund.mark_failed!(notify: { "error" => "#{e.class}: #{e.message}" })
    raise
  end
  # A TransportError (ambiguous — the PSP may have processed it) intentionally
  # propagates with the row left "requested": the retry path above re-uses it.

  case res[:status]
  when :succeeded
    refund.mark_succeeded!(at: Time.zone.now, psp_refund_id: res[:psp_refund_id],
                           notify: res[:raw] || {})
  when :processing
    refund.mark_processing!
  when :failed
    refund.mark_failed!(notify: res[:raw] || {})
  end
  refund
end
```

(`validate_refundable!` is unchanged.)

- [ ] **Step 3: Run** `bundle exec rspec spec/services/payments/activities/refund_spec.rb` → PASS. Commit: `fix(payments): persist refund + idempotency key before the PSP call (H1)`

### Task B3: Recurring-charge idempotency — reuse stalled payments, never advance uncollected (fixes C2, L5)

**Files:** Modify `app/services/payments/cron/charge_due_subscriptions.rb`, `app/services/payments/activities/charge_token.rb`; Test `spec/services/payments/cron/charge_due_subscriptions_spec.rb`, `spec/services/payments/activities/charge_token_spec.rb`

Design: an `ApiError` (definitive PSP error response) marks the payment failed so the next tick retries with a fresh row. A `TransportError` (ambiguous) leaves the row `"created"`; the next tick **reuses that row** — for card charges the PSP-side `Idempotency-Key` (keyed on `out_trade_no`) makes the retry safe; for agreement charges we `Query` the PSP first so an actually-completed charge is recorded instead of re-submitted. `advance_next_charge!` is only reached when the period genuinely resolved.

- [ ] **Step 1: Failing specs (the two-tick scenarios the review found untested)**
  - Card sub, tick 1: gateway raises `ApiError` → payment `failed`, `next_charge_at` NOT advanced. Tick 2 (same day): gateway succeeds → a NEW payment succeeds, `next_charge_at` advanced exactly once.
  - Card sub, tick 1: gateway raises `TransportError` → payment stays `"created"`. Tick 2: `ChargeToken` is invoked with the SAME payment row (`Payment.count` does not grow), succeeds → advanced.
  - Agreement sub, tick 1: `TransportError`. Tick 2: stub `Gateway.query` to return `{ status: :succeeded, psp_transaction_id: "t", raw: {} }` → payment marked succeeded WITHOUT calling `charge_subscription` again, advanced.
  - A sub whose order has a `pending` (SCA) payment: tick neither charges nor advances.
  - `ensure_order_for` uses `Time.zone.today` (travel to a time where `Date.today != Time.zone.today` and assert the ref date).
- [ ] **Step 2: Implement**

`charge_token.rb` — accept an optional existing payment row:

```ruby
def self.call(customer:, order:, payment_method:, payment: nil)
  if payment_method.customer_id != customer.id
    raise Payments::Errors::TenantMismatch,
          "PaymentMethod #{payment_method.id} does not belong to customer #{customer.id}"
  end

  # Reusing a stalled row keeps out_trade_no stable, so the PSP-side
  # Idempotency-Key dedups a retry after an ambiguous transport failure.
  payment ||= Payments::Payment.create!(
    payment_order: order,
    provider:      payment_method.provider,
    flow:          "card",
    out_trade_no:  Payments::OutTradeNo.generate(prefix: "ct", customer_id: customer.id),
    amount_cents:  order.amount_cents
  )

  begin
    result = Payments::Gateway.charge_token(
      customer:       customer,
      order:          order,
      payment:        payment,
      payment_method: payment_method
    )
  rescue Payments::Errors::ApiError => e
    # Definitive PSP error response: record the failure so the caller's next
    # tick retries with a fresh attempt instead of treating this period as
    # in-flight forever (free-period bug C2).
    payment.mark_failed!(reason: "#{e.class}: #{e.message}")
    raise
  end

  # …case result[:status] block unchanged…
```

`charge_due_subscriptions.rb` — replace `charge_one`, `charge_card_subscription`, `charge_agreement_subscription`, and the `Date.today` in `ensure_order_for`:

```ruby
def self.charge_one(sub)
  order = ensure_order_for(sub)

  # pending = awaiting SCA / webhook resolution: the period is not yet
  # collected — neither re-charge (double-charge risk) nor advance
  # (free-period risk).
  return if order.payments.where(status: "pending").exists?

  unless order.payments.where(status: "succeeded").exists?
    if sub.card_recurring?
      charge_card_subscription(sub, order)
    else
      charge_agreement_subscription(sub, order)
    end
  end

  sub.advance_next_charge!
end

def self.charge_card_subscription(sub, order)
  pm = sub.payment_method
  unless pm&.chargeable?
    raise Payments::Errors::CardDeclined,
          "subscription #{sub.id} payment method is not chargeable"
  end

  # Reuse a stalled prior attempt (ambiguous transport failure / crash) so
  # the PSP-side idempotency key stays stable across the retry.
  stalled = order.payments.where(status: "created").order(:created_at).last
  Payments::Activities::ChargeToken.call(
    customer:       sub.customer,
    order:          order,
    payment_method: pm,
    payment:        stalled
  )
end

def self.charge_agreement_subscription(sub, order)
  if (stalled = order.payments.where(status: "created").order(:created_at).last)
    return if resolve_stalled_agreement_payment(sub, stalled) # succeeded at PSP
  end

  payment = Payments::Payment.create!(
    payment_order: order,
    provider:      sub.provider,
    flow:          "jsapi",
    out_trade_no:  Payments::OutTradeNo.generate(prefix: "sb", customer_id: sub.customer_id),
    amount_cents:  sub.amount_cents
  )
  begin
    result = Payments::Gateway.charge_subscription(
      customer: sub.customer, subscription: sub, payment: payment
    )
  rescue Payments::Errors::ApiError => e
    payment.mark_failed!(reason: "#{e.class}: #{e.message}")
    raise
  end
  payment.mark_succeeded!(
    psp_id: result[:psp_transaction_id], at: Time.zone.now, notify: result[:raw] || {}
  )
end

# A prior agreement attempt died mid-flight. Agreement APIs are NOT
# idempotent on re-submission the way card Idempotency-Keys are, so ask the
# PSP what actually happened first. Returns true when the stalled attempt
# turned out to have succeeded (Query already recorded it).
def self.resolve_stalled_agreement_payment(sub, payment)
  Payments::Activities::Query.call(customer: sub.customer, payment: payment)
  payment.reload.status == "succeeded"
rescue Payments::Errors::ApiError
  # PSP has no such trade — the original submission never landed; safe to
  # retire this attempt and charge fresh.
  payment.mark_failed!(reason: "stalled attempt unknown to PSP")
  false
end
```

In `ensure_order_for`: `ref = "sub-#{sub.id}-#{Time.zone.today}"`.

- [ ] **Step 3: Run** `bundle exec rspec spec/services/payments/cron/charge_due_subscriptions_spec.rb spec/services/payments/activities/charge_token_spec.rb` → PASS. Commit: `fix(payments): recurring-charge retry safety — no free periods, no double charges (C2, L5)`

### Task B4: Atomic per-subscription claim for concurrent cron workers (fixes L6)

**Files:** Create `db/migrate/<ts>_add_charge_claimed_at_to_payment_subscriptions.rb`; Modify `app/services/payments/cron/charge_due_subscriptions.rb` (`perform`); Test `spec/services/payments/cron/charge_due_subscriptions_spec.rb`

- [ ] **Step 1: Migration**

```ruby
# frozen_string_literal: true

# DB-agnostic re-entrancy claim for the recurring-charge cron (SQLite has no
# SELECT … FOR UPDATE SKIP LOCKED): a worker atomically claims a due
# subscription before charging; a second overlapping worker's claim UPDATE
# matches zero rows and skips it.
class AddChargeClaimedAtToPaymentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_subscriptions, :charge_claimed_at, :datetime
  end
end
```

Run: `bin/rails db:migrate` (then `bin/rails db:test:prepare`).

- [ ] **Step 2: Failing spec** — a due sub with `charge_claimed_at: 1.minute.ago` is skipped (no charge attempted); one claimed longer than `CLAIM_TTL` ago IS processed (stale claim from a dead worker); after a successful run `charge_claimed_at` is nil again.
- [ ] **Step 3: Implement** — replace `perform`:

```ruby
CLAIM_TTL = 15.minutes

def self.perform
  Payments::Subscription.unscoped_by_tenant.due_now.find_each do |sub|
    next unless claim!(sub)

    begin
      Current.customer = sub.customer
      charge_one(sub)
    rescue Payments::Errors::PaymentRequiresAction, Payments::Errors::CardDeclined => e
      sub.mark_paused!
      Rails.logger.warn("[payments.cron] dunning sub=#{sub.id}: #{e.class}: #{e.message}")
    rescue Payments::Errors::Error => e
      Rails.logger.error("[payments.cron] #{e.class}: #{e.message}")
    ensure
      sub.update_columns(charge_claimed_at: nil)
    end
  end
ensure
  Current.reset
end

# Atomic claim: the UPDATE's WHERE re-checks status + next_charge_at, so of
# two overlapping workers exactly one matches (the other sees 0 rows).
# Stale claims (dead worker) expire after CLAIM_TTL.
def self.claim!(sub)
  Payments::Subscription.unscoped_by_tenant
    .where(id: sub.id, status: "active", next_charge_at: sub.next_charge_at)
    .where("charge_claimed_at IS NULL OR charge_claimed_at < ?", CLAIM_TTL.ago)
    .update_all(charge_claimed_at: Time.zone.now) == 1
end
```

- [ ] **Step 4: Run cron spec → PASS.** Commit: `fix(payments): atomic subscription claim for overlapping cron workers (L6)`

### Task B5: Idempotency key on PayPal server-side capture (fixes M5)

**Files:** Modify `app/services/payments/gateways/paypal.rb:148`; Test `spec/services/payments/gateways/paypal_spec.rb`

- [ ] **Step 1: Failing spec** — stub the capture HTTP call for an APPROVED order in `query`; assert the request carries header `PayPal-Request-Id` == `"#{payment.out_trade_no}-capture"`.
- [ ] **Step 2: Implement** — line 148:

```ruby
cap = api_post("/v2/checkout/orders/#{id}/capture", {}, request_id: "#{payment.out_trade_no}-capture")
```

- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): idempotency key on PayPal server-side capture (M5)`

### Task B6: Schedule the payment crons + webhook-ledger retention (fixes C3, L3-retention)

**Files:** Create `app/jobs/payments/charge_due_subscriptions_job.rb`, `app/jobs/payments/daily_maintenance_job.rb`, `app/services/payments/cron/prune_webhook_events.rb`; Modify `config/recurring.yml`; Test `spec/jobs/payments/…`, `spec/services/payments/cron/prune_webhook_events_spec.rb`

- [ ] **Step 1: Failing specs** — `PruneWebhookEvents.perform(now:)` deletes events older than 90 days and keeps newer ones. `DailyMaintenanceJob#perform` calls each cron and continues past one that raises (stub one to raise, assert the others still run — mirror `spec` for `Billing::DailyBillingJob` if one exists). `ChargeDueSubscriptionsJob#perform` delegates to the cron.
- [ ] **Step 2: Implement**

`app/services/payments/cron/prune_webhook_events.rb`:

```ruby
# frozen_string_literal: true

module Payments
  module Cron
    # Retention sweep for the webhook idempotency ledger. PSP redelivery
    # windows are measured in days, so rows older than RETENTION serve no
    # dedup purpose and only accumulate (payloads embed full PSP bodies).
    class PruneWebhookEvents
      RETENTION = 90.days

      def self.perform(now: Time.current)
        Payments::WebhookEvent.where(created_at: ...(now - RETENTION))
                              .in_batches.delete_all
      end
    end
  end
end
```

`app/jobs/payments/charge_due_subscriptions_job.rb`:

```ruby
# frozen_string_literal: true

module Payments
  # Hourly recurring entry point (config/recurring.yml: payments_charge_due_subscriptions).
  class ChargeDueSubscriptionsJob < ApplicationJob
    queue_as :default

    def perform
      Payments::Cron::ChargeDueSubscriptions.perform
    end
  end
end
```

`app/jobs/payments/daily_maintenance_job.rb`:

```ruby
# frozen_string_literal: true

module Payments
  # Orchestrates the daily payment crons in sequence (config/recurring.yml:
  # payments_daily_maintenance). Each cron is isolated in its own rescue so
  # one failure does not starve the rest — mirrors Billing::DailyBillingJob.
  class DailyMaintenanceJob < ApplicationJob
    queue_as :default

    CRONS = [
      Payments::Cron::DownloadBills,
      Payments::Cron::ReapStalePaymentMethods,
      Payments::Cron::PruneWebhookEvents
    ].freeze

    def perform
      CRONS.each do |cron|
        cron.perform
      rescue StandardError => e
        Rails.logger.error("[payments.daily_maintenance_job] #{cron.name} failed: #{e.class}: #{e.message}")
      end
    end
  end
end
```

`config/recurring.yml` — add under `production:`:

```yaml
  payments_charge_due_subscriptions:
    class: "Payments::ChargeDueSubscriptionsJob"
    queue: default
    schedule: every hour at minute 5
  payments_daily_maintenance:
    class: "Payments::DailyMaintenanceJob"
    queue: default
    schedule: every day at 4am
```

(Also add the same two entries commented-out under `development:`, matching the existing `billing_daily` pattern there.)

- [ ] **Step 3: Run the new specs → PASS.** Commit: `feat(payments): schedule payment crons + webhook-ledger retention (C3, L3)`

---

## Workstream C — Controllers (security engineer)
*(Owner: anysys-security-engineer. Files: `app/controllers/payments/webhooks_controller.rb`, `app/controllers/admin/modules/payments/disputes_controller.rb`, `app/controllers/member/payments/payment_methods_controller.rb`, `config/locales/comp_payments.{en,zh-CN}.yml`, request specs.)*

### Task C-1: Alipay webhook acknowledgement body (fixes M4)

**Files:** Modify `app/controllers/payments/webhooks_controller.rb`; Test `spec/requests/…` (locate the existing webhook request spec via `grep -rl payments_webhook spec/requests`)

- [ ] **Step 1: Failing spec** — POST a valid (stubbed-dispatcher) alipay notification: `response.body == "success"`; a stripe one still has an empty body + 200.
- [ ] **Step 2: Implement** — in `create`, replace `head :ok` with:

```ruby
# Alipay's notify protocol acks with the literal body "success"; anything
# else (including an empty 200) is treated as failure and redelivered for
# ~24h. Other PSPs key off the 2xx status alone.
params[:provider] == "alipay" ? render(plain: "success") : head(:ok)
```

(The string is a PSP protocol constant, not user-facing copy — no I18n key.)

- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): return Alipay's required "success" ack body (M4)`

### Task C-2: Bound the admin disputes listing (fixes L1)

**Files:** Modify `app/controllers/admin/modules/payments/disputes_controller.rb:19-24`; Test `spec/requests/payments/admin/disputes_spec.rb`

- [ ] **Step 1: Failing spec** — create 101 disputes for the tenant; GET index; assert 100 rendered (e.g. count of a per-row marker), matching `TransactionsController`'s cap.
- [ ] **Step 2: Implement** — append `.limit(100)` to `scoped_disputes`' chain.
- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): cap admin disputes listing at 100 rows (L1)`

### Task C-3: Generic, localized setup_intent error (fixes L4)

**Files:** Modify `app/controllers/member/payments/payment_methods_controller.rb` (`setup_intent` rescue); Modify `config/locales/comp_payments.en.yml` + `comp_payments.zh-CN.yml`; Test `spec/requests/…` member payment methods spec

- [ ] **Step 1: Failing spec** — stub `VaultCard` to raise `Payments::Errors::ApiError, "secret internal detail"`; POST setup_intent; assert 422, body does NOT contain "secret internal detail", and equals the translated generic message.
- [ ] **Step 2: Implement** — replace the rescue:

```ruby
rescue StandardError => e
  Rails.logger.warn("[member.payment_methods.setup_intent] #{e.class}: #{e.message}")
  render json: { error: t("member.flash.payment_methods.setup_failed") },
         status: :unprocessable_entity
```

Locale keys (place beside the existing `member.flash.payment_methods.*` keys, keeping en/zh-CN parity):

```yaml
# comp_payments.en.yml        →  setup_failed: "We couldn't start the card setup. Please try again."
# comp_payments.zh-CN.yml     →  setup_failed: "无法开始银行卡绑定，请稍后重试。"
```

(If `member.flash.payment_methods.*` actually lives in a different locale file, add `setup_failed` beside its siblings there instead — key path stays the same.)

- [ ] **Step 3: Run spec → PASS.** Commit: `fix(payments): generic localized setup_intent error, no internal detail leak (L4)`

---

## Workstream D — Component (frontend developer)
*(Owner: anysys-frontend-developer.)*

### Task D1: Currency-aware amount in the admin transactions table (fixes M7)

**Files:** Modify `app/components/payments/admin/transaction_table_component.rb`, `app/components/payments/admin/transaction_table_component.html.erb:24`; Test `spec/components/payments/admin/transaction_table_component_spec.rb`

- [ ] **Step 1: Failing spec** — render with a USD payment (`amount_cents: 1234`, order currency `"USD"`): output contains `$12.34` (match `Billing::CurrencyResolver.format(1234, "USD")` exactly) and does NOT contain `¥12.34`. Keep/extend the existing CNY expectation via the resolver output.
- [ ] **Step 2: Implement** — add to the component class (mirror `DisputeTableComponent#formatted_amount`):

```ruby
# Amount in the payment's own currency (via its order) — never a hard-coded
# symbol; multi-currency gateways (Stripe/PayPal) make non-CNY rows common.
def formatted_amount(payment)
  currency = payment.payment_order&.currency || "CNY"
  Billing::CurrencyResolver.format(payment.amount_cents, currency)
end
```

ERB line 24:

```erb
<td class="px-4 py-3 text-right text-body text-text-primary tabular-nums"><%= formatted_amount(p) %></td>
```

- [ ] **Step 3: Run** `bundle exec rspec spec/components/payments/admin/transaction_table_component_spec.rb` → PASS. Commit: `fix(payments): currency-aware amounts in admin transactions table (M7)`

---

## Phase 2 — QA (anysys-qa-engineer)

- [ ] Review all specs added above; fill gaps with emphasis on multi-tenant isolation and authorization: cross-tenant reactivation (A3), cross-tenant dispute/webhook binding still intact after A6's async move, member-scoping on the touched member endpoints, dead-letter re-drive path, refund retry reuse under two concurrent calls. Honour the stale-test policy: specs asserting the OLD inline-webhook / destroy-on-error behavior must be rewritten to the new async contract, not deleted.
- [ ] Run the payments-scoped suite: `bundle exec rspec spec/services/payments spec/models/payments spec/jobs/payments spec/components/payments spec/requests/payments spec/requests/member/payments`.

## Phase 3 — Release verification (anysys-release-engineer)

- [ ] `bin/rails db:migrate && bin/rails db:test:prepare`
- [ ] Full suite via `bin/rails parallel:spec` (cross-cutting payment change ⇒ full run). Known pre-existing flakes under parallel load: JS drawer spec, `passwords_spec.rb` — rerun those files serially before judging them failures.
- [ ] `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`; smoke-hit an admin transactions page, admin disputes page, and member payment-methods page.

## Phase 4 — Parallel review

- [ ] anysys-tech-lead: AGENTS.md convention compliance on the new diff.
- [ ] anysys-code-reviewer: correctness + security on the new diff.
- [ ] Address any findings; then update the checkboxes in `docs/superpowers/specs/2026-07-13-payments-hardening-refactor-review-findings.md` from `[ ]` to `[x]` for every fixed finding (M2 note: fixed via H2's queue-owned retries + dead-letter).

---

## Self-review notes

- Spec coverage: C1→A1/A2, C2→B3, C3→B6, H1→B2, H2→A6, M1→B1, M2→A6, M3→A3, M4→C-1, M5→B5, M6→A4, M7→D1, M8→A5, L1→C-2, L2→A7, L3→A6 (backfill) + B6 (retention), L4→C-3, L5→B3, L6→B4. All 19 covered.
- File-ownership: no file is touched by two workstreams (`handle_webhook.rb` A only; `charge_due_subscriptions.rb` B only; controllers C only; component D only). Workstreams A–D can build in parallel.
- Interface consistency: `ChargeToken.call(payment: nil)` kwarg is additive; `mark_processed!(customer_id: nil)` kwarg is additive; `stripe_amount_cents(object, currency)` has exactly two call sites, both updated in A2; dispatcher return `:accepted` is additive (controller treats any non-raise as ack).
