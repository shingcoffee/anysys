# Payments and captcha route audit — 2026-10-11

## Status and boundaries

This is the exhaustive **original read-only audit snapshot**, archived at the user's request during the subsequent gateway-only implementation. Evidence line numbers refer to the pre-remediation source inspected for that audit. They are historical references, not current offsets or assertions that concurrent remediation has left every finding open.

The original audit inspected source, schema, existing specs, installed framework/queue behavior and relevant vendor documentation. It did not edit files, run tests, launch subagents, execute application requests or transact with PSPs. Its working tree was clean at the beginning and end. “Confirmed” means the triggering conditions and outcome follow from the inspected implementation; concurrency examples specify the necessary interleaving rather than claiming an executed reproduction.

### Included routes

- Public payment checkout start/collect/complete/show/create, status and result.
- Public PSP callbacks for the four registered gateways.
- Admin payment transactions, refunds, subscriptions, cancellations, reconciliations, download and disputes.
- Customer payment merchant accounts, connection probe and default gateway.
- Platform payment gateway availability, webhook ledger and redrive.
- Member payment methods, setup intent, subscriptions and cancellation.
- Public captcha challenge GET/POST.
- Customer captcha status and public-page throttle settings.
- Platform captcha settings, connection probe, surface throttles and shared-page throttles.

### Excluded boundary and route list

- Customer billing routes under `/:cid/admin/settings/billing`: subscriptions, cancellations, coupon redemptions, payment methods, invoice listing/show/download.
- Platform billing routes under `/:cid/admin/maintenance/platform/billing`: plans, countable items, coupons, subscriptions/cancellations, invoices/mark_paid/void/retry and settings.
- Tenant/platform flowchart CRUD, versions, launch, validation, traces, documents, CRUD type and I/O inspection routes.
- Tenant/platform page-builder CRUD, versions, launch, previews, renders, field options/templates, module data and template application/picker/preview routes.
- Files under `app/services/page_layout_templates/templates/**`.
- General authentication, OAuth, website and public-page business behavior was not independently audited. Shared authorization, shortcut resolution and replay/handoff utilities were inspected only as dependencies of the included surfaces.
- The shared `Billing::CurrencyResolver` money-format/exponent utility is a payment dependency; inspecting its conversion behavior did not expand scope to billing collection or billing provider behavior.

## 1. Complete route/action coverage

Coverage: **22 controllers, 50 distinct actions and 58 explicit method/path variants**. Count PUT/PATCH separately and include the captcha status alias; exclude implicit HEAD and optional formats.

Prefixes:

- `C = /:customer_id`
- `A = C/admin/modules/payments`
- `S = C/admin/settings/modules/payments`
- `P = C/admin/maintenance/platform/module_settings`
- `M = C/member/payments`
- `CS = C/admin/settings/modules/captcha`
- `CP = P/captcha`

Platform routes are drawn with variable CID; AGENTS.md specifies `81721200` as their intended location.

### Public payments — config/routes.rb:86–92,216–225

| Method/path | Controller#action |
| --- | --- |
| GET `C/payments/checkout/start` | `payments/checkouts#start` |
| GET `C/payments/checkout/collect` | `payments/checkouts#collect` |
| POST `C/payments/checkout/complete` | `payments/checkouts#complete` |
| GET `C/payments/checkout` | `payments/checkouts#show` |
| POST `C/payments/checkout` | `payments/checkouts#create` |
| GET `C/payments/:id/status` | `payments/checkouts#status` |
| GET `C/payments/result/:payment_id` | `payments/results#show` |
| POST `/payments/webhooks/:provider` | `payments/webhooks#create` |

Webhook providers are discovered at request time: `alipay`, `wechat_pay`, `stripe`, `paypal`.

### Admin records — config/routes.rb:772–784

| Method/path | Controller#action |
| --- | --- |
| GET `A/transactions` | `admin/modules/payments/transactions#index` |
| GET `A/transactions/:id` | `admin/modules/payments/transactions#show` |
| POST `A/transactions/:transaction_id/refunds` | `admin/modules/payments/refunds#create` |
| GET `A/subscriptions` | `admin/modules/payments/subscriptions#index` |
| GET `A/subscriptions/:id` | `admin/modules/payments/subscriptions#show` |
| GET `A/subscriptions/new` | `admin/modules/payments/subscriptions#new` |
| POST `A/subscriptions` | `admin/modules/payments/subscriptions#create` |
| POST `A/subscriptions/:subscription_id/cancellation` | `admin/modules/payments/subscription_cancellations#create` |
| GET `A/reconciliations` | `admin/modules/payments/reconciliations#index` |
| GET `A/reconciliations/:id` | `admin/modules/payments/reconciliations#show` |
| GET `A/reconciliations/:id/download` | `admin/modules/payments/reconciliations#download` |
| GET `A/disputes` | `admin/modules/payments/disputes#index` |

### Customer payment settings — config/routes.rb:313–318

| Method/path | Controller#action |
| --- | --- |
| GET `S/merchant_accounts` | `admin/settings/modules/payments/merchant_accounts#index` |
| GET `S/merchant_accounts/new` | `admin/settings/modules/payments/merchant_accounts#new` |
| POST `S/merchant_accounts` | `admin/settings/modules/payments/merchant_accounts#create` |
| GET `S/merchant_accounts/:id/edit` | `admin/settings/modules/payments/merchant_accounts#edit` |
| PATCH/PUT `S/merchant_accounts/:id` | `admin/settings/modules/payments/merchant_accounts#update` |
| POST `S/merchant_accounts/:id/test_connection` | `admin/settings/modules/payments/merchant_accounts#test_connection` |
| PATCH/PUT `S/default_gateway` | `admin/settings/modules/payments/default_gateways#update` |

### Platform payments — config/routes.rb:621–630

| Method/path | Controller#action |
| --- | --- |
| GET `P/payment/gateways` | `admin/maintenance/platform/payments/platform_gateways#index` |
| PATCH/PUT `P/payment/gateways/:provider` | `admin/maintenance/platform/payments/platform_gateways#update` |
| GET `P/payment/webhook_events` | `admin/maintenance/platform/payments/webhook_events#index` |
| POST `P/payment/webhook_events/:id/redrive` | `admin/maintenance/platform/payments/webhook_events#redrive` |

### Member payments — config/routes.rb:838–846

| Method/path | Controller#action |
| --- | --- |
| GET `M/payment_methods` | `member/payments/payment_methods#index` |
| GET `M/payment_methods/new` | `member/payments/payment_methods#new` |
| POST `M/payment_methods` | `member/payments/payment_methods#create` |
| DELETE `M/payment_methods/:id` | `member/payments/payment_methods#destroy` |
| POST `M/payment_methods/setup_intent` | `member/payments/payment_methods#setup_intent` |
| GET `M/subscriptions` | `member/payments/subscriptions#index` |
| GET `M/subscriptions/:id` | `member/payments/subscriptions#show` |
| POST `M/subscriptions/:subscription_id/cancellation` | `member/payments/subscription_cancellations#create` |

### Captcha — config/routes.rb:32–33,327–333,607–615

| Method/path | Controller#action |
| --- | --- |
| GET `/captcha/challenge` | `captcha/challenges#show` |
| POST `/captcha/challenge` | `captcha/challenges#create` |
| GET `CS`, GET `CS/status` | `admin/settings/modules/captcha/status#show` |
| PATCH/PUT `CS/pages/:id` | `admin/settings/modules/captcha/pages#update` |
| GET `CP/settings` | `admin/maintenance/platform/captcha/settings#show` |
| GET `CP/settings/edit` | `admin/maintenance/platform/captcha/settings#edit` |
| PATCH/PUT `CP/settings` | `admin/maintenance/platform/captcha/settings#update` |
| POST `CP/settings/test_connection` | `admin/maintenance/platform/captcha/settings#test_connection` |
| PATCH/PUT `CP/surfaces` | `admin/maintenance/platform/captcha/surfaces#update` |
| GET `CP/pages` | `admin/maintenance/platform/captcha/pages#index` |
| PATCH/PUT `CP/pages/:id` | `admin/maintenance/platform/captcha/pages#update` |

## 2. Backend chains and enforcement

### Authorization/tenancy

`ApplicationController` composes TenantContext, FeatureModules::HostIntegration, RouteAuthorization, locale and MFA. TenantContext resolves URL tenant and rejects a different-tenant authenticated actor unless owner. RouteAuthorization authenticates protected prefixes, applies admin/member/platform-owner role gates, then CanCan. Member payments are not admin-preview surfaces.

Evidence: `app/controllers/concerns/tenant_context.rb:129–165`, `app/controllers/concerns/route_authorization.rb:68–76,118–155`, `app/models/ability.rb:41–69,96–110`.

`TenantScoped` has **no default scope**. `for_current_customer` explicitly uses Current.customer or returns none (`app/models/concerns/tenant_scoped.rb:47–52`). Included controllers use explicit tenant scopes. Member payment methods add user scope; member subscriptions scope through payment methods owned by that user.

Payment module guards cover checkout, admin payment records/settings and member payment routes. Results have no module guard. Captcha Rack gating is intentionally platform-wide, independent of tenant captcha-module enablement.

### Checkout/handoff/result

`start/collect → InvocationContext → Invocation.current` reads a tenant-checked session invocation. `complete → FeatureModules::HandoffCompletion → fillable-key filtering → InputCaster → registration input contract → tenant/derived-reference Order find-or-create`. Ordinary show/create require an existing tenant order; shopper monetary request fields are ignored.

`create → EligibleGateways/DefaultGateway → Contracts::Charge → Activities::Charge → FlowSelector → Gateway → CredentialResolver → concrete gateway → Payment/pending PaymentMethod`. Settlement/expiry/provider-switch checks precede charge.

`status/result → tenant + out_trade_no lookup → Query → gateway query/capture → HandleWebhook.finalize_success! → Payment → Order`. Integer IDs are restricted to owner fallback. Result invokes `Payments::HandoffCompletion → FeatureModules::Complete → output contract → exit resolution/log/session clear`.

### Webhook ledger/jobs/redrive

`WebhooksController#create` inherits ActionController::API: no session/CSRF; authenticity is per-provider. Raw body/headers flow through `WebhookDispatcher → extract_merchant_id → active merchant lookup → verify_notification → WebhookEvent(provider,event ID) → ProcessWebhookEventJob → event lock → HandleWebhook → payment/refund/vault/dispute mutation → mark_processed!`. Missing event IDs run inline.

Jobs retry five times before failed/dead-letter. Dispatcher can redrive failed or stale received events. Hourly RedriveWebhookEventsJob recovers stranded events; platform redrive admits received/failed only. Daily retention deletes events older than 90 days. Current is reset after webhook jobs.

### Transactions/refunds/disputes

Transaction index/show query tenant Payment rows; index includes orders/refunds/disputes. Refund create scopes the payment then calls `Money.normalize → Refund activity → parent-payment lock/reserved remainder → committed Refund → PSP refund → outcome transition → order refund totals`. Requested/processing/succeeded amounts reserve the ceiling; failed rows do not. `Contracts::Refund` is defined but not invoked on this path.

Disputes are read-only tenant listings. Stripe/PayPal callbacks resolve provider transaction IDs and upsert unique provider/dispute IDs. Resolved-to-nonterminal regression is guarded, but terminal-to-terminal changes are permitted.

### Subscriptions/cancellation/recurring jobs

Admin create selects a tenant-scoped confirmed active card, validates Subscribe, locks the card for duplicate enrollment, creates Subscription, invokes gateway subscribe, activates and schedules first collection one cycle later.

Hourly `ChargeDueSubscriptionsJob → enabled module → atomic claim → stable period Order → ChargeToken` for card recurring or agreement charge otherwise. Created attempts are reused after ambiguous failure, succeeded periods are advanced without recharging, pending periods wait, and declines/SCA pause without advancing. Claim TTL is 15 minutes.

Admin/member cancellation scopes Subscription, calls CancelSubscription/gateway cancel, marks cancelled and optionally detaches an orphan token. Member cancellation preserves the card; admin cancellation can remove a last-use card.

### Accounts/default/platform availability

Account create/update strong-params split shared columns from vendor fields, validate MerchantAccount and merge encrypted JSON credentials; blank credentials keep stored values. Provider/mode cannot be changed on update. Default gateway requires current eligibility and upserts one tenant row. Platform availability validates provider, backfills provisioned account rows on enable and disables tenant accounts on disable.

Connection probes select explicit account mode. Stripe uses account API; PayPal obtains OAuth token. Alipay/WeChat inherit documented assumed success.

### Bills/download

`DailyMaintenanceJob → DownloadBills → active Alipay/WeChat accounts → Reconcile → ReconciliationBill → gateway bill download → CSV/totals → ActiveStorage attachment → forward payment/amount check + reverse paid_at date check`. Admin download scopes bill and streams its attachment through the protected route; foreign IDs/missing attachment return 404.

### Member vault

`setup_intent → VaultCard → Gateway/Stripe Customer + SetupIntent → pending:<intent ID> PaymentMethod`. Succeeded setup/checkout intent notification finds pending row, applies merchant binding, retrieves card metadata and backfills the token. Create does not stamp a submitted token; destroy scopes tenant/user, detaches then soft-removes even after module error. VaultCard contract exists but this hard-coded Stripe route does not invoke it.

### Captcha challenge and configuration

`CaptchaRackGateProxy → UrlMatcher/canonical shortcut resolution → ThrottleRegistry/SurfaceCatalog → Rack::Attack counter → IP/pattern Grant → configured provider → redirect → RequestSnapshot for POST/PUT/PATCH`.

`Challenges#create → VerificationContext → Verify → active settings → TokenReplay → provider → score threshold/single-use consume → Grant → snapshot take → RequestReplayer → normal Rails dispatch`. Replay restores original path/query and clears parser/routing caches; captcha.replay skips the repeated Rack gate.

Provider settings update sanitizes, validates Reform/model, saves and activates/deactivates. Test connection submits a sentinel invalid token and stores health status. Customer page updates require customer-owned public Page and write exact throttle paths; platform page updates require shared public Page and write template paths; surfaces resolve trusted catalog keys. These actions change throttle rows, not page-builder definition versions.

### Provider behavior

| Provider | Authenticity/transport | Original integration behavior |
| --- | --- | --- |
| Alipay | RSA2 notifications, app-ID routing, 25-hour freshness | HTTP-200 business codes incompletely checked; production endpoint even for app Sandbox |
| WeChat | RSA freshness/signature, AES-GCM resource, cert cache/rotation | Encrypted routing tries active keys; download needs signing; refund callback separately configured |
| Stripe | Official per-account Stripe client, 300-second webhook HMAC | Keyed intent/refund, vault, off-session and SCA |
| PayPal | OAuth REST and signature postback, certificate-host check | Status/result capture approved orders; refund routing incomplete |
| Aliyun captcha | Signed RPC via Vendor::AliyunRpc | Browser API mismatch with official V2 SDK |
| Turnstile | Siteverify/binary outcomes | Returned hostname unused |
| reCAPTCHA v3 | Siteverify/score threshold | Returned hostname/action unused |

## 3. Ranked confirmed findings

### P1 — security/financial integrity

#### F1. Cross-provider merchant binding allows cross-tenant payment forgery

- Evidence: `app/services/payments/activities/handle_webhook.rb:177–194,581–599`; `app/services/payments/gateways/stripe.rb:70–76`; `app/models/payments/merchant_account.rb:34`; `db/schema.rb:939`.
- Trigger: tenant A's Stripe merchant routing ID equals tenant B's Alipay merchant ID (uniqueness is per provider). An A-signed Stripe success names B's Alipay out_trade_no. Verification uses A's Stripe account, but handler lookup has no provider condition and signing_matches_payment resolves the ID under the payment's Alipay provider, accepting B's account. B's payment/order becomes paid without Alipay capture. Shared refund settlement has the same missing incoming-provider binding.
- Fix: carry verified account/provider identity, require matching provider/tenant and scope all target lookups accordingly.
- Specs: `spec/requests/payments/webhooks_stripe_spec.rb`, `spec/services/payments/activities/handle_webhook_spec.rb`. Original refund examples at lines 154–198 use a WeChat payment for Stripe/PayPal events, masking the boundary.

#### F2. A cheaper order completes a different expensive handoff

- Evidence: `app/controllers/payments/checkouts_controller.rb:221–225,322–332`; `app/services/payments/activities/charge.rb:49–59`; `app/services/payments/handoff_completion.rb:71–74`.
- Trigger: materialize an unpaid cheap order, start an expensive invocation in the same tenant/session, POST the cheap reference, pay and open result. The current invocation token is stamped on the arbitrary selected order; completion checks token only.
- Fix: bind invocation/order at charge and completion, verify derived reference and monetary identity; unrelated direct checkout must not acquire the token.
- Specs: `spec/requests/payments/checkouts_spec.rb`, `spec/requests/payments/checkout_collect_spec.rb`, `spec/services/payments/handoff_completion_spec.rb`.

#### F3. Captcha replay manufactures valid CSRF authorization for an invalid original POST

- Evidence: `app/services/captcha/rack_gate.rb:81–85`; `app/services/captcha/request_snapshot.rb:20–29,35–45`; `app/controllers/captcha/challenges_controller.rb:69–80`; `app/services/captcha/request_replayer.rb:18–29,51–58`.
- Trigger: every-hit checkout captures a missing/invalid-CSRF POST before controller validation. A legitimate challenge submission replays it with newly generated authenticity token and challenge session/environment. Original origin/session authorization is not retained; IP/path are the only snapshot binding. Cross-site POST followed by challenge can acquire the victim's session on replay.
- Fix: verify original CSRF/origin/session before replay admission; preserve valid target request evidence instead of supplying authorization to an unverified body.
- Specs: `spec/requests/captcha/url_throttle_gate_spec.rb`, `spec/services/captcha/request_replayer_spec.rb`, `spec/services/captcha/request_snapshot_spec.rb`; enable real CSRF checks.

#### F4. Alipay business errors can retire a still-payable attempt or falsely close/unsign

- Evidence: `app/services/payments/gateways/alipay.rb:74–78,92–95,110–113,224–230`; `app/services/payments/activities/query.rb:31–34`; `app/services/payments/activities/charge.rb:47–48,115–129`.
- Trigger: HTTP-200 query business error lacks trade_status, maps failed, then another same-provider checkout creates a fresh attempt while original QR remains payable. HTTP-200 close error is reported closed, permitting another provider while the original is open. Unsign error likewise records local cancellation.
- Fix: centralized operation-root/business-code validation; errors preserve unresolved state; remote closure/cancellation must succeed before local transition.
- Specs: `spec/services/payments/gateways/alipay_spec.rb`, `spec/services/payments/activities/charge_spec.rb`, `spec/services/payments/activities/query_spec.rb`.

#### F5. Indeterminate writes are classified definitive, changing financial idempotency identity

- Evidence: `app/services/payments/gateways/stripe.rb:358–365`; `app/services/payments/gateways/base.rb:199–207`; `app/services/payments/activities/refund.rb:45–54`; `app/services/payments/activities/charge_token.rb:43–52`; `app/services/payments/cron/charge_due_subscriptions.rb:94–102`.
- Trigger: PSP executes charge/refund but returns 500. ApiError marks row failed, and next request/tick submits a new key. WeChat 500/certain 429 refund errors require original refund number. Unresolved Stripe retries also have no age boundary and can execute again after key retention expires.
- Fix: distinguish definitive rejection from uncertain writes; retain reservation/key and reconcile before another operation or after vendor retention expires.
- Specs: `spec/services/payments/activities/refund_spec.rb`, `spec/services/payments/activities/charge_token_spec.rb`, `spec/services/payments/cron/charge_due_subscriptions_spec.rb`.
- Source: <https://docs.stripe.com/error-low-level>.

#### F6. Account disablement can permanently discard an already-verified settlement

- Evidence: `app/services/payments/credential_resolver.rb:22–30`; `app/services/payments/activities/handle_webhook.rb:185–194`; `app/jobs/payments/process_webhook_event_job.rb:25–34`; `app/controllers/admin/maintenance/platform/payments/webhook_events_controller.rb:28–39`.
- Trigger: valid event is verified/persisted/acked, account disabled before job. Fresh active-account guard rejects settlement, yet job marks processed and owner redrive refuses it. Changing merchant ID similarly prevents old webhook routing and makes historical query/refund use replacement credentials.
- Fix: retain/pin historical verified account identity; disable only new operations; recoverable binding failure must not be processed.
- Specs: `spec/jobs/payments/process_webhook_event_job_spec.rb`, `spec/services/payments/webhook_dispatcher_spec.rb`, `spec/requests/admin/maintenance/platform/payments/webhook_events_spec.rb`.

#### F7. Paused enrollment can duplicate a resumable recurring plan

- Evidence: `app/services/payments/activities/create_subscription.rb:13,23–45`; `app/services/payments/activities/handle_webhook.rb:628–652`.
- Trigger: SCA pauses plan, admin resubmits same card/plan enrollment, duplicate lookup excludes paused and inserts another active plan. Old SCA completion reactivates original; both can bill.
- Fix: deduplicate resumable paused enrollment or explicitly retire it when replacing.
- Specs: `spec/services/payments/activities/create_subscription_spec.rb`, `spec/requests/admin/modules/payments/subscriptions_spec.rb`, `spec/services/payments/activities/handle_webhook_spec.rb`.

#### F8. In-flight dunning/recovery can overwrite cancellation

- Evidence: `app/services/payments/activities/cancel_subscription.rb:6–8`; `app/services/payments/cron/charge_due_subscriptions.rb:23–27`; `app/models/payments/subscription.rb:40–43`; `app/services/payments/activities/handle_webhook.rb:633–652`.
- Trigger: handler reads paused, member cancellation commits cancelled, handler writes active and resumes future billing. Stale cron object can likewise write paused over cancelled.
- Fix: locked/conditional persisted transitions paused→active and active→paused; cancellation is a floor.
- Specs: `spec/requests/member/payments/subscriptions_spec.rb`, `spec/services/payments/activities/cancel_subscription_spec.rb`, `spec/services/payments/cron/charge_due_subscriptions_spec.rb`, `spec/services/payments/activities/handle_webhook_spec.rb`.

### P2 — functional/settlement/enforcement

#### F9. One-time charge rollback loses the PSP operation identity

- Evidence: `app/services/payments/activities/charge.rb:22–33,52–80`.
- Trigger: PSP creates intent/order, transport fails before returning, surrounding order transaction rolls back local Payment/trade number. Retry uses another key and creates an orphan/duplicate remote attempt. This alone does not prove the first unconfirmed object captured money.
- Fix: commit identity before outbound write with aggregate claim/settlement guards.
- Specs: `spec/services/payments/activities/charge_spec.rb`, `spec/requests/payments/checkouts_spec.rb`.

#### F10. Late processing response regresses succeeded refund

- Evidence: `app/models/payments/refund.rb:31–34`; `app/services/payments/activities/refund.rb:56–61`.
- Trigger: webhook commits succeeded while synchronous call waits; processing reply uses stale requested object and overwrites status. Ledger is processed; order can already be refunded.
- Fix: lock/reload or conditional update based on persisted nonterminal status.
- Specs: `spec/models/payments/refund_spec.rb`, `spec/services/payments/activities/refund_spec.rb`.

#### F11. PayPal refund without custom_id cannot route

- Evidence: `app/services/payments/gateways/paypal.rb:73–81,174–184`; `app/services/payments/credential_resolver.rb:22–30`.
- Trigger: pending admin refund later notifies refund/invoice ID without custom_id. Request only sent invoice_id and extraction only falls back to disputes, so 404 occurs before signature verification/settlement.
- Fix: send refund custom_id; route through trusted local refund/invoice/capture linkage.
- Specs: `spec/services/payments/gateways/paypal_spec.rb`, `spec/services/payments/webhook_dispatcher_spec.rb`, `spec/services/payments/activities/handle_webhook_spec.rb`.
- Already documented in `doc/reference/en/payments.md:39`.

#### F12. WeChat bills fail download authentication and native-format reconciliation

- Evidence: `app/services/payments/gateways/wechat_pay.rb:133–137`; `app/services/payments/activities/reconcile.rb:15–16,28–38,49–62`.
- Trigger: real download_url is fetched without APIv3 authorization. Even after successful download, Chinese/backtick native rows, summary footer and payment/refund types do not match expected English fields, producing missing refs/zero totals/false discrepancies.
- Fix: sign exact download path/query; vendor-normalize native records, summary and refund kinds before generic reconciliation.
- Specs: `spec/services/payments/gateways/wechat_pay_spec.rb`, `spec/services/payments/activities/reconcile_spec.rb`, `spec/services/payments/cron/download_bills_spec.rb`.
- Sources: <https://pay.weixin.qq.com/doc/v3/merchant/4012791868>, <https://pay.weixin.qq.com/doc/v3/merchant/4013071246>.

#### F13. Query permanently records poll time rather than settlement date

- Evidence: `app/services/payments/activities/query.rb:22–28`; `app/services/payments/activities/handle_webhook.rb:261,290,537,595`; `app/services/payments/activities/reconcile.rb:35–37`.
- Trigger: yesterday's capture is queried today before delayed webhook. Query stamps today; succeeded guard prevents later timestamp correction. Reverse reconciliation uses wrong date.
- Fix: normalize authoritative provider capture timestamps and reconcile them on delayed notifications.
- Specs: `spec/services/payments/activities/query_spec.rb`, `spec/services/payments/activities/handle_webhook_spec.rb`, `spec/services/payments/activities/reconcile_spec.rb`.

#### F14. Stripe success ignores asserted currency

- Evidence: `app/services/payments/activities/handle_webhook.rb:36–38,595–599`; `app/services/payments/activities/query.rb:25,44`.
- Trigger: USD 10 local payment receives signed JPY amount_received 1000 referencing it. Conversion uses local USD, obtains 10 and settles; PSP currency is not passed to mismatch check. Query has same issue.
- Fix: enforce PSP currency and convert in that currency; bind known PSP intent ID.
- Specs: `spec/services/payments/activities/query_spec.rb`, `spec/services/payments/activities/handle_webhook_spec.rb`, `spec/requests/payments/webhooks_stripe_spec.rb`.

#### F15. Member default-gateway checkout without provider 500s

- Evidence: `app/controllers/payments/checkouts_controller.rb:108,151,274–287`; `app/services/plugin_registry.rb:23–25`.
- Trigger: same-tenant member POSTs valid ref but no provider. Default resolves; save-card capability helper still passes raw nil to registry and nil.to_sym raises unrescued NoMethodError, even without opt-in.
- Fix: use resolved provider consistently.
- Spec: `spec/requests/payments/checkouts_spec.rb`.

#### F16. Save-card checkbox never reaches backend

- Evidence: `app/components/payments/checkout_component.html.erb:11–19`; `app/components/payments/widget_checkout_component.html.erb:43–59`; `app/javascript/controllers/payments/stripe_card_controller.js:116–122`; `app/controllers/payments/checkouts_controller.rb:151,285–287`.
- Trigger: select Stripe, check opt-in after intent creation and pay. Checkbox is not submitted/read; intent already lacked future usage; no vault placeholder is created by advertised UI.
- Fix: collect opt-in before intent or implement server update before confirmation.
- Specs: `spec/requests/payments/checkouts_spec.rb`, `spec/javascript/controllers/payments/stripe_card_controller.test.js`.

#### F17. Save-card retry changes Customer behind same intent key

- Evidence: `app/services/payments/gateways/stripe.rb:123–131,251–257`; `app/services/payments/activities/charge.rb:47–48,70–73`.
- Trigger: same pending checkout twice with save_card creates two Customers and submits same intent key with different customer parameter. Stripe rejects idempotency replay.
- Fix: persist/reuse Customer and frozen request context/existing intent.
- Specs: `spec/services/payments/gateways/stripe_spec.rb`, `spec/services/payments/activities/charge_spec.rb`.

#### F18. Retry renders new flow using old payload

- Evidence: `app/services/payments/activities/charge.rb:46–48,70–81`; `app/models/payments/payment.rb:47–49`; `app/components/payments/h5_redirect_component.rb:9–12`.
- Trigger: desktop QR then mobile H5 retry same provider/order reuses pending Payment. New flow is returned but mark_pending skips payload update; H5 reads nil h5_url from QR payload.
- Fix: freeze flow or supported synchronized transition.
- Specs: `spec/services/payments/activities/charge_spec.rb`, `spec/requests/payments/checkouts_spec.rb`.

#### F19. Missing subscription currency creates unchargeable record/batch failure

- Evidence: `app/services/payments/contracts/subscribe.rb:16–26`; `app/services/payments/activities/create_subscription.rb:16,50–58`; `app/models/payments/subscription.rb:17–23`; `app/services/payments/cron/charge_due_subscriptions.rb:162–165`.
- Trigger: omit currency with otherwise valid enrollment. Contract skips check, activity stores empty string, model accepts. Due order create raises RecordInvalid outside Payments-error rescue and aborts batch.
- Fix: required supported currency in contract/model; 422 before enrollment.
- Specs: `spec/services/payments/contracts/subscribe_spec.rb`, `spec/requests/admin/modules/payments/subscriptions_spec.rb`, `spec/services/payments/cron/charge_due_subscriptions_spec.rb`.

#### F20. Positive sub-minor-unit handoff amount 500s at persistence

- Evidence: `app/services/feature_modules/payment/registration.rb:21–22`; `app/controllers/payments/checkouts_controller.rb:85–94,298–309`; `app/models/concerns/payments/normalizes_amount.rb:9–14`; `app/models/payments/order.rb:24`.
- Trigger: CNY 0.004 passes input contract but Order rounds to zero and find_or_create_by! raises uncaught RecordInvalid.
- Fix: finite/currency-aware positive-after-normalization contract and controlled validation response.
- Specs: `spec/requests/payments/checkout_collect_spec.rb`, `spec/services/feature_modules/payment/registration_spec.rb`, `spec/services/payments/money_spec.rb`.

#### F21. Public payment URLs reject a signed-in other-tenant shopper

- Evidence: `app/controllers/concerns/tenant_context.rb:156–159,198–201`.
- Trigger: A member/admin opens B's valid public checkout/result/status; rejected before public action, although anonymous works. Contradicts AGENTS public category.
- Fix: scope actor restrictions to protected resources; keep public URL tenant isolation and same-tenant saved-card attribution.
- Specs: `spec/requests/payments/checkouts_spec.rb`, `spec/requests/payments/results_spec.rb`.

#### F22. Optional formats bypass captcha

- Evidence: `app/services/captcha/rack_gate.rb:28–33`; `app/services/captcha/url_matcher.rb:34–39`; `app/services/captcha/path_template.rb:14–17`; `config/routes.rb:221–222`.
- Trigger: every-hit checkout accessed/posted as checkout.html routes normally but literal formatted path does not match formatless throttle.
- Fix: router-canonical endpoint/format matching while retaining original return/replay path.
- Specs: `spec/services/captcha/url_matcher_spec.rb`, `spec/requests/captcha/surface_enforcement_spec.rb`, `spec/requests/payments/checkouts_spec.rb`.

#### F23. Live challenge ignores platform failure policy

- Evidence: `app/controllers/captcha/challenges_controller.rb:26–42`; `app/services/captcha/activities/verify.rb:85–87`; `config/locales/captcha.en.yml:62–66`.
- Trigger: save fail_policy closed, challenged checkout POST gets unreachable/configuration_error; catalog fail_closed false causes replay because result.fail_policy is unused.
- Fix: resolve platform policy with explicit surface overrides at live decision point.
- Specs: `spec/requests/captcha/url_throttle_gate_spec.rb`, `spec/services/captcha/activities/verify_spec.rb`, `spec/requests/admin/maintenance/platform/captcha/settings_spec.rb`.

#### F24. Fail-open GET loops on vendor outage

- Evidence: `app/controllers/captcha/challenges_controller.rb:39–42,85–86`; `app/services/captcha/rack_gate.rb:37–45`.
- Trigger: over-limit GET accepts vendor outage without Grant, redirects back, and immediately re-challenges. POST has one-request replay exemption, GET does not.
- Fix: narrow one-use request-bound passage, not normal long-lived success grant.
- Specs: `spec/requests/captcha/url_throttle_gate_spec.rb`, `spec/services/captcha/rack_gate_spec.rb`.

#### F25. Aliyun browser API does not match official SDK

- Evidence: `app/javascript/controllers/captcha_aliyun_controller.js:14–33,36–39`; `app/services/captcha/providers/aliyun.rb:33–38,47–55`.
- Trigger: genuine SDK exposes initAliyunCaptcha and requires pre-load region/prefix, selector/button/getInstance; app waits for AliyunCaptcha and calls init, lacks required prefix field, and returns success before server verification.
- Fix: official SDK contract and actual verification outcome propagation.
- Specs: `spec/javascript/controllers/captcha_aliyun_controller.test.js`, `spec/services/captcha/providers/aliyun_spec.rb`; current fabricated init global masks issue.
- Source: <https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/client-access>; documented in `doc/reference/en/captcha.md:19`.

#### F26. Wrong-host/action successful captcha token is accepted

- Evidence: `app/services/captcha/providers/google_recaptcha_v3.rb:66–73,83–87`; `app/services/captcha/providers/turnstile.rb:67–74`; `app/services/captcha/activities/verify.rb:47–53`; `app/services/captcha/verification_context.rb:15–22`.
- Trigger: valid Siteverify success belongs to another key-approved hostname/action; supplied current context is ignored and target grant is issued.
- Fix: enforce hostname and expected SDK action; align submit with logical verification action.
- Specs: `spec/services/captcha/providers/google_recaptcha_v3_spec.rb`, `spec/services/captcha/providers/turnstile_spec.rb`, `spec/services/captcha/activities/verify_spec.rb`.

#### F27. Accepted malformed configuration escapes module error taxonomy

- Evidence: `app/services/captcha/contracts/provider_settings.rb:37–46`; `app/services/captcha/providers/aliyun.rb:84–85`; `app/services/captcha/providers/base.rb:79–94`; `app/services/outbound_http.rb:238–241`; `app/services/payments/gateways/alipay.rb:209–210`; `app/services/payments/gateways/wechat_pay.rb:322–323`.
- Trigger: nonblank Aliyun endpoint bad host saves/activates, then verify/probe raises raw InvalidRequestError and 500 even under fail-open. Nonblank invalid payment PEM passes eligibility and raises raw OpenSSL error during checkout.
- Fix: format/readiness validation and controlled module configuration errors without secret leakage.
- Specs: `spec/services/captcha/contracts/provider_settings_spec.rb`, `spec/services/captcha/activities/test_connection_spec.rb`, `spec/requests/admin/settings/modules/payments/merchant_accounts_spec.rb`, `spec/requests/payments/checkouts_spec.rb`.

#### F28. Captcha rejects payment-compatible old webviews

- Evidence: `app/controllers/application_controller.rb:17–18`; `app/controllers/payments/checkouts_controller.rb:335–339`; `app/controllers/payments/results_controller.rb:82–84`; `app/controllers/captcha/challenges_controller.rb:6–10`.
- Trigger: Alipay browser admitted by payment override hits throttle; challenge inherits modern-browser gate and responds 406.
- Fix: compatible interstitial browser policy.
- Specs: `spec/requests/payments/checkouts_spec.rb`, `spec/requests/payments/results_spec.rb`, `spec/requests/captcha/url_throttle_gate_spec.rb`.

### P3 — boundary/navigation

#### F29. JSON null/array causes webhook 500

- Evidence: `app/services/payments/gateways/stripe.rb:70–78`, `paypal.rb:73–83`, `wechat_pay.rb:44–49`; `app/controllers/payments/webhooks_controller.rb:16–22`.
- Trigger: valid JSON wrong envelope shape parses then raises raw Ruby TypeError/NoMethodError during extraction.
- Fix: controlled shape/parse rejection before routing, returning 400 through SignatureInvalid.
- Specs: `spec/requests/payments/webhooks_spec.rb`, gateway specs for Stripe/PayPal/WeChat.

#### F30. Foreign-vendor credential is assigned as an unknown column

- Evidence: `app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb:183–201`.
- Trigger: PATCH Stripe with api_key_v3; union permits it, Stripe split leaves it in shared columns and UnknownAttributeError follows.
- Fix: separately slice shared and selected-vendor keys.
- Spec: `spec/requests/admin/settings/modules/payments/merchant_accounts_spec.rb`.

#### F31. Missing invocation redirects to unroutable tenant root

- Evidence: `app/controllers/payments/checkouts_controller.rb:230–235`; `config/routes.rb:188–225,852–858`.
- Trigger: no invocation and no published tenant home/root shortcut; start/collect/complete redirects /cid, then 404 because no ordinary route/shortcut exists.
- Fix: existing public fallback or resolve a published landing first.
- Specs: `spec/requests/payments/checkout_start_spec.rb`, `spec/requests/payments/checkout_collect_spec.rb`; follow redirects, not only assert location.

## 4. Effective database constraints

Evidence: `db/schema.rb:295–327,901–1081,1418–1427`.

| Resource | Identity/relationship constraints |
| --- | --- |
| MerchantAccount | Unique tenant/provider/mode and provider/merchant ID; customer FK |
| Order | Unique tenant/external_ref; customer FK |
| Payment | Unique out_trade_no; order/customer/user FKs; PSP transaction index not unique |
| Refund | Unique out_refund_no; payment/customer FKs; PSP refund ID not unique |
| Subscription | Unique tenant/external_ref; unique non-null provider/agreement; payment-method/customer FKs |
| PaymentMethod | Unique provider/PSP method ID, tenant/user index; no customer/user FKs |
| Dispute | Unique provider/dispute ID; no payment/customer FKs |
| WebhookEvent | Unique provider/event ID |
| DefaultGateway / PlatformGateway | Unique customer / provider respectively |
| Captcha ProviderSettings | Unique provider, partial unique enabled index |
| Captcha UrlThrottle | Unique match_kind/url_pattern |

Money is major-unit decimal, normalized to zero/two decimals for currently supported currencies. No DB checks enforce positive payment amounts, currency/status enums, matching related customer IDs or card-plan enrollment uniqueness. Controller scopes protect ordinary record access but do not replace those relational invariants. Aggregate with_lock usage exists; SQLite production and method-call/sequential specs do not prove real concurrent serialization.

## 5. Gaps and limitations (not additional exploit claims)

1. Specs often mock activity/dispatcher or simulate overlap sequentially. Real bill wire formats, callback races, CSRF-enabled replay, paused re-enrollment and cancellation interleavings need integration coverage.
2. Primary/queue are separate SQLite databases (`config/database.yml:35–46`). Solid Queue adapter defers enqueue until commit. Dispatcher/docs atomic insert+enqueue claim is false; hourly reaper provides eventual recovery of committed received rows stranded before enqueue. References: `app/services/payments/webhook_dispatcher.rb:24–29`, `doc/reference/en/payments.md:135`.
3. Platform owner gate checks actor, not URL CID 81721200. Owner can mutate global settings beneath another CID; no ordinary-admin escalation, but AGENTS location constraint is not enforced.
4. One-file gateway extension guarantee is incomplete: `HandleWebhook:156–168` hard-codes providers; reconciliation also fixes provider whitelist. Registry-only discovery does not create full webhook behavior.
5. WeChat refund request omits notify_url; separate merchant-platform callback configuration is necessary. No automated refund-query recovery job. This is documented external configuration dependency.
6. Scheduled jobs do not query/expire pending one-time payments or approved PayPal orders. Browser approval abandonment can leave unresolved order; comments implying query cron overstate implementation.
7. OutTradeNo includes predictable customer/time and six lowercased alphanumerics (roughly 30 random bits), not a conventional high-entropy bearer secret. No dedicated status/result limiter.
8. Snapshot orphan-prune method is not scheduled. Per-file cap does not cap aggregate file count/size; uploaded-file nesting handling is limited.
9. Surface discovery can expose captcha/challenges although UrlMatcher always hard-skips it; such throttle saves cannot enforce protection.
10. Captcha active selection permits unconfigured provider and deliberately fails open; invalid sentinel probe does not prove scene/site-key/browser integration. Alipay/WeChat assumed-success probes do not verify merchant connectivity.
11. Hand-written Alipay/WeChat API responses are trusted through TLS without response-signature verification. WeChat bill hash was not checked. No transport-compromise exploit was asserted.

## 6. Sources and remediation documentation requirements

- Stripe: <https://docs.stripe.com/error-low-level>, <https://docs.stripe.com/api/customers/create>.
- PayPal refund fields/linkage: <https://developer.paypal.com/api/payments/v2/captures-refund/>.
- WeChat refund retry/callback contract: <https://pay.weixin.qq.com/doc/v3/merchant/4012791862>.
- WeChat bill signing/native columns: <https://pay.weixin.qq.com/doc/v3/merchant/4012791868>, <https://pay.weixin.qq.com/doc/v3/merchant/4013071246>.
- Aliyun browser V2: <https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/client-access>.

Remediation must synchronize `doc/reference/en/payments.md` and `doc/reference/zh-CN/payments.md`; captcha changes similarly require both captcha pages. Keep locale sections/examples/callouts aligned and all user-facing wording I18n. The gateway-only implementer was explicitly assigned this new audit file only, with reference-doc updates reserved for the integrating owner.

## 7. Gateway-only implementation handoff (subsequent work)

This supplemental section describes the scoped implementation, not an executed verification of the original findings or concurrent agents' changes. Tests were written but not run; Ruby syntax checking is the only authorized execution check.

- Alipay centrally requires operation business root/code, handles common error_response, raises ApiError for definitive business errors and TransportError for missing/malformed response, 20000, 10003 and isp errors. Unknown/missing query states never become failed. Root validation also protects bill/cancellation calls.
- Base maps malformed HTTP-success JSON to uncertain TransportError, POST 5xx/409/429 to TransportError, bad URL/RSA configuration to CredentialsMissing and bad notification shapes/signatures to SignatureInvalid. It uses JSON/OpenSSL/Faraday, not new hand-written protocol libraries.
- Stripe retains official gem verification/transport, retrieves an existing one-time intent, keys immutable checkout Customer creation by trade number, returns/preserves psp_customer_id and save_card in prepay payload, and keeps financial 5xx/transient 429/409/retry-directed errors uncertain. Activity must commit/freeze identity before outbound writes and bound retries to vendor retention; gateway changes cannot establish DB claim/TTL policy.
- Query keeps existing status/psp_transaction_id/raw and adds amount (major-unit BigDecimal), currency (upper-case), settled_at (Time or nil). Alipay uses send_pay_date in Asia/Shanghai; WeChat success_time; Stripe retrieves an unexpanded latest Charge if needed, never uses intent.created; PayPal uses nested capture amount/currency/create_time. Activity must enforce assertions and use the authoritative time.
- PayPal sends refund custom_id and routes older/early notifications using provider-scoped local refund number/PSP refund ID, supplementary capture ID or rel=up capture linkage. Unverified links are never fetched. Binding remains the activity's responsibility.
- WeChat signs exact bill download URI, restricts signed download to vendor HTTPS origins, checks supplied SHA1, retains raw csv and adds rows from the native parser plus bill_summary metadata. Rows have string keys: kind, out_trade_no, psp_transaction_id, amount, currency, status, settled_at, out_refund_no, psp_refund_id and raw. Kinds payment/refund/reversal are not interchangeable. Refund bill status is acceptance-time snapshot; reconciliation must compare refunds as refunds, not payments or webhook-equivalent settlement.
- CredentialResolver.call still requires active credentials for new operations. by_merchant_id resolves disabled rows for verification. New for_payment(customer:, payment:) resolves the pinned attempt account and rejects tenant/merchant-ID/mode drift; facade/activity query/refund/close must opt into it. Notification handlers must likewise accept historical disabled identity while enforcing provider/tenant binding.
- Integration remains responsible for activity/controller/model/captcha fixes, refund-kind reconciliation, account pinning at facade call sites, retry-age bounds and both reference locales. Billing Collector/providers were not changed by the gateway implementer.
