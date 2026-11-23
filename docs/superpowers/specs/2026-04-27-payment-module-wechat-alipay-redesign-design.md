# Payment Module Redesign — WeChat Pay + Alipay

**Date:** 2026-04-27
**Branch:** feature-payment-enhancement
**Status:** Approved design; implementation plan to follow.

## Summary

Replace the existing stub `FeatureModules::Payment::Registration` with a complete,
multi-tenant payment module that supports **WeChat Pay** and **Alipay only** (China).
All other payment methods are removed. Existing payment code outside
`app/services/page_layout_templates/templates/` (namely
`app/services/feature_modules/payment/registration.rb`) is deleted and replaced.

The module supports the full lifecycle — **charge, refund, reconciliation,
subscription (recurring)** — and provides three device-aware front-end flows:
**QR-code (desktop)**, **H5 redirect (mobile web)**, and **JSAPI (in-app
WeChat/Alipay browser)**. Credentials are stored **per-tenant** (encrypted), with
sandbox/production modes.

## Non-Goals

- No non-China payment methods (Stripe, PayPal, Apple Pay, cards, etc.).
- No multi-currency support; CNY only.
- No platform-wide fallback merchant account; each tenant supplies their own.
- No state-machine gem; transitions are explicit in activity steps.
- No backward compatibility with the existing stub — it is deleted.

## Architecture

### Directory layout

```
app/
├── models/
│   ├── payment_order.rb
│   ├── payment.rb
│   ├── payment_refund.rb
│   ├── payment_subscription.rb
│   ├── payment_reconciliation_bill.rb
│   └── payment_merchant_account.rb
├── services/
│   ├── feature_modules/payment/
│   │   ├── registration.rb
│   │   └── provisioner.rb
│   └── payments/
│       ├── gateway.rb
│       ├── flow_selector.rb
│       ├── credential_resolver.rb
│       ├── webhook_dispatcher.rb
│       ├── adapters/
│       │   ├── base.rb
│       │   ├── wechat_pay.rb
│       │   └── alipay.rb
│       ├── contracts/
│       │   ├── charge.rb
│       │   ├── refund.rb
│       │   └── subscribe.rb
│       ├── activities/
│       │   ├── charge.rb
│       │   ├── refund.rb
│       │   ├── query.rb
│       │   ├── cancel_subscription.rb
│       │   ├── reconcile.rb
│       │   └── handle_webhook.rb
│       └── cron/
│           ├── charge_due_subscriptions.rb
│           └── download_bills.rb
├── controllers/payments/
│   ├── checkouts_controller.rb
│   ├── results_controller.rb
│   ├── webhooks_controller.rb
│   └── admin/
│       ├── merchant_accounts_controller.rb
│       ├── transactions_controller.rb
│       ├── subscriptions_controller.rb
│       └── reconciliations_controller.rb
└── components/payments/
    ├── checkout_component.rb
    ├── qr_code_component.rb
    ├── h5_redirect_component.rb
    ├── jsapi_invoker_component.rb
    ├── waiting_component.rb
    ├── result_component.rb
    └── admin/
        ├── transaction_table_component.rb
        ├── refund_dialog_component.rb
        ├── subscription_table_component.rb
        ├── reconciliation_table_component.rb
        └── merchant_account_form_component.rb
```

### Unit responsibilities

| Unit | Responsibility | Depends on |
|---|---|---|
| `Payments::Gateway` | Single public entry point. Resolves credentials, picks adapter, delegates. | `CredentialResolver`, `Adapters::*` |
| `Payments::Adapters::*` | Stateless HTTP + signing + response verification per PSP. Returns normalized hashes. | PSP HTTP API |
| `Payments::Activities::*` | Trailblazer orchestration: DB writes, contract validation, gateway calls, idempotency. | `Gateway`, models, contracts |
| `Payments::FlowSelector` | Pure function `(request, provider) -> :qr | :h5 | :jsapi`. | — |
| `Payments::CredentialResolver` | `(customer, provider) -> PaymentMerchantAccount`; raises `CredentialsMissing`. | `PaymentMerchantAccount` |
| `Payments::WebhookDispatcher` | Verify signature via adapter, resolve tenant by merchant-id, route to `HandleWebhook`. | `Adapters::*`, activities |
| Controllers | Thin — invoke an activity, render a component. | Activities, components |
| ViewComponents | Render UI with Tailwind; Stimulus controllers for QR polling / H5 redirect / JSAPI. | — |

## Data Model

All tables are tenant-scoped (`customer_id` + shared `TenantScoped` concern).

### `payment_merchant_account`
Per-tenant encrypted PSP credentials.
- `customer_id:bigint` (required, indexed)
- `provider:string` — `"wechat_pay"` | `"alipay"`
- `mode:string` — `"sandbox"` | `"production"`
- `merchant_id:string` — WeChat mchid / Alipay app_id
- `api_key_v3:text` (encrypted) — WeChat APIv3 key
- `private_key_pem:text` (encrypted) — WeChat cert private key OR Alipay app private key
- `platform_public_key_pem:text` (encrypted) — Alipay platform public key; null for WeChat
- `wechat_cert_serial:string` — WeChat only
- `notify_url_override:string` — optional
- `status:string` — `"active"` | `"disabled"`
- Unique: `[customer_id, provider, mode]`
- Unique: `[provider, merchant_id]` — used by webhook dispatcher

### `payment_order`
What is being paid for.
- `customer_id:bigint` (required, indexed)
- `external_ref:string` — host-flow identifier (unique per customer)
- `amount_cents:integer`
- `currency:string` default `"CNY"`
- `subject:string`, `body:text`
- `status:string` — `"pending" | "paid" | "partial_refund" | "refunded" | "closed" | "failed"`
- `metadata:jsonb`
- `expires_at:datetime`, `paid_at:datetime`
- Unique: `[customer_id, external_ref]`

### `payment`
One charge attempt against an order.
- `payment_order_id:bigint` (required, indexed)
- `customer_id:bigint` (required, indexed, denormalized)
- `provider:string`, `flow:string` — `qr | h5 | jsapi`
- `out_trade_no:string` unique — our ID sent to PSP
- `psp_transaction_id:string`
- `status:string` — `"created" | "pending" | "succeeded" | "failed" | "closed"`
- `amount_cents:integer`
- `prepay_payload:jsonb` — code_url / h5_url / jsapi params
- `raw_notify:jsonb` — last verified webhook payload
- `paid_at:datetime`, `closed_at:datetime`
- Index: `[provider, psp_transaction_id]`

### `payment_refund`
- `payment_id:bigint` (required)
- `customer_id:bigint` (required, indexed)
- `out_refund_no:string` unique
- `psp_refund_id:string`
- `amount_cents:integer`, `reason:string`
- `status:string` — `"requested" | "processing" | "succeeded" | "failed"`
- `requested_at, succeeded_at, failed_at:datetime`
- `raw_notify:jsonb`

### `payment_subscription`
- `customer_id:bigint` (required, indexed)
- `provider:string`, `external_ref:string`
- `plan_name:string`, `amount_cents:integer`
- `cycle:string` — `daily | weekly | monthly | yearly`
- `psp_agreement_id:string`
- `status:string` — `"pending_sign" | "active" | "paused" | "cancelled" | "expired"`
- `next_charge_at:datetime`
- `signed_at, cancelled_at:datetime`
- Unique: `[provider, psp_agreement_id]`

### `payment_reconciliation_bill`
- `customer_id:bigint` (required, indexed)
- `provider:string`, `bill_date:date`
- `bill_type:string` — `all | success | refund`
- Uses ActiveStorage attachment for the downloaded bill file
- `total_count:integer`, `total_amount_cents:integer`
- `discrepancy_count:integer` default 0
- `status:string` — `"downloading" | "parsed" | "reconciled" | "discrepant" | "failed"`
- `raw_summary:jsonb`
- Unique: `[customer_id, provider, bill_date, bill_type]`

## Public Interface — `Payments::Gateway`

All methods take `customer:` and provider-agnostic normalized inputs.

```ruby
Payments::Gateway.charge(customer:, order:, provider:, flow:, openid: nil)
  # -> { payment: Payment, prepay_payload: Hash }

Payments::Gateway.query(customer:, payment:)
  # -> { status: :succeeded|:pending|:failed|:closed, psp_transaction_id:, raw: }

Payments::Gateway.refund(customer:, payment:, amount_cents:, reason:)
  # -> { refund: PaymentRefund, raw: }

Payments::Gateway.close(customer:, payment:)
  # -> { status: :closed }

Payments::Gateway.subscribe(customer:, subscription:)
  # -> { sign_url_or_params: }

Payments::Gateway.cancel_subscription(customer:, subscription:)
  # -> { status: :cancelled }

Payments::Gateway.charge_subscription(customer:, subscription:)
  # -> { payment: Payment, raw: }

Payments::Gateway.download_bill(customer:, provider:, bill_date:, bill_type:)
  # -> { bill: PaymentReconciliationBill, raw_summary: }
```

## Data Flow

### Charge
1. Host module/flow invokes FeatureModules handoff → `GET /:customer_id/payments/checkout?ref=<external_ref>`.
2. `CheckoutsController#show` finds-or-creates the `PaymentOrder` from the input-contract payload; renders `CheckoutComponent` (WeChat | Alipay picker).
3. `POST /:customer_id/payments/checkout` with `{provider}` → `Activities::Charge`:
   - Validates via `Contracts::Charge` (Reform).
   - Creates `Payment` row (status `created`, generates `out_trade_no`).
   - `FlowSelector.(request, provider)` → `:qr | :h5 | :jsapi`.
   - `Gateway.charge(...)` → adapter prepay API → returns payload.
   - Stores `prepay_payload`, transitions to `pending`.
   - Renders flow-appropriate component (QR / H5 / JSAPI) or responds JSON.
4. Front-end:
   - **QR:** `qr-poll` Stimulus controller polls `GET /:customer_id/payments/payments/:id/status` every 2s.
   - **H5:** `h5-redirect` Stimulus controller `window.location =` PSP URL.
   - **JSAPI:** `jsapi-invoker` Stimulus controller invokes `WeixinJSBridge.invoke` / `ap.tradePay`.
5. PSP webhook → `POST /payments/webhooks/:provider` → `WebhookDispatcher`:
   - Adapter verifies signature.
   - Resolves tenant by `[provider, merchant_id]` lookup on `PaymentMerchantAccount`.
   - Invokes `Activities::HandleWebhook` → transitions `Payment` + `PaymentOrder` to `succeeded` / `paid`.
6. User returns via `results#show` → `ResultComponent` with "return" CTA honoring FeatureModule `default_exit`.

### Refund
Admin UI → `Admin::TransactionsController#refund` → `Activities::Refund`:
creates `PaymentRefund` (status `requested`) → `Gateway.refund` (sync result)
→ webhook later confirms.

### Subscription
`Gateway.subscribe` returns sign URL/params → user signs in PSP app →
webhook flips `PaymentSubscription` to `active` → cron job
`Cron::ChargeDueSubscriptions` runs per cycle, calls `Gateway.charge_subscription`
for each due subscription.

### Reconciliation
Daily cron `Cron::DownloadBills` iterates active merchant accounts,
`Gateway.download_bill(bill_date: yesterday)` per provider, parses CSV,
diffs local `Payment` rows, writes `PaymentReconciliationBill` with
discrepancy count; admins view via `Admin::ReconciliationsController`.

## Error Handling

- `Payments::Adapters::TransportError` — retryable (network/5xx); activities retry via ActiveJob with exponential backoff, max 3.
- `Payments::Adapters::ApiError` — terminal (PSP rejected); `Payment.status = "failed"` with `failure_reason`.
- `Payments::CredentialsMissing` — checkout renders "Payments not configured"; admins see CTA to settings.
- Webhook signature failure — dispatcher returns `400`, logs security warning with request fingerprint; no DB write.
- Contract violations — Reform contracts reject at controller boundary; currency MUST equal `"CNY"`.
- **Idempotency:** every PSP call uses our generated `out_trade_no` / `out_refund_no`. Duplicate POSTs return the existing row. `HandleWebhook` is idempotent — re-entry to the same terminal state is a no-op.
- **Tenant isolation:** all non-webhook controllers enforce `Current.customer`; all models scoped; webhook path carries no tenant — resolved from payload only.

## Routes

```ruby
scope "/:customer_id/payments", as: :payments do
  get   "checkout",              to: "payments/checkouts#show"
  post  "checkout",              to: "payments/checkouts#create"
  get   "payments/:id/status",   to: "payments/checkouts#status", as: :payment_status
  get   "result/:payment_id",    to: "payments/results#show",    as: :result

  namespace :admin do
    resources :merchant_accounts, only: %i[index new create edit update]
    resources :transactions,      only: %i[index show] do
      member { post :refund }
    end
    resources :subscriptions,     only: %i[index show] do
      member { post :cancel }
    end
    resources :reconciliations,   only: %i[index show]
  end
end

post "/payments/webhooks/:provider", to: "payments/webhooks#create", as: :payments_webhook
```

## FeatureModule Registration

Rewritten `FeatureModules::Payment::Registration`:

```ruby
module FeatureModules
  module Payment
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "payment"
      def self.module_name        = "Payments (WeChat + Alipay)"
      def self.module_description = "Accept WeChat Pay and Alipay (China) — charge, refund, reconciliation, subscriptions"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.revoke(customer)

      entry_path   { |customer| "/#{customer.id}/payments/checkout" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :external_ref, validates: { presence: true }
        property :amount_cents, validates: { presence: true, numericality: { greater_than: 0, only_integer: true } }
        property :currency,     validates: { presence: true, inclusion: { in: %w[CNY] } }
        property :subject,      validates: { presence: true }
        property :body
        property :expires_at
        property :metadata
      end

      output_contract do
        property :payment_reference, validates: { presence: true }
        property :status,            validates: { inclusion: { in: %w[succeeded failed] } }
        property :paid_at
      end
    end
  end
end
```

`Provisioner.call(customer)` creates disabled `PaymentMerchantAccount` shells
(`wechat_pay`, `alipay` × `sandbox`, `production`) so the admin UI can edit
them in place. `revoke` destroys them.

## ViewComponents and Stimulus

All styling via TailwindCSS; all interactivity via StimulusJS.

- `Payments::CheckoutComponent` — provider picker (WeChat | Alipay).
- `Payments::QrCodeComponent` — renders QR from `code_url`; Stimulus controller `payments--qr-poll` polls status endpoint every 2s, swaps component on resolution, timeout after 3 min.
- `Payments::H5RedirectComponent` — auto-redirect; Stimulus controller `payments--h5-redirect`.
- `Payments::JsapiInvokerComponent` — invokes `WeixinJSBridge.invoke('getBrandWCPayRequest', ...)` or `ap.tradePay(...)`; Stimulus controller `payments--jsapi-invoker`.
- `Payments::WaitingComponent` — shared waiting UI.
- `Payments::ResultComponent` — success/failure with return CTA.
- `Payments::Admin::TransactionTableComponent`, `::RefundDialogComponent`, `::SubscriptionTableComponent`, `::ReconciliationTableComponent`, `::MerchantAccountFormComponent`.

## Testing Strategy

- **Models:** RSpec — validations, uniqueness, tenant scoping, state transitions.
- **Adapters:** RSpec with WebMock. Fixture PSP responses under `spec/fixtures/payments/{wechat,alipay}/`. Fixture-only RSA keypair + WeChat APIv3 key for signing/verification tests.
- **Activities:** RSpec per branch — success / API error / transport error / contract violation / idempotent re-entry.
- **Controllers:** request specs covering each route; tenant isolation; webhook signature-fail returning 400.
- **ViewComponents:** per-permutation rendering specs (WeChat+QR, Alipay+H5, JSAPI, etc.).
- **System specs:** Capybara — QR happy path (PSP polling stubbed), H5 redirect, JSAPI JS-bridge invocation, admin refund flow.
- **Cron jobs:** `ChargeDueSubscriptions`, `DownloadBills` specs.
- **Coverage:** 100% of new code in `app/services/payments/**`, `app/models/payment*`, `app/controllers/payments/**`, `app/components/payments/**`.

## Removal / Cleanup

- Delete `app/services/feature_modules/payment/registration.rb` (rewritten, not preserved).
- Any existing `feature_modules/payment/*` stubs replaced.
- `page_layout_templates/templates/payment/*` is **not touched** per AGENTS.md.

## Open Questions Resolved in This Spec

- Currency: **CNY only**.
- Credentials: **per-tenant** in `payment_merchant_account`, encrypted at rest.
- Sandbox/production: **per-tenant `mode` column**.
- Page scope: checkout, waiting, result, admin merchant-accounts, admin transactions, admin subscriptions, admin reconciliations.
- Order ownership: payment module owns `PaymentOrder` (keyed by host `external_ref`).
- Webhook tenant resolution: via `[provider, merchant_id]` payload lookup.
