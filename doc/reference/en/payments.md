---
title: "Payments"
summary: "Gateway registration, committed payment attempts, verified account-bound settlement and recurring ownership."
---

## Summary

`FeatureModules::Payment::Registration` (key `payment`) charges, refunds, subscribes and reconciles through Alipay, WeChat Pay, Stripe and PayPal gateways. Registration/credential discovery uses one Base subclass plus `register!`, without per-vendor migrations or merchant columns. Settlement handlers remain provider-specific; registration alone does not implement another vendor's callbacks or bill semantics.

A customer turns a gateway on by setting `Payments::MerchantAccount#status` to `"active"` and filling the credential blob. Checkout and `Payments::CredentialResolver` keep only active rows. Platform availability is a separate flag on `Payments::PlatformGateway`.

## Configure the payment providers

1. At `/81721200/admin/maintenance/platform/module_settings/payment/gateways`, make only the gateways you intend to offer available. Enable Payments for each customer at `/:cid/admin/maintenance/modules`.
2. At `/:cid/admin/settings/modules/payments/merchant_accounts`, edit that customer's **Sandbox** or **Production** row. Replace the seeded `unset-...` merchant identifier with a value unique across customers **for that provider**, fill **every** credential field below, and activate the row. In Rails production only `production` rows are used; all other Rails environments use `sandbox` rows. A platform switch turned off also disables tenant rows, which must be reactivated after switching it back on.
3. Host notification endpoints on a publicly reachable HTTPS origin and set `APP_HOST` to its public host. The public `POST https://<host>/payments/webhooks/<provider>` endpoints have **no tenant prefix**. Production's `force_ssl` generates HTTPS URLs; development URL helpers default to HTTP unless configured for HTTPS. Check the generated Alipay/WeChat order `notify_url` and Alipay WAP buyer return URL in the environment you use. A tenant notification URL override changes only the callback, not Alipay's buyer return URL. WeChat does not supply a buyer result URL to its payment API. The result page (`/:cid/payments/result/:out_trade_no`) is not a webhook. Verify a real payment and its notification; an Alipay/WeChat **Test connection** response is only an assumed success, not a vendor ping.

Production boot requires an explicit `APP_HOST`, secure `APP_PROTOCOL` (default `https`) and a valid optional `APP_PORT`. Mail and gateway helpers share the validated application `default_url_options`; gateways do not re-read environment values or substitute localhost. The only missing-host exception is `SECRET_KEY_BASE_DUMMY=1` with **only** `assets:precompile` as a top-level task: `assets-build.invalid` is explicitly marked build metadata. Server, worker, migration and mixed-task boots retain strict runtime configuration.

### Alipay (`alipay`)

1. In [Alipay Open Platform](https://openhome.alipay.com/platform/developerIndex.htm), create/approve an application with the required web/mobile payment products; configure **RSA2 public-key signing**. Put its **App ID** in the row's Merchant ID; put the application's **private key PEM** in `private_key_pem` and the **Alipay public key PEM** in `platform_public_key_pem`. This adapter uses public-key mode, not certificate-mode files. See Alipay's [official SDK configuration](https://github.com/alipay/alipay-easysdk/blob/master/java/README.md).
2. Expose `POST https://<host>/payments/webhooks/alipay`; Anysys includes its URL as `notify_url` on the payment request. The H5/WAP flow also supplies the browser result URL. Check QR, H5 and in-app permissions separately; in-app calls need a buyer ID, and agreement-based recurring payments need their own product approval.
3. Ordinary nonbilling APIs use `https://openapi.alipay.com/gateway.do`, including app Sandbox rows. Billing authorization/collection selects the configured sandbox/production endpoint; historical Billing query/refund/close/revocation uses the recorded accepted mode when available. Validate the intended flow/environment with a transaction and signed notification.

### WeChat Pay (`wechat_pay`)

1. Obtain a merchant number (`mchid`), bind a permitted Official Account/Mini Program AppID, and request the [JSAPI](https://pay.weixin.qq.com/doc/v3/merchant/4015423216), [H5](https://pay.weixin.qq.com/doc/v3/merchant/4015614193), and Native product permissions needed for your flows. Register the real [JSAPI payment authorization directory](https://pay.weixin.qq.com/doc/v3/merchant/4013287088) and [H5 payment domain](https://pay.weixin.qq.com/doc/v3/merchant/4013287193) in the merchant platform. JSAPI also needs the payer's OpenID for the configured AppID.
2. Put `mchid` in Merchant ID and fill `appid`, the 32-character `api_key_v3`, merchant API-certificate `private_key_pem`, WeChat Pay `platform_public_key_pem`, and merchant `wechat_cert_serial`. These are **different** keys and certificates; see WeChat's [APIv3 parameter locations](https://pay.weixin.qq.com/doc/v3/merchant/4013070756) and [certificate guide](https://pay.weixin.qq.com/doc/v3/merchant/4024350132). Confirm the merchant's WeChat platform-certificate/public-key mode against the adapter's signature verification.
3. Ensure the order's generated `notify_url` points to `https://<host>/payments/webhooks/wechat_pay` (or use the tenant override); it must meet WeChat's [public HTTPS callback requirements](https://pay.weixin.qq.com/doc/v3/merchant/4012075420). **Separately configure refund-result notifications** in WeChat's merchant platform at **Transaction Center → Refund Management → Refund Configuration**, using the same public callback URL: the adapter's refund request omits the optional [`notify_url`](https://pay.weixin.qq.com/doc/v3/merchant/4012791862), so the payment-order callback does not configure refund notifications. This adapter always calls `api.mch.weixin.qq.com`, including for app Sandbox rows; recurring agreement payments are not implemented. Test a real QR/H5/JSAPI payment, refund and notifications rather than relying on **Test connection**.

### Stripe (`stripe`)

1. In [Stripe Dashboard → API keys](https://docs.stripe.com/keys), obtain `sk_test_...` and `pk_test_...` for the Sandbox row. At [Workbench → Webhooks](https://docs.stripe.com/webhooks), create a **Your account / snapshot events / webhook endpoint** destination at `https://<host>/payments/webhooks/stripe`; copy its `whsec_...` signing secret. Enter `secret_key`, `publishable_key`, `webhook_signing_secret`, and a tenant-unique Merchant ID routing value (the app places it in Stripe object metadata).
2. Subscribe to `payment_intent.succeeded`, `setup_intent.succeeded`, `refund.updated`, `charge.refund.updated`, and `charge.dispute.created`, `.updated`, `.closed`. Enable the desired [payment methods](https://docs.stripe.com/payments/payment-element) in the Stripe account; Anysys uses Payment Element for card checkout.
3. For Production, obtain separate `sk_live_...` / `pk_live_...` keys and register a **live** webhook destination with its **own** `whsec_...`. Test checkout, an actual signed webhook, saved cards if needed, and refunds in each mode. Stripe's [test/live credentials and endpoints](https://docs.stripe.com/keys) are distinct.

### PayPal (`paypal`)

1. In [PayPal Developer Dashboard → Apps & Credentials](https://developer.paypal.com/api/rest/), create/select a **Sandbox REST app** and copy its Client ID and Client secret. Under the **same app's Webhooks**, add `https://<host>/payments/webhooks/paypal` and copy its **Webhook ID**. Enter `client_id`, `client_secret`, `webhook_id` and a tenant-unique Merchant ID routing value (the app writes it to Order `custom_id`). See the [official webhook registration guide](https://developer.paypal.com/api/rest/webhooks/rest/).
2. Subscribe to `PAYMENT.CAPTURE.COMPLETED`, `PAYMENT.CAPTURE.REFUNDED`, and `CUSTOMER.DISPUTE.CREATED`, `.UPDATED`, `.RESOLVED`. Use real signed sandbox notifications; [mock events cannot verify through postback](https://developer.paypal.com/api/rest/webhooks/rest/). Refund requests now include merchant `custom_id`; older/early callbacks route through provider-scoped local refund/invoice/capture linkage. Unverified links are never fetched. Wallet/guest-card options depend on eligibility.
3. Repeat app credentials, webhook registration and Webhook ID in **Live** for the Production row; see [PayPal's go-live guide](https://developer.paypal.com/api/rest/production/). This adapter switches between PayPal sandbox and live APIs. PayPal subscriptions, card vaulting and bill downloads are not implemented.

## Flow

```text
Platform owner marks Payments::PlatformGateway available
        |
        v
FeatureModules::Payment::Provisioner
        |  one MerchantAccount per (customer, provider, mode)
        |  merchant_id unset-<provider>-<mode>-<id>, status disabled
        v
Admin sets status active + credentials JSON
        |
        v
Payments::EligibleGateways
        |  platform-available AND configured? AND currency
        v
Payments::Activities::Charge (and refund, subscribe, vault, reconcile)
        |
        v
Payments::Gateway -> Payments::Gateways::<Vendor>#charge
        |
        v
POST /payments/webhooks/:provider
        |
        v
Payments::WebhooksController
        v
Payments::WebhookDispatcher
        |  extract_merchant_id, then verify_notification
        v
Payments::WebhookEvent + Payments::ProcessWebhookEventJob
        v
Payments::Activities::HandleWebhook
```

Public checkout is `Payments::CheckoutsController` at `/:cid/payments/checkout`. Member card vaulting is `Member::Payments::PaymentMethodsController` at `/:cid/member/payments/payment_methods`. Those paths are public and member URLs. They are outside the four admin surfaces.

## Implementation

### One gateway file

`Payments::Gateways` is `PluginRegistry` over `app/services/payments/gateways` with `defaults: false`. There is no registry-wide default gateway. A subclass declares `key` (stored as `MerchantAccount#provider` and used in the webhook URL), `display_name`, `credential_fields`, `supported_flows`, and `capabilities`. `supported_flows` is a subset of `:qr`, `:h5`, `:jsapi`, and `:card`. The class implements `extract_merchant_id(headers, body)` and the instance API `charge`, `query`, `refund`, `close`, `subscribe`, `cancel_subscription`, `charge_subscription`, `download_bill`, and `verify_notification`. Card gateways also implement `vault_card`, `detach_token`, `charge_token`, and `fetch_payment_method`. `register!` runs at the end of the class body.

`extract_merchant_id` normally supplies a routing hint before signature verification. An exact stored Stripe/PayPal PSP operation resolves its pinned historical account, independent of current environment mode. Known unbound or ambiguous local operations are rejected for offline repair. For an uncorrelated Stripe event without routing hints, the official signature verifier may authenticate a unique retained account before returning a route; invalid or shared/ambiguous secrets are rejected. An ID-only payload is never authentication. `event_id` is the dedup key on `Payments::WebhookEvent`. A blank event id makes `WebhookDispatcher` call `HandleWebhook` inline.

The route constraint on `POST /payments/webhooks/:provider` reads `Payments::Gateways.keys` at request time. `routes.rb` does not list vendor names. `Payments::WebhooksController` is an `ActionController::API` (no session, no CSRF). Provider `alipay` responds with the body `success`. Other providers get `head :ok`. `SignatureInvalid` is 400. `TenantNotFound` is 404.

`Payments::Gateway` is the facade. `CredentialResolver.call` requires an active runtime-mode account for new operations (`production` in production, otherwise `sandbox`). `by_merchant_id` admits retained disabled accounts for verification. `for_payment(customer:, payment:, historical: true)` defaults to exact historical row lookup with customer/provider checks; `historical: false` additionally enforces the accepted merchant-label/mode snapshot. New facade writes require that strict binding plus active, configured, platform-available credentials. Historical query/refund/close rejects a different explicit merchant and permits mutable label/mode edits on the same retained row; it never substitutes a current-mode replacement.

### Merchant accounts

`Payments::MerchantAccount` is tenant-scoped. Uniqueness is `(customer_id, provider, mode)` and, separately, `(provider, merchant_id)`. Vendor secrets live in the encrypted `credentials` JSON. Read with `credential`. `write_credentials` keeps the stored value when the new value is blank. `configured?` requires `enabled?`, a merchant id that is present and does not start with `unset-`, and a stored value for every `credential_fields` name. `STATUSES` are `active` and `disabled`.

`Payments::EligibleGateways.for` keeps gateways that are in `PlatformGateway.available_providers`, have a configured active account in the current mode, and list the requested currency in `supported_currencies`. `Payments::SetDefaultGateway` upserts `Payments::DefaultGateway` only for a provider that set returns.

`FeatureModules::Payment::Provisioner` seeds a disabled row per registered gateway that the platform has marked available, for both `sandbox` and `production`. `revoke` sets every account for the customer to `disabled` and leaves the JSON in place. Turning a platform tender off in `PlatformGatewaysController` disables that provider's tenant rows the same way. Turning it on back-fills missing rows.

### Activities

`Payments::Activities::Charge` locks the order, refuses a settled or expired order, picks a flow with `Payments::FlowSelector`, and calls `Payments::Gateway.charge`. `save_card` is forwarded only when the gateway's `capabilities` include `:tokenized_cards` and a user is present. Sibling activities are `Query`, `Refund`, `CreateSubscription`, `CancelSubscription`, `ChargeToken`, `VaultCard`, `Reconcile`, and `HandleWebhook`. `HandleWebhook` refuses to mark a payment paid when the notified amount is present and differs from `payment.amount`.

The handoff input contract (amount, currency `CNY`, subject, optional body, expires_at, metadata) is on the registration. Completion returns `payment_reference`, `status` (`succeeded` or `failed`), and `paid_at`. Flowchart steps that call this module are covered on [flowchart runtime](flowchart-runtime).

### Flowchart steps

`request_payment` (fields `amount`, `currency`, `subject`, all expressions) does not create an order or charge inside the submission. `FlowchartRuntime::Payments.request` normalizes the amount with `Payments::Money.normalize`, upcases the currency, checks that the Payment module is registered with handoff and enabled for the run's customer, and writes `ctx[:submission_outcome]["handoff"] = { "module_key" => "payment", "input" => { amount, currency, subject } }`. After the run succeeds, `PublicPagesController` starts the Payment handoff with that input and `Payments::CheckoutsController` creates the single `Payments::Order` (`build_order_from`). Failures are `request_payment.invalid_order` and `request_payment.module_disabled`. This differs from the original design, in which the step created a pending order itself.

`refund_payment` (fields `payment`, `amount`, optional `reason`) calls `FlowchartRuntime::Payments.refund`. The payment must belong to the run's customer (otherwise `refund_payment.not_found`); the refund runs `Payments::Activities::Refund` under `Current.set(customer:)`. `Payments::Errors::RefundNotAllowed` maps to `refund_payment.not_captured`, `non_positive`, `exceeds_remainder` or `billing_collection`; any other payment error is `refund_payment.failed`. See [Flowchart runtime](flowchart-runtime) and [Flowchart step actions](flowchart-step-actions).

### Historical data preflight

Data-only migration `20261011190000_backfill_payment_historical_bindings.rb` is separate from Billing's financial lifecycle migration. Before deployment, run the offline preflight against the intended database:

```bash
RAILS_ENV=production bin/rails payments:historical_bindings:preflight
RAILS_ENV=production bin/rails payments:historical_bindings:apply
```

The versioned repair accepts only an explicit existing account ID or unique `(provider, merchant_id)` matched to recorded payment-operation IDs or a previously verified ledger signer. It checks tenant/provider ownership and conflicting references; one available account for a customer/provider is not sufficient. Unknown, conflicting, foreign or malformed evidence is reported by record ID. Apply/migration rejects the entire unresolved plan before making any changes, rather than silently guessing.

Repair adds only `_attempt` identity or the server-owned `_anysys_verification` envelope, preserving money, status, timestamps, order/trade/refund numbers and original payload fields. It does not reconstruct or authorize an old financial retry; newly recovered attempt identity is marked `historical_identity_backfill` for reconciliation. Migration rollback is intentionally irreversible. No request-time compatibility/backfill path exists, no PSP/network lookup occurs, and no Billing lifecycle rows are rewritten. If explicit merchant evidence was discarded, reconcile authoritative PSP/ledger records externally before retrying the preflight; runtime lookup continues to reject unbound records.

Migration-boundary specs now live in `spec/migrate/backfill_payment_historical_bindings_spec.rb`; the existing service spec retains its provider/evidence matrix. The migration specs insert true pre-envelope rows into SQLite tables reconstructed from `91b89d3e:db/schema.rb`, verify deterministic signer/operation mapping, repeat-apply stability, entire-plan refusal for missing/ambiguous/foreign evidence and irreversible rollback. They compare the complete old financial/user/refund rows and schema, allowing only the identity-envelope additions. The versioned repair's Base-bound row classes run in a child process using that disposable database; the RSpec application's connection pool is never reconfigured. No provider operations run. Exact targeted results and shared harness details are in `docs/audits/2026-10-11-billing-migration-qa.md`.

### Four surfaces

| Surface | Path | Controller |
| --- | --- | --- |
| Entries | `/:cid/admin/modules/payments/transactions`, `/reconciliations`, `/disputes` | `Admin::Modules::Payments::TransactionsController`, `RefundsController`, `ReconciliationsController`, `DisputesController` |
| Customer settings | `/:cid/admin/settings/modules/payments/merchant_accounts` | `Admin::Settings::Modules::Payments::MerchantAccountsController`, `DefaultGatewaysController` |
| Enable / disable | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`, `ModuleEnablementsController` (`provision!` / `revoke`) |
| Platform settings | `/:cid/admin/maintenance/platform/module_settings/payment/gateways` and `/webhook_events` | `Admin::Maintenance::Platform::Payments::PlatformGatewaysController`, `WebhookEventsController`; shared panes on `ModuleSettingsController` |

`TransactionsController` lists `Payments::Payment.for_current_customer.commerce`, which excludes orders whose `external_ref` starts with `billing-inv-`. The module has no admin Subscriptions surface: the organization's own plan, payment methods and invoices are managed in Settings / Billing at `/:cid/admin/settings/billing/*` (see [Billing](billing)), and `/:cid/admin/modules/payments/subscriptions` returns 404. Members still view and cancel their own `payments_managed` card subscriptions at `/:cid/member/payments/subscriptions`. `Refund` refuses `billing_collection` payments. Billing mandates are not cancelled from this module. The registration's `entries_for("transactions")` is a different relation: `FeatureModules::Log` for the payment module. Sidebar links use the dedicated controllers.

The module key is `payment`. URL segments are `payments`.

The optional Return URL on the generic Payments configuration form (`/:cid/admin/settings/modules/payments`, linked from Settings / Payments at `/:cid/admin/settings/modules/payments/return_url`) is available only while the platform owner has enabled Handoff for Payments. It is a customer-level fallback for a shopper returning after a successful page-to-payment handoff; a page-specific exit target takes priority. The standalone payment result page also uses this URL for its **Return** button while Handoff is enabled. Disabling Handoff hides the form and ignores (but retains) any previously saved URL, so a standalone result uses the normal default instead. It does not change the payment gateway's notification webhook, buyer return URL, or merchant account settings. See [module framework](module-framework) for the fallback order and the other modules.

## Where to pay attention

### Route audit: checkout, settlement and recurring invariants

Public checkout/status/result permit foreign signed-in visitors while retaining URL-tenant order/payment scopes and `current_tenant_user` card attribution. Default provider resolution is reused consistently. Handoff charge/completion require invocation-derived order reference and monetary identity as well as token. Amounts must remain finite/positive after currency normalization; user-collected fields are scalar. Missing invocation falls back to the public root. See [Module framework](module-framework) and [Tenancy and roles](tenancy-and-roles).

`PrepareAttempt` commits identity before HTTP, freezing provider/flow/user, money/content, account/mode and operation parameters in `_attempt`. Pending retries keep original flow/payload. Definitive rejection may fail; uncertain writes retain identity/reservation. `AttemptSafety` bounds Stripe one-time/token-charge/refund replay to 23 hours before reconciliation. Checkout collects same-tenant member Stripe save-card consent on the provider-selection POST before PaymentIntent creation; the later widget cannot change frozen consent. Gateway charge/token-charge use the committed eligible account and recorded client IP, not a new environment selection.

Billing collection shares `AttemptSafety.definitive_rejection?`: neither an arbitrary API exception nor a not-found-shaped unclassified payload releases the original operation identity. An uncertain write can already have captured; recovery reconciles that same payment before considering another submission. Definitive provider declines permit a new keyed attempt, with successful settlement applied once. The committed-collection regression checks durable rows from a second connection and verifies no second capture after an uncertain response.

Billing zero-grace capture uses the accepted request deadline, not unpaid-access grace: initial/renewal requests can collect and apply valid captured money within their fixed period without unpaid purchased access. Recovered finalization schedules the existing disposition job only after commit; the daily batch and repeated deliveries share one collection attempt. An overdue expired request cannot authorize another PSP submission.

Webhook records retain verified account ID and original body in a server-owned `_anysys_verification` payload envelope. Already-verified payment/refund settlement binds to that exact account row, not its current mutable merchant routing label; a missing verified account raises a retryable credentials error. Handlers retain provider/customer, asserted amount/currency and PSP-identity checks. `ProcessWebhookEventJob` claims a ten-minute `_anysys_processing` lease under a short row lock, runs handler/provider HTTP outside the event transaction, and marks processed only after successful projection by the same claim token. A failed projection releases its lease; stale claims can be recovered, and an old worker cannot complete or clear a successor's claim. Domain handlers remain idempotent across lease expiry/recovery. Separate primary/queue databases still require hourly redrive of stranded received rows. A Billing authorization confirmed on a disabled historical account can become active without becoming the default or charge-ready; readiness still gates collection.

Merchant-account forms permit only shared typed attributes and the actual selected provider's credential keys. On update the provider comes from the scoped persisted account; forged provider/mode and foreign-vendor credential fields cannot become model columns or change its provider identity. Blank secrets retain their existing encrypted values.

Recurring deduplication includes resumable paused rows and requires supported currency. A stranded `pending_sign` card subscription is activated on the next create instead of being returned as already live. Billing vault tokens are rejected. Persisted dunning/SCA transitions preserve cancellation/expiry. `managed_by == "billing"` mandates have no general Payments schedule; [Billing](billing) owns collection. Platform billing tokens have nil `user_id` plus purchasing-customer/authorizer fields, distinct from member cards. Signed Stripe setup and Alipay agreement events synchronize exact billing authorization and settlement, keeping failures retryable.

Alipay validates business roots/codes and preserves uncertain transient outcomes; URL/RSA errors use module types. Query returns major-unit amount, uppercase currency and authoritative settled_at. WeChat signs vendor HTTPS bill URI, checks supplied SHA1 and normalizes payment/refund/reversal rows. Reconcile pins account/provider/currency, compares refund rows to exact local Refund identity/amount/outcome, and keeps processing bill snapshots from regressing authenticated success. Refund-only bills skip reverse payment checks; reversal/unmatched rows remain discrepancies. WeChat refund callback configuration and lack of automated pending-one-time query remain boundaries.

Payment/email webhook constraints parse an anchored PATH_INFO provider before an optional format suffix; `.json`/`.xml` retain registered-provider dispatch and proof checks. Query/body provider hints cannot select a route. Already-verified settlement survives account label edits, but first-arriving old-label notifications and destroyed key history still require retained routing/key identity; no historical key-version store is implemented.

The same account-ID binding applies to verified Billing Stripe setup metadata, preserving the accepted original context after routing-label edits. Historical reads use the pinned row's currently retained credentials; replacing those credentials may make the original PSP account unreachable even though the local row still exists. This requires owner reconciliation/correct retained credentials, not guessed replacement accounts or fresh charges. Billing leaves an ambiguous attempt unresolved when a negative query follows known label/mode drift. This source follow-up adds no credential-version store or routing aliases.

:::note
Gateway, attempt/refund reconciliation, callback and pre-intent consent APIs are source-documented. Targeted isolated-database verification remains in the payment RSpec follow-up audit. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. That run is not a real PSP, deployment, or concurrency test.
:::

:::attention
A new gateway is one file under `app/services/payments/gateways/` that subclasses `Payments::Gateways::Base` and calls `register!`. `Payments::WebhookDispatcher`, `Payments::WebhooksController`'s route constraint, and `Payments::MerchantAccount` validation all read `Payments::Gateways`. Do not add a typed credential column. Secrets go through `MerchantAccount#write_credentials` into the encrypted `credentials` JSON. Blank form values keep the stored secret.
:::

:::attention
`status == "active"` is what `Payments::MerchantAccount#enabled?` and `Payments::CredentialResolver` filter on. Checkout also goes through `Payments::EligibleGateways`, which requires `Payments::PlatformGateway.available_providers` and `MerchantAccount#configured?`. A row left at `unset-<provider>-...` or missing a `credential_fields` value stays out of checkout even when status is active. `Provisioner` creates rows as `disabled`.
:::

:::attention
`extract_merchant_id` is routing input, not proof. Verification uses the exact retained account, including disabled historical rows. Merchant IDs are provider-unique across tenants. Alipay expects acknowledgment `success`.
:::

:::attention
`WebhookDispatcher` records and requests enqueue in a primary transaction; deferred/separate-database enqueue still needs recovery. Duplicate IDs retain original verified body/account; failed or 10-minute-stale received rows may redrive. Settlement rejects asserted money mismatch.
:::

## Key code

```ruby
# app/services/payments/gateways.rb
module Gateways
  extend PluginRegistry.build(label: "payment gateway", dir: "app/services/payments/gateways", defaults: false)
end
```

```ruby
# app/models/payments/merchant_account.rb
def enabled? = status == "active"

def configured?
  return false unless enabled?
  return false if merchant_id.blank? || merchant_id.to_s.start_with?("unset-")

  gateway_class.credential_fields.all? { |f| credential(f[:name]).present? }
end
```

```ruby
# app/services/payments/credential_resolver.rb
def self.call(customer:, provider:, mode: default_mode)
  acc = Payments::MerchantAccount.unscoped_by_tenant
                              .where(customer_id: customer.id,
                                     provider: provider, mode: mode,
                                     status: "active")
                              .first
```

```ruby
# config/routes.rb
post "/payments/webhooks/:provider",
     to: "payments/webhooks#create",
     as: :payments_webhook,
     constraints: ->(req) {
        provider = req.path_info.match(%r{\A/payments/webhooks/([^/.]+)(?:\.[^/]+)?\z})&.[](1)
       Payments::Gateways.keys.map(&:to_s).include?(provider)
     }
```
