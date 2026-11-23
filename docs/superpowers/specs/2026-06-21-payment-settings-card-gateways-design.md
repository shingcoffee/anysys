# Payment Settings Refactor + Card Gateways (Tokenized) + Card Recurring — Design

Date: 2026-06-21
Worktree: `refactor-payment-module`
Status: Approved for planning (autonomous execution authorized by user)

## 1. Goal

Three cohesive pillars on top of the existing vendor-agnostic Payment module (today: Alipay + WeChat Pay, CNY-only, QR/H5/JSAPI flows):

1. **Enrich + refactor the admin payment settings UI** at `/:cid/admin/settings/modules/payments/` to a world-class layout (gateway gallery → per-gateway config), modeled on Stripe Dashboard / Shopify Payments.
2. **Add the most popular card payment processor (Stripe)** as a new gateway covering Visa / Mastercard / Amex / etc. (these are card *networks* handled by the processor, not separate integrations).
3. **Tokenize, never store cards** — no PAN/CVV ever touches our DB; we persist only PSP tokens (Stripe Customer id + PaymentMethod id) plus display metadata. **Support recurring (off-session) payments for a cardholder** using those tokens.

## 2. Guiding constraints (from AGENTS.md)

- Adding a *vendor* must stay a single-file change: `app/services/payments/gateways/stripe.rb` + `register!`. Schema/controllers/Settings UI/webhook dispatcher pick it up automatically. The cross-vendor *infrastructure* enrichments below (Base contract, flow selector, vault model, multi-currency) are the "refactor" half of the request and are done once, not per vendor.
- Vendor credentials live in the encrypted `credentials` JSON blob on `MerchantAccount`. No typed columns per vendor, no per-vendor migration.
- Multi-tenant: every new model carries `customer_id`; card vault rows additionally carry `user_id` (the cardholder). Member-owned records enforce both `customer_id` and `user_id`.
- URL areas: admin config under `/:cid/admin/settings/modules/payments/`; cardholder self-service under `/:cid/member/...`; public checkout stays public.
- ViewComponent + Tailwind + Stimulus only. Reform contracts + Trailblazer activities for business logic. Thin models.
- PCI posture: card data is captured exclusively inside the Stripe-hosted iframe (Payment Element / SetupIntent). We are PCI SAQ-A — the PAN never reaches our servers, logs, or DB.

## 3. Architecture changes

### 3.1 Gateway Base contract enrichment (one-time, vendor-agnostic)

Add to `Payments::Gateways::Base` so card processors are first-class and future card processors (PayPal/Braintree/Adyen) remain single-file:

- **Capabilities declaration** — `capabilities` returns a subset of
  `[:one_time, :recurring, :tokenized_cards, :refunds, :reconciliation, :webhooks]`.
  Drives the Settings UI badges and guards (e.g. only show "save card for later" when `:tokenized_cards`).
- **New flow `:card`** added to the recognized flow set `[:qr, :h5, :jsapi, :card]`.
- **Tokenization API** (default raise `NotImplementedError`, overridden by token-capable gateways):
  - `vault_card(user:, return_url:)` → `{ client_secret:, psp_customer_id: }` — begins a SetupIntent so the browser-side Stripe Element can confirm and vault a card off-session. Returns the PSP customer token to persist.
  - `detach_token(payment_method:)` → `{ status: :removed }` — revokes a vaulted token at the PSP.
  - `charge_token(order:, payment:, payment_method:)` → `{ psp_transaction_id:, status:, raw: }` — off-session charge against a stored token (used by member-initiated repeat charges and by `charge_subscription`).
- **Currency support** — `supported_currencies` returns an array of ISO codes (China gateways → `["CNY"]`; Stripe → a broad set incl. zero-decimal handling). `zero_decimal_currency?(code)` helper on Base for amount conversion.
- Existing methods unchanged: `charge`, `query`, `refund`, `close`, `subscribe`, `cancel_subscription`, `charge_subscription`, `download_bill`, `verify_notification`, `extract_merchant_id`, `register!`, `key`, `display_name`, `credential_fields`, `supported_flows`, `jsapi_user_agent_pattern`.
- For card providers, `charge_subscription(subscription:, payment:)` delegates to `charge_token` using the subscription's linked vaulted payment method.

### 3.2 FlowSelector refactor

`Payments::FlowSelector.call(request:, provider:)` today picks qr/h5/jsapi by user-agent. Refactor so it intersects the request heuristic with `gateway.supported_flows`:
- If the gateway supports `:card` and not the China flows (Stripe) → always `:card`.
- If the gateway supports the China flows (Alipay/WeChat) → keep the existing UA heuristic (jsapi for in-app browser, h5 for mobile, qr for desktop).
- Generalize to: pick the first supported flow from a provider-aware priority list. No behavior change for existing gateways.

### 3.3 Stripe gateway — `app/services/payments/gateways/stripe.rb` (single file)

- `key = "stripe"`, `display_name = "Credit / Debit Card (Stripe)"`.
- `capabilities = [:one_time, :recurring, :tokenized_cards, :refunds, :reconciliation, :webhooks]`.
- `supported_flows = [:card]`. `supported_currencies = %w[usd eur gbp cad aud jpy sgd hkd cny ...]`.
- `credential_fields`: `secret_key` (password, encrypted), `publishable_key` (string, unencrypted — needed client-side), `webhook_signing_secret` (password, encrypted). All in the encrypted `credentials` blob; publishable key is non-secret but lives there for uniformity.
- `merchant_id` = the Stripe account id (`acct_…`), fetched via `GET /v1/account` on connect-test; used by `extract_merchant_id`.
- **charge (flow `:card`)** → create a PaymentIntent (amount in smallest unit, currency-aware), return `{ prepay_payload: { client_secret:, publishable_key: } }`. The browser confirms via Stripe Payment Element; we never see the card. Optional `setup_future_usage: off_session` + `customer` when the shopper opts to save the card.
- **query** → `GET /v1/payment_intents/:id` → map status (`succeeded`/`processing`/`requires_*`/`canceled`).
- **refund** → `POST /v1/refunds`.
- **close** → cancel the PaymentIntent.
- **vault_card** → create/reuse a Stripe Customer, create a SetupIntent (`usage: off_session`), return its `client_secret` + customer id.
- **charge_token** → `POST /v1/payment_intents` with `customer`, `payment_method`, `off_session: true`, `confirm: true`.
- **subscribe / charge_subscription / cancel_subscription** → card-recurring is implemented in *our* engine (Subscription + cron) on top of `vault_card` + `charge_token`; `subscribe` ensures a vaulted token exists, `charge_subscription` delegates to `charge_token`, `cancel_subscription` flips local state (and detaches token if no other use).
- **verify_notification** → verify `Stripe-Signature` against `webhook_signing_secret` (timestamped HMAC, replay window enforced), parse the event.
- **extract_merchant_id(headers, body)** → read `account` from the event, falling back to PaymentIntent/SetupIntent `metadata.merchant_id` (we stamp our MerchantAccount.merchant_id into metadata on every create). Runs before signature verification, so it only routes — never trusts the body cryptographically.
- `register!` at end.

No Stripe SDK gem dependency assumed beyond what's already used; reuse Base's `http_post/http_get`. (Planning step confirms whether a `stripe` gem is desired; default is raw HTTP via Base helpers to match Alipay/WeChat style.)

### 3.4 New domain model — the card vault

`Payments::PaymentMethod` → table `payment_methods` (migration; this is cross-vendor infra, not vendor config, so a migration is correct here):

| column | type | notes |
|---|---|---|
| customer_id | integer | tenant scope (indexed) |
| user_id | integer | cardholder (indexed); member-owned |
| provider | string | e.g. "stripe" |
| psp_customer_id | string | Stripe Customer token |
| psp_payment_method_id | string | Stripe PaymentMethod token |
| brand | string | display only (visa/mastercard/amex…) |
| last4 | string | display only |
| exp_month | integer | display only |
| exp_year | integer | display only |
| is_default | boolean | one default per (customer, user) |
| status | string | active / expired / removed |
| timestamps | | |

Hard rule enforced by model + review: **no `pan`, `card_number`, `cvv`, or full-card column may ever exist on this table.** Only tokens + non-sensitive display metadata.

`Payments::Subscription` enrichment (migration): add `payment_method_id` (FK, nullable — agreement-based providers like Alipay leave it null) and `currency` (string, default existing CNY for back-compat-free new rows). Card subscriptions reference a vaulted `PaymentMethod`; the existing `ChargeDueSubscriptions` cron calls `charge_subscription`, which for card providers off-session-charges the token.

### 3.5 Multi-currency

- Relax `Payments::Contracts::Charge` and `Subscribe` currency validation from hard-coded `["CNY"]` to "must be in the selected gateway's `supported_currencies`".
- Add a tenant-level default currency setting surfaced in the gateway config (per merchant account, stored in `credentials` blob or a typed `default_currency` column on `payment_merchant_accounts` — **decision: typed column**, since currency is gateway-agnostic config, not a vendor secret; one shared migration, not per-vendor).
- Amount conversion respects zero-decimal currencies (JPY etc.) in the Stripe gateway.

### 3.6 Provisioner

No code change required: `FeatureModules::Payment::Provisioner` already iterates `Payments::Gateways.keys × modes`, so Stripe rows (sandbox/production) auto-seed when a tenant enables the module. Confirms the single-file rule.

## 4. Admin Settings UI refactor (`/:cid/admin/settings/modules/payments/`)

Replace the flat merchant_accounts index + monolithic form with a two-level, world-class IA. Decomposed into focused ViewComponents (Tailwind + Stimulus, responsive mobile→desktop):

1. **Gateway gallery** (`Payments::Admin::GatewayGalleryComponent`) — a responsive grid of gateway tiles.
   - **`GatewayCardComponent`** per gateway: logo/name, `StatusBadgeComponent` (Active / Needs setup / Disabled), supported-method chips (cards, wallets, QR…), current mode (Sandbox/Production), quick enable/disable toggle (Stimulus), "Configure" action.
2. **Gateway config page** (`Payments::Admin::GatewayConfigComponent`) — opened per gateway:
   - Environment switcher Sandbox ⇄ Production (each is its own MerchantAccount row).
   - **`CredentialFieldsComponent`** — the dynamic `credential_fields` renderer extracted from today's monolithic form (password fields keep the "leave blank to keep existing" encrypted-secret UX).
   - `merchant_id`, `notify_url_override`, **`default_currency`** (new), method-level accept toggles where applicable.
   - **"Test connection"** button (Stimulus → controller action → gateway ping, e.g. Stripe `GET /v1/account`) with success/error inline feedback and last-verified timestamp.
   - Enable/disable (status) toggle.
3. **Status semantics** — a row is "Needs setup" until required `credential_fields` are present and a successful test connection has occurred; "Active" when `status=active`; "Disabled" otherwise.

UI/UX produced via the **frontend-design plugin** through `anysys-ux-designer` before the frontend build. All surfaces responsive per AGENTS.md.

Controllers stay under `Admin::Settings::Modules::Payments::*` with `require_admin_or_owner!` guards and tenant scoping. Add a `MerchantAccounts#test_connection` member action (and a thin `GatewaysController#index` for the gallery if cleaner than reusing merchant_accounts#index).

## 5. Cardholder (member) surface — lean but required for "recurring for a card holder"

Under `/:cid/member/` (member-scoped, `customer_id` + `user_id` enforced; sign-in required):

- **`member/payment_methods`** — list / add / remove saved cards. "Add card" opens the Stripe Element backed by `vault_card` (SetupIntent); removal calls `detach_token`. Shows brand + last4 + expiry only. Stimulus controller `payments_stripe_card_controller.js` drives the Element + client-side confirmation.
- **`member/subscriptions`** — view own recurring plans, the linked card, next charge date; cancel. Creating a subscription against a saved card is allowed where a plan exists.
- Checkout enrichment: the public card checkout offers an optional **"Save this card for future payments"** checkbox (only when the gateway has `:tokenized_cards` and the shopper is an authenticated member), wiring `setup_future_usage` into the PaymentIntent.

## 6. Security & isolation

- Tokens only; PCI SAQ-A; PAN never stored/logged. A test asserts the `payment_methods` schema contains no card-number/cvv-like column.
- Member endpoints enforce `customer_id == current_user.customer_id` AND `user_id == current_user.id` on every record action; admin settings enforce admin-or-owner + same-tenant.
- Stripe webhook: tenant resolved from event before signature verification; signature then verified against that tenant's stored signing secret; replay window enforced. Cross-merchant spoofing rejected (signing merchant must match the payment's merchant account), mirroring the existing WeChat/Alipay dispatcher guard.
- Encrypted `credentials` blob holds Stripe secret + webhook secret; publishable key is non-secret but co-located.

## 7. Testing focus (RSpec, TDD)

- Gateway: `Stripe` charge/query/refund/vault/charge_token/verify_notification (HTTP stubbed), capability + currency declarations, zero-decimal conversion.
- Model: `PaymentMethod` (tenant + user scoping, default uniqueness, no-sensitive-column guard), `Subscription` card-linked charging + next-charge advance.
- FlowSelector: Stripe → `:card`; China gateways unchanged (regression).
- Contracts: multi-currency acceptance/rejection by gateway.
- Components: gallery, gateway card, credential fields, status badge, member payment-methods.
- Request/system: admin config + test-connection (admin-or-owner, tenant isolation), member payment-methods + subscriptions (member-only, user isolation, cross-tenant blocked), webhook routing + signature + replay.
- Multi-tenant isolation and authorization are first-class per AGENTS.md.

## 8. Out of scope

- Stripe Connect / marketplace split payments.
- PayPal / Braintree / Adyen gateways (the Base enrichment makes them future single-file additions; not built now).
- 3DS step-up customization beyond what the Payment Element handles automatically.
- Migrating existing Alipay/WeChat behavior (untouched except the no-op-compatible Base/FlowSelector refactor).
- Dunning/retry strategy beyond the existing cron's single attempt (can follow later).

## 9. Build pipeline (per AGENTS.md workflow)

PO brief (covered by this spec) → UX mockups (`anysys-ux-designer` + frontend-design) → writing-plans → parallel build (backend: Base/FlowSelector/Stripe/models/migrations/activities/contracts; frontend: settings + member ViewComponents/ERB/Stimulus; security: routes + controllers + guards) → QA (RSpec, tenant + authz focus) → release-engineer (RSpec + assets + smoke) → parallel review (tech-lead conventions + code-reviewer correctness/security).
