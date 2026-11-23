# Billing UX: focused improvements to existing surfaces

Date: 2026-10-11

Role: `.cursor/agents/anysys-ux-designer.md`

Deliverable: design and frontend task brief; implementation dependencies are explicitly identified.

## 1. Design basis and references

Read `AGENTS.md`, the UX-designer agent, `.cursor/rules/core-conventions.mdc`, and `.cursor/rules/viewcomponent-frontend.mdc`. Inspected billing ViewComponents, their mounting views, controllers, routes, models, Activities, Reform contracts, schema, collector/dunning/renewal behavior, payment gateways, webhook settlement, and existing Stripe Stimulus integration.

The shadcn skill/MCP is unavailable in this harness. **Before design**, consulted these official pages with `webfetch` on 2026-10-11:

| Reference | Pattern adopted | Project delivery |
|---|---|---|
| https://ui.shadcn.com/docs/components/card | Header/title/description, content, and action/footer separation | Existing `Admin::Settings::SectionComponent`, billing cards, and `Admin::CardTableComponent`; project spacing and tokens |
| https://ui.shadcn.com/docs/components/table | Semantic headings, caption, right-aligned amounts, responsive containment | Existing invoice/subscription tables and mobile rows; Rails GET filtering and pagination |
| https://ui.shadcn.com/docs/components/alert | Attention callout with description and nearby contextual action; distinct destructive state | Existing `AlertComponent` plus sibling Rails links/forms in a labelled region |

These are composition references. Delivery uses Rails ViewComponent, Tailwind, native HTML forms/details, and existing Stimulus. The current `AlertComponent` accepts `message:`, `type:`, and `auto_dismiss:`; it does not have shadcn-style title/action slots. Put a heading and actions in the enclosing billing component rather than inventing slots.

## 2. Surface inventory and exact reuse map

Billing is a first-class platform/admin feature, **not** a `FeatureModules` registration. Use the existing Settings and Maintenance / Platform / Billing navigation. Both are `admin` URL surfaces; the latter is platform-owner-only. There is no billing module toggle or member billing screen to add.

In the table below, component basenames resolve under `app/components/billing/admin/`; each named component has both `.rb` and `.html.erb` files.

| Surface and starting URL | Actual mount chain | Focused improvement |
|---|---|---|
| Settings / Plan: `/:cid/admin/settings/billing/subscription` | `app/views/admin/settings/billing/subscriptions/show.html.erb` → `Admin::Settings::PageComponent` → `PlanComparisonComponent(customer_settings: true)` → `CustomerSubscriptionComponent` → `Admin::Settings::SectionComponent`, `BadgeComponent` | Stored-currency summary/comparison, honest cadence eligibility, server-rendered plan review, pending request, coupon benefit, recovery and dated cancellation |
| Settings / Payment methods: `/:cid/admin/settings/billing/payment_methods` | `app/views/admin/settings/billing/payment_methods/index.html.erb` → `Admin::Settings::PageComponent` → `PaymentMethodComponent(customer_settings: true)` → `CustomerPaymentMethodsComponent` → `PaymentAuthorizationComponent` | Active plus pending/failed/removed rows; charge readiness separate from local status; eligible provider setup, Alipay handoff, conditional Stripe form |
| Settings / Invoices: `/:cid/admin/settings/billing/invoices` | `app/views/admin/settings/billing/invoices/index.html.erb` → `Admin::Settings::PageComponent` → `InvoiceTableComponent(context: :settings, customer_settings: true)` | GET search/filter, real pagination, collection status on desktop and mobile |
| Settings / Invoice: `/:cid/admin/settings/billing/invoices/:id` and `.../:id/download` | `app/views/admin/settings/billing/invoices/{show,download}.html.erb` → `InvoiceDetailComponent(platform: false, customer_settings: true)` | Collection detail, eligible retry, payment-method link, conditional existing Stripe authentication form; print/download retains document layout |
| Platform / Subscriptions: `/81721200/admin/maintenance/platform/billing/subscriptions` | `app/views/admin/maintenance/platform/billing/subscriptions/index.html.erb` → `AdminPageComponent`, `PlatformBillingNavComponent`, `SubscriptionsTableComponent`, `Admin::CardTableComponent` | GET search/filter, pagination, cancellation/pending indicators; clear immediate-cancel meaning |
| Platform / Subscription: `.../subscriptions/:id` | `app/views/admin/maintenance/platform/billing/subscriptions/show.html.erb` → `SubscriptionSummaryComponent(show_actions: false)`, `InvoiceTableComponent(context: :platform)` | Correct dates, customer identity, coupon benefit, pending request, paginated invoice history, contextual forced-cancel form |
| Platform / Invoices: `.../invoices` and `.../invoices/:id` | `app/views/admin/maintenance/platform/billing/invoices/{index,show}.html.erb` → `AdminPageComponent`; index adds `PlatformBillingNavComponent`; `InvoiceTableComponent` / `InvoiceDetailComponent(platform: true)` | Same collection/history presentation, state-valid operator actions and truthful outcomes |
| Platform / Plan new/edit: `.../plans/new`, `.../plans/:id/edit` | `app/views/admin/maintenance/platform/billing/plans/{new,edit}.html.erb` → `PlanFormComponent` | Preserve failed input and show Reform errors at relevant fields; describe price snapshot effects |
| Platform / Coupon new/edit: `.../coupons/new`, `.../coupons/:id/edit` | `app/views/admin/maintenance/platform/billing/coupons/{new,edit}.html.erb` → `CouponFormComponent`; catalog uses `CouponTableComponent` | Preserve failed input, correct fixed-currency/duration guidance, distinguish enabled from redeemable |
| Platform / Settings show/edit: `.../settings`, `.../settings/edit` | `app/views/admin/maintenance/platform/billing/settings/{show,edit}.html.erb` → `SettingsFormComponent` | Preserve failed input and explain actual collection-provider selection |

Shared reuse: `Admin::Settings::PageComponent`, `Admin::Settings::SectionComponent`, `AdminPageComponent`, `Admin::CardTableComponent`, `Admin::PaginationComponent`, `BadgeComponent`, and `AlertComponent`. **No new ViewComponent class is required.** Encapsulate added markup in the named billing components; mounting views only pass data. A list footer reuses `Admin::PaginationComponent(pagination:, page_path:)` with `{ page:, per_page:, total:, total_pages: }`.

## 3. Evidence: current behavior versus required presentation

| Inspected source | Current behavior | UX consequence / required server work |
|---|---|---|
| `app/controllers/admin/settings/billing/subscriptions_controller.rb`, `app/services/billing/currency_resolver.rb` | `assign_show` gets only a live subscription and derives comparison currency from customer/request locale | Existing subscription prices must use its stored `currency`; fetch latest ended subscription separately for historical context |
| `app/models/billing/plan.rb`, `app/models/billing/subscription.rb` | Catalog has decimal `amount_usd`/`amount_cny`; subscription snapshots integer `amount_cents`, `currency`, `interval`; `free?` checks both catalog currencies | Show stored current price independently from current catalog price. Determine zero-priced choice using the displayed currency's price, not global `free?` |
| `app/services/billing/contracts/change_plan.rb` | Rejects a live change to a different `interval` | Monthly/yearly are actual plan records selected by `plan_code`; initial subscription can choose either, live switch stays same cadence. Explain compare-only choices before submission |
| `app/services/billing/activities/change_plan.rb`, `app/services/billing/proration.rb` | Proration invoice generated now; new plan applied only when invoice paid, result `:succeeded`, or `:pending_manual`; period anchors are retained | Do not describe every click as immediately paid or scheduled for next renewal. Review uses server math and conditional effective wording |
| `db/schema.rb`, `app/services/payments/activities/handle_webhook.rb` | No persisted target-plan/effective-date/request link for an uncollected change. Webhook settles an open billing invoice but does not complete the requested plan change | A durable pending-change presentation and eventual application require backend work. Never reconstruct target identity from translated line-item descriptions or a flash |
| `app/services/billing/activities/finalize_invoice.rb`, `app/services/billing/activities/apply_coupon.rb` | At most one attached coupon; discounts depend on usability/currency and count of prior non-draft invoices, including void invoices | Attached code is not proof of future benefit. Explain next-invoice eligibility and remaining invoice allowance, including prorations |
| `app/controllers/admin/settings/billing/payment_methods_controller.rb` | Index queries `.active`; default/removal lookup also queries `.active` | Load all statuses for display. Pending/failed/removed rows currently cannot be defaulted or removed; do not render those existing actions for them |
| `app/services/billing/available_providers.rb`, `app/services/billing/contracts/payment_method.rb` | Platform-owner account must be active/configured in current credential mode and gateway must have `:recurring` + `:billing_agreements`; no currency filter | Add currency-aware setup eligibility. Stripe is deliberately excluded by the current agreement-capability predicate; registered/configured is insufficient to advertise billing setup |
| `app/services/billing/activities/set_up_payment_method.rb` | Calls `Payments::Gateway.subscribe` but discards its result; activates only if mandate already active. Fallback external reference is tenant-only, not provider-specific. Mandate creation does not explicitly set billing currency | Preserve usable handoff data; isolate mandates by tenant/provider; use actual stored billing currency for mandate amount/currency. A sign request alone is not authorization |
| `app/services/payments/gateways/alipay.rb` | `subscribe` returns `sign_url_or_params`; default supported currency is CNY | Alipay is a CNY-compatible authorization handoff only when backend can provide a validated usable redirect/form. Do not treat the returned sign string as necessarily an HTTP URL |
| `app/services/payments/gateways/stripe.rb`, `app/javascript/controllers/payments/stripe_card_controller.js` | Stripe provides SetupIntent/tokenized-card APIs and recurring charges; existing controller has PaymentIntent and vault modes | Reuse controller where supported, but billing needs its own admin endpoints and mandate/token association; member vault routes are not billing routes |
| `app/services/billing/collector.rb`, `app/services/billing/activities/collect_invoice.rb` | Runtime collection mode comes from current settings, not invoice snapshot; failures increment `attempt_count`; pending/manual leave invoice open; existing pending capture is reused | Separate invoice status from collection state. Label attempt count as failed attempts, not all payment attempts. Pending does not mean failure or paid |
| Tenant/platform invoice indexes and platform subscription index | `.limit(100)`; no search or pagination parameters; platform subscription detail invoice list unbounded | Implement server-side filtering/counting/pagination, including detail histories; a 100-row cap is not pagination |
| `app/services/billing/activities/mark_invoice_paid.rb`, `resume_subscription.rb`, `app/services/billing/cron/dunning.rb` | Paying an invoice does not restore Billing subscription status; resume can activate paused without debt validation; exhausted invoice becomes uncollectible/past_due | Do not promise recovery from changing a method or paying one invoice. Server must supply recovery eligibility; uncollectible needs operator resolution under current rules |
| Platform invoice/cancellation controllers; `app/services/billing/activities/void_invoice.rb` | Retry emits generic notice even on failure/manual/pending. Void refuses created/pending/succeeded payments. Immediate cancel changes subscription before best-effort voids; no live-state precondition in controller | Validate actions before side effects and return outcome-specific messages. Forced cancel cannot claim every invoice was voided if one could not be |
| Platform plan/coupon/settings controllers and form components | Controllers assign `@contract` on 422; views pass only model; components show model errors/values | Pass the failing Reform contract to existing components. A 422 without retained input or visible contract errors is not usable validation |

## 4. Presentation contracts for the existing components

The following are **proposed server-to-component props**, not existing database columns. Components format/translate supplied facts; Activities/contracts remain responsible for business decisions. Forward new props through the two wrapper components, not just the customer subclass.

| Prop / consumer | Required content and source |
|---|---|
| `current_subscription:` / customer plan | Live row remains the mutation target. `latest_subscription:` is separate read-only ended history when no live row exists; never use it to decide ChangePlan versus Subscribe |
| `currency:` / plan and method wrappers | Live `Billing::Subscription#currency`, otherwise `CurrencyResolver.for_customer`. Unsupported/blank legacy currency is a visible unavailable state, never silently relabel a USD price as another currency |
| `plan_review:` / customer plan | Active target record selected by GET `review_plan_code`; server-calculated credit, charge, discount, tax, estimated total, calculation time, actual interval and effective condition. Preview is read-only and recomputed at PATCH |
| `pending_change:` / customer plan and platform summary | Durable request identity, requested plan/code, target amount/currency/interval snapshot, requested time, linked invoice ID, request state, effective condition, confirmed effective time if applied, retry eligibility. An open invoice by itself does not establish this contract |
| `coupon_benefit:` / customer plan and platform summary | Attached code/name, percent or fixed amount in applicable currency, eligibility state, allowance remaining for future invoices, duration, expiry, and reason. Server uses the same rules as FinalizeInvoice |
| `recovery:` / customer plan | Actual subscription state, outstanding invoice links, optional grace deadline, `can_resume`, and recovery instruction key. Grace deadline = `past_due_at + current grace_period_days`; describe it as current policy, not a guaranteed execution timestamp |
| `provider_options:` / method wrappers and authorization | For each provider: key, localized display-name key, configured/current-mode status, currency compatibility, supported billing setup flow, enabled/disabled state, reason key. Do not pass credentials. `available_providers:` remains the eligible key set for existing forms |
| `payment_method_readiness:` / customer methods | Map keyed by Billing method ID: active local row, linked mandate status, verified agreement/chargeable token, current account availability, currency compatibility, default eligibility, and reason key |
| `authorization:` / authorization component | Conditional validated Alipay redirect/form descriptor, or Stripe publishable key and billing setup/create URLs. Raw sign strings/client-supplied provider URLs are not rendering contracts |
| `collection:` or `collection_by_invoice_id:` / detail/list | Effective current mode, recorded invoice mode, canonical collection state, failed attempts, next retry if meaningful, latest relevant payment state, allowed actions and reason keys. Resolve platform-owned payment order by `customer_id: 81721200`, `external_ref: "billing-inv-#{invoice.id}"`, after authorizing invoice access |
| `payment_recovery:` / tenant invoice detail | Only when the associated platform-owned Stripe payment `requires_action?`: publishable key from its account/mode, `recovery_client_secret`, and result URL back to this invoice. Do not expose another tenant's secret or render it in print/download |
| `filters:`, `pagination:` / tables | Validated GET filter values, scoped page of records, totals and same-scope page-path callable. Stable order `created_at DESC, id DESC` |
| `contract:` / plan/coupon/settings forms | Optional failing Reform form; use its submitted values/errors on 422, original record only for persistence identity/routes. Retain raw invalid dunning text and limits map alongside it |

## 5. Layout specification

### A. Tenant plan, current state and pending changes

Keep the existing section order and Settings page shell. Add compact facts and callouts, rather than another dashboard.

```text
Current subscription
  Plan name     [actual subscription status] [cancellation scheduled, if set]
  Stored subscription price + ISO currency + actual cadence
  Current period start/end        Trial end / renewal / cancellation / ended date
  [Recovery message + invoice/payment-method links, when needed]
  [Pending request: target plan, target price/cadence, linked invoice, effective condition]

Compare plans
  Currency/cadence guidance
  Existing comparison table: billed price, monthly equivalent, trial, limits, action
  [Inline server-rendered review of selected eligible plan]

Coupon
  [Attached benefit summary and eligibility] OR existing code-entry form

Manage subscription
  Dated cancellation explanation + Cancel Subscription / Keep subscription / Resume
```

Data rules:

1. Current amount is `subscription.amount_cents`, not today's `plan.amount_*`. Append the ISO currency to remove ambiguous `$`/`¥` interpretation. Comparison uses `plan.price_cents_for(subscription.currency)` for a live row. Locale changes affect wording/date formatting, not billing denomination.
2. Only USD/CNY are priced by this catalog. Do not use `Plan#amount_for`'s USD fallback to invent a EUR/HKD price. For a currency outside the catalog, show current snapshot and an explanatory unavailable comparison/action state.
3. New subscription choices expose both monthly/yearly records. On a live row, retain other-cadence columns as compare-only with a disabled action and `cadence_restriction`. Same-plan disables only for the live current plan; a cancelled/expired plan is selectable again via Subscribe. Never submit a free-standing `interval`, price, currency or effective date.
4. Terminal status takes precedence over a leftover cancellation flag: cancelled/expired → `ended_at` in the latest-history strip, never a future scheduled-cancellation label. For live rows: scheduled cancellation → `current_period_end`; otherwise trialing → `trial_end`; active → renewal at `current_period_end`; paused/past_due → period end, not a confirmed renewal. Also show the actual period range. Missing date uses `common.labels.em_dash`, not a computed invented date. Show cancellation timestamp with localized time/zone when available.
5. Target review is a compact block inside Compare plans, reached by GET. Show billed target price, cadence, estimated proration total and calculation timestamp. Do not run FinalizeInvoice for preview: it writes/consumes invoices. Backend supplies a side-effect-free calculation consistent with Proration, discount, tax and zero-total clamp.
6. For live ChangePlan, paid/zero-total changes take effect after server completion, gateway-pending changes await collection, and manual-mode changes currently take effect on accepted request while invoice remains unpaid. For Subscribe, current behavior is different: a non-trial subscription starts active at `started_at` even if its first collection is pending/failed; a trial starts trialing with `trial_end` and no immediate invoice. Show that persisted subscription state and its separate invoice state, not a pending plan-change claim. There is no scheduled next-period plan-change capability. No future-date picker or claim that downgrades refund unused credit; negative net total is clamped to zero in invoice totals.
7. Trial days are available for a newly created subscription, not automatically granted on a live switch. A trial switch currently can generate a proration invoice before trial end; disclose this in review instead of advertising a renewed trial.
8. Pending card uses durable request facts and an invoice link. In-flight: informational badge and refresh/view link. Failed: warning with method/invoice actions. Do not offer another switch that can create a second unresolved proration invoice; resolve/retry the original request. Once applied, current snapshot and confirmed effective time replace the waiting message. No pending-request cancellation endpoint exists.

Primary action is the existing final Subscribe/Switch submit in the inline review. Secondary actions are Back to comparison/View invoice. Cancellation stays in Manage subscription. Loading uses Rails/Turbo submission feedback; the server's response decides whether the plan changed. On invalid target/state, render this page with status 422, preserve the chosen code, display an error summary and adjacent explanation. A request with no durable pending data must not display a fictitious target/effective date.

### B. Coupon benefit status

Keep code entry in the existing Coupon section. For no-live/new signup, place optional coupon input in the Subscribe review using the already-permitted `billing_subscription[coupon_code]`. Live coupon entry retains the existing redemption form. When attached, replace entry with a read-only benefit summary; a second/replacement coupon is not supported.

Show code/name, discount (`%{percent}% off` or formatted fixed amount in subscription currency), duration, eligibility for the **next newly finalized invoice**, and allowance remaining. Use a status badge plus reason text, not just the code.

Eligibility derives from `usable_on_invoice?`, `applies_to_currency?`, and duration rules. For a future invoice, prior count is all current non-draft invoices for the subscription. Once has `max(1 - count, 0)` allowance; repeating has `max(duration_in_cycles - count, 0)`; forever has no count limit but still requires usability/currency. Proration, void, paid and uncollectible invoices count; drafts do not. Call this invoice allowance rather than calendar months. Global `times_redeemed` controls new redemptions, not an attached coupon's remaining benefit. A repeating code attached later does not reset the prior invoice count.

Expired/disabled/exhausted/mismatched coupons stay visibly attached with their reason and no misleading Apply button. Benefit summary states that applying a code does not reprice already-issued invoices; final discount is in the finalized invoice lines/totals. Zero subtotal can yield no discount even when eligible. Do not use invoice `billing_coupon_id` as proof of a historical discount: current invoice generation/finalization does not populate that snapshot; use persisted discount lines/amounts.

Error behavior: reuse current not-found/not-redeemable/currency/once-elapsed/already-applied messages. Improve the POST failure rendering to retain `coupon_redemption[coupon_code]` and the Coupon section's field error at 422; successful POST redirects back. Reapplying the same code remains idempotent. No asynchronous coupon verification or extra controller is required.

### C. Payment methods and authorization

Retain the two existing Settings sections: Saved billing methods and Payment authorization. Saved section shows active rows first, then a visibly labelled Pending and inactive methods group. Pending and failed rows are visible by default; removed history may be inside native `<details>`. Show every stored row, including when providers become unavailable.

Each row: provider → actual local status badge → default badge if `is_default` → safe account label → authorized date → charge-readiness text → applicable actions. A local `active` badge is not enough: linked mandate may be inactive/incomplete, token unconfirmed, account disabled/unconfigured, or currency incompatible. Keep the factual default badge but add the blocker; do not silently imply the default is usable.

| Method state | Presentation and action |
|---|---|
| Active and charge-ready | Existing Make Default on nondefault row; Remove; contextual warning when removing sole/default charge-ready method |
| Active but blocked | Actual Active badge plus reason; Make Default unavailable until verified ready; Remove still available under current active-row route policy |
| Pending with usable authorization handoff | Pending badge; Continue authorization posts the existing setup form for this provider, allowing server to reuse/reissue the handoff; refresh link after return |
| Pending without usable handoff | Pending badge and setup-unavailable/retry guidance; never fabricate a completion URL or show as authorized |
| Failed | Failed badge and Reauthorize using existing provider setup POST only if currently eligible |
| Removed | Removed badge, historical authorized date if present; new authorization via existing provider POST if eligible; no Make Default/Remove on this historical row |

Do not invent an `inactive` enum: `Billing::PaymentMethod::STATUSES` is pending/active/failed/removed. Blank account data uses an em dash, not generated English such as `" (authorized)"`. Translate provider display names through locale keys; preserve actual masked account data as data.

Authorization options must be active **and** configured for platform customer 81721200/current credential mode, compatible with effective billing currency, and backed by a functioning billing setup path. Show eligible buttons and, if a known option is disabled, a brief reason. Distinguish no configured options from configured-but-currency-incompatible options; the existing `no_providers` message alone is inaccurate for the second case. Do not make tenant admins configure platform credentials.

**Alipay:** existing provider form submits server-side. Backend retains the signing result and responds with a 303 redirect to a validated usable Alipay authorization URL, or an ordinary server-rendered vendor form if that is the normalized result. Use `data-turbo="false"` on external handoff form. `sign_url_or_params` currently may be a signing string; normalization must produce a supported URL/form or fail visibly. After browser return to the method index, method remains Pending until verified provider confirmation updates the mandate and billing row. Current generic payment webhook settlement is not evidence that agreement activation exists; the backend must supply a verified agreement activation path before calling this setup supported.

**Stripe:** put the secure setup panel inside the existing `PaymentAuthorizationComponent`, with project form spacing/buttons. Mount only when configured, currency-compatible and the billing-specific SetupIntent/confirmation contract exists. Reuse `payments--stripe-card` and the existing Stripe loader; raw card fields are vendor iframe fields, not Rails inputs. Reuse its localized error/processing Values. Never mount `Payments::Member::PaymentMethodsComponent` wholesale: its navigation, ownership and merchant accounts are member-scoped, and tenant admins cannot call its routes.

Stripe setup is the unavoidable provider-managed client interaction. Other billing interactions remain normal server forms/links. Existing vault mode initializes lazily on submit and requests an intent again on subsequent submits; it does not guarantee an initialized setup form on arrival or clean redirect completion. Before billing enables this panel, prepare/mount a single resumable intent and confirm it on submit, handle a 3DS return, and bind completion to that same tenant/setup attempt. Prefer a narrowly scoped extension of the **existing** controller if needed; do not add a new controller or inline JS. Do not pass a SetupIntent secret as its PaymentIntent `clientSecret` mode: that mode calls `confirmPayment`, not `confirmSetup`.

Empty/loading/error: truly no rows gets `all_empty`; no ready active row still shows pending/history plus the existing authorized-empty wording. Initialization shows localized Loading/Processing and a labelled inline error region. Vendor failure leaves the previous default intact and renders a localized error/retry. Failed/pending setup never gets the successful authorization flash. Adding a method does not itself settle invoices or resume service. Removal currently best-effort revokes at provider; the result should promise local removal, not confirmed remote revocation.

### D. Invoice collection, retry and searchable histories

Keep list columns Number, Customer (platform), Issued, Due, Total, Status and Actions. Add a compact Collection cell; on mobile add the same labelled datum beneath Status. Add a GET toolbar above the existing table and the shared pagination footer below it. Avoid a second client-side table engine.

Detail retains header, period/due/paid facts, line items and totals. Add one labelled Collection section between header and lines, hidden from the printable document's action area. Show effective mode, recorded mode when different, collection state, failed-attempt count, meaningful next-attempt timestamp and recovery action. `Invoice#attempt_count` increments on failed collection; never label it total gateway attempts. If no persisted reason exists, show a neutral instruction, not a guessed issuer decline or raw exception.

Collection-state precedence supplied by server:

1. Invoice terminal status: paid/void/uncollectible; draft has not been finalized. Terminal states override stale retry timestamps.
2. Relevant succeeded payment on an open invoice: settlement reconciliation needed; do not allow another charge/manual mark-paid that obscures that state.
3. Relevant created/pending payment: processing; when `requires_action?`, authentication required. A stale `next_attempt_at` is not a new-payment invitation.
4. Open invoice in effective manual mode: awaiting manual settlement; no automatic retry CTA, even if recorded invoice mode is gateway.
5. Open gateway invoice with unusable/missing method or mandate: action required with Payment methods link. A recorded next attempt may be shown, but explain collection is blocked.
6. Open gateway invoice with scheduled retry and no in-flight operation: retry scheduled. Otherwise awaiting collection. Next attempt is a schedule, not a guarantee that a charge will succeed.

Tenant retry is a **proposed route**, absent today. Render it only after server exposes `can_retry`: open gateway invoice, authorized tenant, ready compatible method, no created/pending/succeeded capture requiring reconciliation. POST retries the original invoice/order, does not create a new subscription or proration invoice. Result redirects to this invoice with distinct succeeded/pending/failed/skipped outcomes. Pending hides further retry and offers ordinary Refresh/View actions. Automatic dunning may still proceed; backend rechecks under lock.

For a verified Stripe `requires_action?` payment, tenant detail can reuse the existing controller's PaymentIntent mode with `publishableKey`, `clientSecret`, `resultUrl` returning to this invoice, and existing translated Values. The action is Complete payment authentication. It confirms the existing PaymentIntent, not a new invoice charge. Continue to display Processing until the server/webhook reports paid. Operator detail shows authentication-required guidance; customer-facing authentication belongs on the tenant invoice. Download never includes secrets, recovery widgets or mutation actions.

Histories use the following **proposed GET parameters** on existing read routes:

| History | Exact fields | Search semantics |
|---|---|---|
| Tenant invoices | `q`, `status`, `page` | Literal case-insensitive invoice-number substring; allowlisted invoice status |
| Platform invoices | `q`, `status`, `tenant_id`, `page` | Number substring plus optional exact target customer ID |
| Platform subscriptions | `q`, `status`, `tenant_id`, `page` | Plan name/code substring plus optional exact target customer ID |
| Platform subscription's invoices | `q`, `status`, `page` | Same invoice-number/status filter, additionally fixed to the subscription from the route |

Use 25 rows per page, scoped count before offset/limit, stable descending created time/ID. No client `per_page` control is necessary. Submitting search/filter resets to page 1; Prev/Next preserve only validated filter parameters and locale. Reset returns to the same history without filters. GET creates no invoices or payment requests. Escape wildcard characters for literal matching; validate tenant ID/status/page, clamp page to valid range, and show localized feedback for invalid filters. Use `tenant_id`, not `customer_id`, to avoid replacing the owner's route customer ID. Pagination paths for platform histories retain `/81721200/...` regardless of selected tenant.

Unfiltered empty state reuses existing empty messages. Filtered empty state says no matches and offers Reset; retain typed query/filter values. Server render handles loading; no spinners/fake skeletons on every full-page navigation. On list-query failure render a localized error and retry GET rather than an empty dataset. Back-to-history links preserve validated filter state, never arbitrary return URLs. Platform invoice Download deliberately routes to the invoice tenant's existing authorized settings download path, as `InvoiceTableComponent#download_path` already does.

### E. Tenant recovery and cancellation

Keep recovery in Current subscription and Collection; do not create a separate recovery dashboard.

| Actual state | Tenant path |
|---|---|
| Active/trialing, invoice failure | View affected invoice → authorize/select a charge-ready method → retry eligible open invoice or wait for scheduled collection |
| Scheduled cancellation | Show exact current period end; Keep subscription uses existing DELETE cancellation. It clears schedule, not debt |
| Paused | Show current period end as historical/current anchor; Resume only when server `can_resume` passes. Explain outstanding invoices/method blockers before offering it |
| Past due | Show status, outstanding invoice(s), current-policy grace deadline if derivable, method/invoice links. No unconditional Resume. Current uncollectible invoices cannot be retried/marked paid through existing open-only actions; operator resolution is necessary |
| Cancelled/expired | Show latest ended row's plan/ended date read-only, then select any active plan with Subscribe. Do not call ChangePlan or imply old invoices/benefits/mandate revive automatically |

Cancellation POST always schedules period-end cancellation for tenants; `cancellation[immediately]=false` is an existing form field but the controller ignores its value and hardcodes false. Do not offer a tenant immediate-cancel checkbox. Explain outstanding invoices are not waived and cancellation is not a refund. Date is sourced from the current live row on POST, not trusted from the browser. If already scheduled, show idempotent scheduled result. If ended, show current ended/no-live state and no mutation success.

Resume DELETE clears a schedule, or reactivates a paused row only after backend recovery validation. A paused-row predicate checks unresolved subscription debt/payment operations and requires a ready compatible method only when current collection policy and a positive charge actually require one; free/manual subscriptions must not be blocked by an irrelevant card requirement. It does not restore cancelled/expired rows or settle debt. If one invoice is paid but others remain unresolved, do not display service-restored success. The backend must reconcile Billing subscription recovery explicitly; payment success currently only settles the invoice. Cancellation/Resume controls and server predicates must agree for trialing/active/past_due/paused rather than depending solely on existing button visibility.

### F. Operator action validation and existing catalog forms

Platform detail explicitly shows target customer ID/name and subscription/invoice identity above actions. Keep mutation forms adjacent to their explanation. No extra role or approval system is needed.

| Action | Eligibility to display **and** enforce on POST | Result presentation |
|---|---|---|
| Mark as Paid | Open invoice, no unresolved created/pending capture or succeeded-payment reconciliation; manual settlement decision valid | Paid timestamp/status only after server transition. Explain it records settlement, not a gateway capture |
| Retry Collection | Open invoice, effective gateway mode, ready compatible mandate, no unresolved in-flight/succeeded capture | Distinct paid/processing/failed/blocked result; never generic success for `:failed` or `:pending_manual` |
| Void Invoice | Draft/open, no created/pending/succeeded collection that prevents voiding | Void only after persisted transition; refusal explains collection blocker. No refund claim |
| Cancel immediately | Live subscription, all affected open invoices safe for the chosen cancellation semantics | Explicit immediate termination and open-invoice disposition; preflight before changing state. Existing best-effort void behavior cannot justify an unconditional “all invoices voided” promise |

Move the platform table's ambiguous Cancel emphasis to a clear Cancel immediately label with consequence text and contextual detail link. The existing nested cancellation POST takes no user-editable timing field; backend hardcodes `immediately: true`. Allow the same form on subscription detail, where target identity/consequences are easiest to understand. A native `<details>` action panel is sufficient if actions need visual separation. Turbo confirms may enhance the forms, but server validation and explanatory text must work without JS. Hide terminal-state actions; crafted/stale posts still receive a localized refusal after locked revalidation.

Plan/coupon/settings forms keep their cards and controls. Add error summary using `AlertComponent(type: :error)` and a localized list of actual contract errors; adjacent field error linked through `aria-describedby` and `aria-invalid`. On 422 retain every submitted value, including invalid decimal/numeric text, inactive fields relevant to the selected discount type, limits and the raw comma-separated dunning string. Use native `<details>` or server conditional sections for disclosure; existing coupon/settings Stimulus may remain as enhancement.

Required validation fidelity:

- Plan: nonnegative USD/CNY decimal prices, valid cadence, trial integer >= 0, integer position, required code/name and unique code; code immutable on edit at server, not just a disabled input. Limits accept blank/-1 as unlimited or a whole nonnegative value; reject malformed input rather than silently converting `"abc"` to 0 through `AssignPlanLimits#parse`. Validate all parts before commit. Explain existing subscription price snapshots persist, while catalog limits are read from the plan.
- Coupon: percent 1–100 or positive integer fixed minor units; explicit fixed currency, once/repeating/forever, positive repeating invoice allowance, optional positive redemption cap, clear expiry time zone. Blank fixed currency currently means unrestricted; never silently describe a legacy blank coupon as CNY. Reject unsupported entered currency according to supported catalog policy. Code immutable on edit at server. Enabled badge and Redeemable now are distinct; catalog can add the existing `maint_platform.billing.coupons.show.redeemable_now` label beside status.
- Settings: valid collection mode; nonnegative integer tax/grace/trial-notice values; each dunning offset positive integer. Show current-mode configured providers and explain collection actually uses each tenant's authorized default. `gateway_provider` is still required by the current contract but is not read by Collector for choosing a tenant's gateway; label/explain it as a configured setting, not proof of collection routing. Removing that legacy requirement is a backend policy change, not a frontend dropdown fix.

## 6. Exact submission fields, routes and helpers

`T = /:cid/admin/settings/billing`; `P = /81721200/admin/maintenance/platform/billing`. Platform route helpers take the owner's route customer ID; target tenant is the loaded record, not that URL ID. CSRF tokens and Rails `_method` are framework fields.

### Existing routes and accepted fields

| Action | Verb / path | Exact submitted business fields | Route helper |
|---|---|---|---|
| Read subscription / review | GET `T/subscription` | Proposed query `review_plan_code`; optional display filter `cadence` is unnecessary | `admin_settings_billing_subscription_path(cid)` |
| Subscribe / change live plan | PATCH `T/subscription` | `billing_subscription[plan_code]`; optional `billing_subscription[coupon_code]` for Subscribe only (ChangePlan currently does not use it) | `admin_settings_billing_subscription_path(cid)` |
| Apply live coupon | POST `T/coupon_redemption` | `coupon_redemption[coupon_code]` | `admin_settings_billing_coupon_redemption_path(cid)` |
| Schedule tenant cancellation | POST `T/cancellation` | Existing hidden `cancellation[immediately]=false`; controller permits no timing override | `admin_settings_billing_cancellation_path(cid)` |
| Keep/resume tenant subscription | DELETE `T/cancellation` | None | `admin_settings_billing_cancellation_path(cid)` |
| List / refresh methods | GET `T/payment_methods` | None | `admin_settings_billing_payment_methods_path(cid)` |
| Start/reissue supported authorization | POST `T/payment_methods` | `billing_payment_method[provider]` | `admin_settings_billing_payment_methods_path(cid)` |
| Make default | PATCH `T/payment_methods/:id/make_default` | None; `id` from route | `make_default_admin_settings_billing_payment_method_path(cid, pm)` |
| Remove active method | DELETE `T/payment_methods/:id` | None; `id` from route | `admin_settings_billing_payment_method_path(cid, pm)` |
| Tenant invoice history | GET `T/invoices` | Proposed query `q`, `status`, `page` | `admin_settings_billing_invoices_path(cid)` |
| Tenant invoice / document | GET `T/invoices/:id`, GET `T/invoices/:id/download` | None | `admin_settings_billing_invoice_path(cid, invoice)`; `download_admin_settings_billing_invoice_path(cid, invoice)` |
| Platform invoice history/detail | GET `P/invoices`, GET `P/invoices/:id` | History proposed query `q`, `status`, `tenant_id`, `page` | `admin_maintenance_platform_billing_invoices_path(owner_cid)`; `admin_maintenance_platform_billing_invoice_path(owner_cid, invoice)` |
| Operator invoice actions | POST `P/invoices/:id/mark_paid`, `.../void`, `.../retry` | None; IDs from route | `mark_paid_admin_maintenance_platform_billing_invoice_path`, `void_admin_maintenance_platform_billing_invoice_path`, `retry_admin_maintenance_platform_billing_invoice_path` |
| Platform subscription history/detail | GET `P/subscriptions`, GET `P/subscriptions/:id` | Index proposed query `q`, `status`, `tenant_id`, `page`; detail invoice history `q`, `status`, `page` | `admin_maintenance_platform_billing_subscriptions_path(owner_cid)`; `admin_maintenance_platform_billing_subscription_path(owner_cid, sub)` |
| Immediate operator cancellation | POST `P/subscriptions/:subscription_id/cancellation` | None; controller always immediately true | `admin_maintenance_platform_billing_subscription_cancellation_path(owner_cid, sub)` |
| Create/update plan | POST `P/plans`; PATCH `P/plans/:id` | `billing_plan[code]`, `billing_plan[name]`, `billing_plan[description]`, `billing_plan[amount_usd]`, `billing_plan[amount_cny]`, `billing_plan[interval]`, `billing_plan[trial_days]`, `billing_plan[active]`, `billing_plan[is_default]`, `billing_plan[position]`, `billing_plan[limits][<item_key>]` | `admin_maintenance_platform_billing_plans_path(owner_cid)`; `admin_maintenance_platform_billing_plan_path(owner_cid, plan)` |
| Create/update coupon | POST `P/coupons`; PATCH `P/coupons/:id` | `billing_coupon[code]`, `billing_coupon[name]`, `billing_coupon[discount_type]`, `billing_coupon[percent_off]`, `billing_coupon[amount_off_cents]`, `billing_coupon[currency]`, `billing_coupon[duration]`, `billing_coupon[duration_in_cycles]`, `billing_coupon[max_redemptions]`, `billing_coupon[redeem_by]`, `billing_coupon[active]` | `admin_maintenance_platform_billing_coupons_path(owner_cid)`; `admin_maintenance_platform_billing_coupon_path(owner_cid, coupon)` |
| Update settings | PATCH `P/settings` | `billing_settings[tax_rate_bps]`, `[collection_mode]`, `[gateway_provider]`, `[grace_period_days]`, `[trial_ending_notice_days]`, `[dunning_schedule]` (comma-separated string) | `admin_maintenance_platform_billing_settings_path(owner_cid)` |

Plan/coupon codes disabled on edit are not submitted by the browser; preserve the loaded code and reject crafted changes. Some controller comments mention `platform/module_settings/billing`; actual `config/routes.rb` has **`platform/billing`**. Use the actual helpers above.

### Proposed routes: require backend implementation before rendering controls

| Need | Proposed action contract | Existing integration being reused |
|---|---|---|
| Tenant invoice retry | POST `T/invoices/:id/retry`, no business body; helper `retry_admin_settings_billing_invoice_path(cid, invoice)` | Existing CollectInvoice/Collector; tenant-scoped lookup, eligibility and request reconciliation |
| Billing Stripe SetupIntent | POST `T/payment_methods/setup_intent`; JSON request has no body, provider fixed to Stripe; JSON 2xx response `{ client_secret: ... }`; helper `setup_intent_admin_settings_billing_payment_methods_path(cid)` | Existing controller vault `setupIntentUrl` fetch contract; platform merchant credentials with an explicit tenant-owned billing setup association |
| Billing Stripe completion | POST `T/payment_methods/confirm_setup`; JSON body `{ payment_method_id: "pm_..." }`; helper `confirm_setup_admin_settings_billing_payment_methods_path(cid)`; JSON 2xx on accepted verified/pending association, JSON 422 `{ error: translated_message }` on invalid attempt | Existing controller vault `createUrl` contract. Server matches its own tenant-bound setup attempt and verified provider token; client ID never authorizes itself |

Stripe browser returns to GET `T/payment_methods`; provider `setup_intent`/redirect parameters are correlation hints, not authorization proof. Backend must support redirect completion/webhook activation and same-account publishable key/intent pairing. Member vault URLs and public checkout URLs are not substitutes. No new generic UI API, plan-effective-date endpoint or coupon-removal endpoint is proposed.

## 7. Server interaction flows and failure paths

1. **Select plan:** GET `T/subscription` → eligible plan's Review change link → GET same route with `review_plan_code` → server renders snapshot/estimate/effective explanation → existing PATCH with `billing_subscription[plan_code]` (and signup coupon if any) → revalidate under lock → redirect to same show with applied snapshot or durable pending request/invoice. Invalid/inactive/cadence/stale request renders 422 with selected target retained. GET must be side-effect-free. Repeated unresolved submission reuses/refuses the canonical request, not a second proration invoice.
2. **Benefit:** live plan page → enter coupon → existing POST redemption → success redirect shows benefit/eligibility; failure re-renders 422 at coupon field. No live row → optional signup coupon in review → existing PATCH Subscribe validates in the resolved signup currency. No mutation to already-finalized invoices.
3. **Alipay:** GET methods → existing provider POST with `provider=alipay` → eligibility recheck and pending row → normalized validated provider redirect/form → external authorization → return to methods GET → read verified current state. Abort/vendor-down/invalid signing result leaves Pending/Failed and a localized retry path, no authorized flash. Refresh reads state; it does not itself approve the mandate.
4. **Stripe setup, conditional:** methods GET renders supported setup panel → existing Stimulus loads/prepares intent via proposed billing POST → Stripe iframe collects/confirms → proposed completion POST with PSP `payment_method_id` → server verifies/binds or retains Pending → methods GET displays actual state. SDK/validation/3DS/webhook-delay errors stay in panel or show Pending on return. This is the provider exception to server-only forms; all tenant/merchant associations and eligibility are server-owned.
5. **Default/removal:** methods GET → existing PATCH default/DELETE remove → locked tenant-scoped active-row revalidation → redirect to methods. Incomplete/mismatched default gets a localized refusal. Removing sole/default method shows actual next-step method/invoice guidance, not a promise of automatic replacement or PSP revocation.
6. **Collect/recover:** subscription recovery link → invoice GET → methods GET/setup/default as needed → return to original authorized invoice GET → proposed retry POST (or existing Stripe PaymentIntent authentication) → invoice GET with Paid/Processing/Failed state. Do not set subscription active in the view. Past_due/uncollectible routes to operator resolution and accurate grace context. Resume only through validated existing DELETE cancellation.
7. **Cancel/keep:** plan GET → dated period-end cancellation form → existing POST → plan GET shows cancelling/date. Keep subscription uses DELETE → page shows remaining actual status. Ended/stale row refuses mutation and presents latest ended snapshot. Operator immediate cancellation uses existing platform nested POST → preflight state/payment conflicts → cancel and valid invoice disposition → platform subscription GET shows actual results.
8. **Find history:** index GET → toolbar GET `q/status/tenant_id` → scoped filtered page 1 → normal Prev/Next GET preserving allowed filters → invoice/subscription GET → back to validated history state. Empty query result keeps controls; invalid query gets localized correction; no record leakage via filtering or pagination.
9. **Operator settlement/form save:** platform detail/form GET → existing action POST or form POST/PATCH → state/contract validation → success redirect reflecting stored result, or 422 with submitted values and actionable errors. Vendor failure uses machine-readable translated outcome, not `exception.message`. Read-only/stale crafted actions get refusal rather than misleading success.

Authorization failures use existing `RouteAuthorization`/TenantContext behavior: unauthenticated sign-in redirect (JSON 401), denied HTML redirects to authorized tenant landing/JSON 403, and cross-tenant record IDs in tenant controllers return 404. Frontend must not retry mutations on a permission error. Platform access remains owner-only; tenant admin/owner billing records remain scoped to the URL customer even when platform-owner records are looked up to perform collection.

## 8. Responsive, accessibility, Tailwind and Stimulus guidance

- Keep existing settings shell and `gap-6` section rhythm; `card`, `section-header`, `text-body`, `text-body-sm`, `form-label`, `input-field`, `btn btn-primary/secondary/danger`, and project `text-text-*` / `border-border-subtle` / status tokens. Use `px-4 py-4 sm:px-6`, `min-w-0`, `break-words`, `tabular-nums`; no custom CSS, React or shadcn runtime dependency.
- At 320/375 px, facts/actions stack with `flex-col`; at `sm`, two-column fact grids and wrapping actions; only at sufficient content width (`lg` in Settings) show dense histories. Keep platform tables locally `overflow-x-auto`, not page-level overflow. Put primary actions `w-full sm:w-auto` where needed; long zh-CN text must wrap.
- The customer comparison currently intentionally uses a contained horizontally scrollable semantic table. Preserve it with keyboard-focusable labelled region and caption; review/pending/coupon/recovery blocks stay full-width and readable without horizontal scrolling. Avoid repeating large plan cards as a redesign.
- Every table needs caption/label, `scope="col"`/`scope="row"`, a text Actions heading (can be `sr-only`), and right-aligned numeric totals. Mobile invoice rows retain all decision-critical status/collection/action data. A scroll region needs visible focus and no clipped controls.
- Persistent pending/recovery callouts use a labelled section; errors use `role="alert"`, nonurgent status updates `role="status"`/`aria-live="polite"`. Wrap existing AlertComponent where necessary; do not silently assume it already supplies these roles. Never auto-dismiss unresolved billing blockers.
- Each field has an explicit translated label, error ID, `aria-invalid` and `aria-describedby`. Summary errors point to fields. Native details/summary is keyboard-operable. Disabled actions have a nearby reason; don't communicate pending/blocked solely with color.
- Shared pagination currently hides text below `sm`; add translated accessible labels to the icon links using existing Previous/Next keys. This is a narrow `app/components/admin/pagination_component.html.erb` accessibility patch, not a pagination redesign.
- Rails GET/POST/PATCH/DELETE handles review/filter/pagination/coupon/cancellation/default/removal/retry. Existing `billing-plan-compare` confirmation and `payment-method` behavior are optional enhancements; server review and explanatory text are authoritative. Do not write a new controller for these flows.
- Retain `billing-coupon-form` / `billing-settings` enhancement where useful; ensure relevant fields are available in server-rendered/error states and usable when JS is unavailable. Stripe is the only conditional client extension: existing `app/javascript/controllers/payments/stripe_card_controller.js`, existing loader `app/javascript/lib/stripe_js_loader.js`; no new JS files.
- Bind all existing Stripe Values through translated `data-payments--stripe-card-*-value` attributes, with `element` and `error` targets. Error messages remain localized Values/server responses, not new JS literals. Any later modification of the existing JS requires the project's real 100% line/branch coverage checks; this design delivery does not execute tests.
- Print/download keeps invoice identity, line items, amount/currency, period and persisted paid date; `print:hidden` on setup/recovery/filters/actions, and no client secret in download rendering.

## 9. Exact I18n handoff

All keys below are a **task inventory**, not edits to locale files in this audit. Add both English and idiomatic Simplified Chinese together, retaining identical interpolation tokens. Translate at request/render time; stable key strings may be constants, translated output may not. Dates use `I18n.l`, amounts use CurrencyResolver with stored currency. User-entered plan/coupon names and masked account details are data; built-in labels and generated account prose must be I18n.

### Reuse existing keys

| File pair | Exact keys / existing subtree used |
|---|---|
| `config/locales/settings_navigation.en.yml`, `.zh-CN.yml` | `settings_navigation.items.plan_subscription`, `.billing_payment_methods`, `.invoices` |
| `config/locales/settings_billing.en.yml`, `.zh-CN.yml` | `settings_billing.subscription.description`, `.price`, `.cancellation_date`, `.trial_end`, `.renewal_date`, `.ended_at`, `.period_end`, `.none`, `.compare_hint`, `.billed_price`, `.monthly_equivalent`, `.prices_note`, `.trial`, `.manage`, `.cancel_hint`, `.states.{past_due,paused,cancelled,expired}`; `settings_billing.payment_methods.{description,saved,empty,authorization,authorization_hint,unavailable,remove_confirm}`, `.readiness.{pending,failed,removed}`; `settings_billing.invoices.{description,download_hint}` |
| `config/locales/comp_billing.en.yml`, `.zh-CN.yml` | `comp_billing.plan_comparison.{current_subscription,plan_fallback,compare_plans,no_plans,current_badge,current_plan_btn,free,trial_days_free,unlimited,subscribe,switch,apply_coupon,coupon_code_label,coupon_code_placeholder,apply,interval_year,interval_month}`, `.statuses.{trialing,active,past_due,paused,cancelled,expired}`; `comp_billing.payment_method.{default_badge,account,authorized,make_default,add_another,setup_provider,no_providers}`, `.statuses.{pending,active,failed,removed}`; `comp_billing.invoice_table.{invoices_heading,empty,number,customer,issued,due,total,draft}`, `.statuses.{draft,open,paid,void,uncollectible}`; all existing `comp_billing.invoice_detail` labels/action/confirmation/kind keys; `comp_billing.subscription_summary.{period,coupon}`; `comp_billing.subscriptions_table.{subscriptions_heading,customer,plan,interval,amount,period_end,empty}`; `comp_billing.plan_form.intervals.{monthly,yearly}` and existing plan/coupon/settings field keys; `comp_billing.coupon_table.durations.{once,repeating,forever}`, `.duration_cycles` |
| `config/locales/common.en.yml`, `.zh-CN.yml` | `common.actions.{search,filter,reset,view,back,continue,cancel,remove,next,previous,download}`, `common.labels.{status,actions,customer,all,em_dash,description}`, `common.status.{loading,processing,configured,active,inactive,pending,failed}` |
| `config/locales/chrome.en.yml`, `.zh-CN.yml` | `chrome.pagination.page_of_html`, `.prev`; use `common.actions.next` for existing next link |
| `config/locales/comp_payments.en.yml`, `.zh-CN.yml` | `comp_payments.shared.stripe_unavailable`; `comp_payments.stripe.{unexpected_error,setup_intent_failed,missing_client_secret,missing_payment_method,server_error,processing}`; `comp_payments.member.payment_methods.save_card` (identical “Save card” text only; reuse key does not reuse member route); `comp_payments.widget_checkout.secured_by` |
| `config/locales/admin_settings.en.yml`, `.zh-CN.yml` | `admin_settings.errors.validations.{plan_not_active,plan_interval_mismatch,provider_not_available,coupon_not_found,coupon_not_redeemable,coupon_currency,gateway_provider_required,dunning_schedule_positive}`; `admin_settings.flash.coupon_redemptions.{not_found,not_redeemable,currency_mismatch,already_applied,once_elapsed,applied}`; `admin_settings.flash.payment_methods.{authorized,pending_authorization,removed,default_updated,provider_unavailable}`; `admin_settings.flash.subscriptions.{subscribed,plan_changed,plan_change_not_collected}` (last one for actual failure only); `admin_settings.flash.cancellations.{scheduled,resumed}`; existing invoice title/back keys |
| `config/locales/maint_platform.en.yml`, `.zh-CN.yml` | Existing `maint_platform.billing` breadcrumb/page-title keys; `maint_platform.billing.coupons.show.redeemable_now`; `maint_platform.flash.billing.{invoice_marked_paid,invoice_voided,invoice_cannot_mark_paid,invoice_cannot_void,invoice_collection_skipped,subscription_cancelled,plan_in_use,plan_created,plan_updated,coupon_created,coupon_updated,settings_updated}` |

### Add to `config/locales/settings_billing.en.yml` and `config/locales/settings_billing.zh-CN.yml`

In this table, prefixes are exact. `%{...}` is Ruby I18n interpolation, not JavaScript interpolation.

| Full key | English | zh-CN |
|---|---|---|
| `settings_billing.subscription.currency` | Billing currency | 计费币种 |
| `settings_billing.subscription.currency_snapshot_hint` | Your subscription keeps its stored currency when language settings change. | 更改语言设置不会改变订阅已保存的计费币种。 |
| `settings_billing.subscription.currency_unavailable` | Plan changes are unavailable for the stored currency %{currency}. | 已保存的币种 %{currency} 暂不支持切换套餐。 |
| `settings_billing.subscription.cadence_restriction` | A current subscription can only switch to a plan with the same billing interval. | 现有订阅只能切换至计费周期相同的套餐。 |
| `settings_billing.subscription.review_change` | Review plan change | 查看套餐变更详情 |
| `settings_billing.subscription.change_review_title` | Change to %{plan} | 切换至 %{plan} |
| `settings_billing.subscription.proration_estimate` | Estimated prorated total | 预估按比例计费总额 |
| `settings_billing.subscription.proration_estimate_hint` | Calculated at %{time}. The final invoice is calculated when you submit. | 估算时间为 %{time}。最终账单将按提交时的情况计算。 |
| `settings_billing.subscription.effective_date` | Effective date | 生效时间 |
| `settings_billing.subscription.effective_on_collection` | Takes effect after the prorated invoice is collected. | 按比例计费账单收款完成后生效。 |
| `settings_billing.subscription.effective_manual` | Takes effect when the request is accepted. The invoice still awaits manual settlement. | 请求受理后生效；账单仍待人工结算。 |
| `settings_billing.subscription.trial_change_hint` | Changing plans during a trial can create an invoice before the trial ends. | 在试用期内切换套餐，可能会在试用结束前生成账单。 |
| `settings_billing.subscription.pending_change_title` | Pending change to %{plan} | 待完成的套餐变更：%{plan} |
| `settings_billing.subscription.pending_payment` | Payment is processing. Your current plan remains in effect until collection completes. | 付款处理中。收款完成前，当前套餐继续生效。 |
| `settings_billing.subscription.failed_change` | The change is waiting for payment. Review the linked invoice and payment method. | 此变更尚待付款。请检查关联账单和付款方式。 |
| `settings_billing.subscription.effective_pending` | Effective date not yet confirmed | 生效时间尚未确认 |
| `settings_billing.subscription.latest_ended` | Most recent ended subscription | 最近结束的订阅 |
| `settings_billing.subscription.keep_subscription` | Keep subscription | 保留订阅 |
| `settings_billing.subscription.cancel_at_date` | Cancel this subscription at %{date}? Outstanding invoices are not waived. | 确认于 %{date} 取消此订阅？未结清账单仍需支付。 |
| `settings_billing.subscription.recovery_heading` | Resolve subscription payment | 处理订阅付款问题 |
| `settings_billing.subscription.recovery_hint` | Resolve outstanding invoices before service recovery can be confirmed. | 请先处理未结清账单，再确认服务是否已恢复。 |
| `settings_billing.subscription.grace_deadline` | Grace period ends under current policy: %{date} | 按当前规则，宽限期于 %{date} 结束。 |
| `settings_billing.payment_methods.other_methods` | Pending and inactive methods | 待授权及不可用的付款方式 |
| `settings_billing.payment_methods.all_empty` | No billing payment methods have been saved. | 尚未保存任何账单付款方式。 |
| `settings_billing.payment_methods.continue_authorization` | Continue authorization | 继续授权 |
| `settings_billing.payment_methods.retry_authorization` | Reauthorize | 重新授权 |
| `settings_billing.payment_methods.return_pending` | Provider confirmation is pending. Refresh this page to check the current status. | 正在等待服务商确认。请刷新页面查看最新状态。 |
| `settings_billing.payment_methods.currency_incompatible` | This provider cannot collect invoices in %{currency}. | 此服务商无法收取 %{currency} 币种的账单款项。 |
| `settings_billing.payment_methods.setup_unsupported` | Billing authorization is not available for this provider. | 此服务商暂不支持账单扣款授权。 |
| `settings_billing.payment_methods.no_compatible_providers` | No configured billing provider supports %{currency}. | 尚无已配置的账单服务商支持 %{currency}。 |
| `settings_billing.payment_methods.mandate_unready` | The linked authorization is not ready for collection. | 关联授权尚未就绪，暂时无法扣款。 |
| `settings_billing.payment_methods.gateway_unavailable` | The provider is currently unavailable for collection. | 此服务商目前无法用于扣款。 |
| `settings_billing.payment_methods.remove_default_hint` | This is your default payment method. Choose another ready method for future collection. | 此为默认付款方式。请为后续扣款选择其他可用方式。 |
| `settings_billing.payment_methods.stripe_setup_hint` | Authorize a card for future subscription charges using the secure Stripe form. | 请通过 Stripe 安全表单授权银行卡，用于后续订阅扣款。 |
| `settings_billing.payment_methods.authorize_redirect_hint` | Continue to %{provider} to authorize recurring subscription charges. | 请前往 %{provider} 授权定期支付订阅费用。 |
| `settings_billing.payment_methods.providers.alipay` | Alipay (China) | 支付宝（中国） |
| `settings_billing.payment_methods.providers.stripe` | Credit / Debit Card (Stripe) | 信用卡／借记卡（Stripe） |
| `settings_billing.invoices.retry_payment` | Retry invoice payment | 重试账单付款 |
| `settings_billing.invoices.complete_authentication` | Complete payment authentication | 完成付款验证 |
| `settings_billing.invoices.operator_resolution` | This invoice requires resolution by the platform administrator. | 此账单需由平台管理员处理。 |

Do not reuse `settings_billing.payment_methods.readiness.active` unconditionally; it asserts authorization. Use it only when full charge readiness is confirmed. Existing JS plan confirmation keys use `{plan}` templates; if retained, pass the existing translated Value contract and keep that token style. Server review keys above use `%{plan}`.

### Add to `config/locales/comp_billing.en.yml` and `config/locales/comp_billing.zh-CN.yml`

| Full key | English | zh-CN |
|---|---|---|
| `comp_billing.subscription_coupon.benefit_heading` | Coupon benefit | 优惠权益 |
| `comp_billing.subscription_coupon.percent_benefit` | %{percent}% off eligible charges | 符合条件的费用优惠 %{percent}% |
| `comp_billing.subscription_coupon.fixed_benefit` | Up to %{amount} off eligible charges | 符合条件的费用最高减免 %{amount} |
| `comp_billing.subscription_coupon.remaining_invoices` | en one: `%{count} future invoice remaining`; other: `%{count} future invoices remaining` | zh-CN other: `后续还可用于 %{count} 张账单` |
| `comp_billing.subscription_coupon.eligible_next` | Eligible for the next qualifying invoice | 可用于下一张符合条件的账单 |
| `comp_billing.subscription_coupon.exhausted` | Invoice allowance used up | 可用账单次数已用完 |
| `comp_billing.subscription_coupon.inactive` | This coupon is disabled. | 此优惠券已停用。 |
| `comp_billing.subscription_coupon.expired` | This coupon has expired. | 此优惠券已过期。 |
| `comp_billing.subscription_coupon.currency_mismatch` | This attached coupon does not apply to %{currency}. | 已关联的优惠券不适用于 %{currency}。 |
| `comp_billing.subscription_coupon.invoice_count_hint` | Finalized invoices, including prorated and void invoices, count toward the allowance. | 已出具的账单均计入次数，包括按比例计费账单和已作废账单。 |
| `comp_billing.subscription_coupon.future_only` | Coupon benefits are calculated on new invoices; issued invoices are unchanged. | 优惠将在新账单中计算，已出具的账单不变。 |
| `comp_billing.subscription_coupon.locked_hint` | A coupon is already attached to this subscription and cannot be replaced here. | 此订阅已关联优惠券，无法在此替换。 |
| `comp_billing.collection.heading` | Collection status | 收款状态 |
| `comp_billing.collection.recorded_mode` | Recorded collection mode | 账单记录的收款方式 |
| `comp_billing.collection.current_mode` | Current collection mode | 当前收款方式 |
| `comp_billing.collection.failed_attempts` | Failed collection attempts | 收款失败次数 |
| `comp_billing.collection.next_attempt` | Next scheduled attempt | 下次计划扣款时间 |
| `comp_billing.collection.awaiting_collection` | Awaiting collection | 待收款 |
| `comp_billing.collection.awaiting_manual` | Awaiting manual settlement | 待人工结算 |
| `comp_billing.collection.processing` | Collection is processing | 收款处理中 |
| `comp_billing.collection.authentication_required` | Payment authentication required | 需要完成付款验证 |
| `comp_billing.collection.retry_scheduled` | Collection retry scheduled | 已安排重试收款 |
| `comp_billing.collection.method_required` | A ready payment method is required | 需要可用的付款方式 |
| `comp_billing.collection.reconciliation_required` | Payment received; invoice settlement needs reconciliation | 已收到付款，账单结算状态待核对 |
| `comp_billing.collection.refresh` | Refresh collection status | 刷新收款状态 |
| `comp_billing.history.invoice_query` | Search invoice numbers | 搜索账单编号 |
| `comp_billing.history.subscription_query` | Search plan names or codes | 搜索套餐名称或代码 |
| `comp_billing.history.no_matches` | No billing records match these filters. | 没有符合筛选条件的计费记录。 |
| `comp_billing.history.load_failed` | Billing history could not be loaded. Try again. | 无法加载计费记录，请重试。 |
| `comp_billing.plan_form.snapshot_hint` | Catalog price edits do not change existing subscription price snapshots. Plan limits are read from the current plan. | 修改目录价格不会改变现有订阅保存的价格。用量上限按当前套餐读取。 |
| `comp_billing.coupon_form.currency_hint` | Fixed discounts use this currency. A blank legacy currency applies without a currency restriction. | 固定金额优惠以此币种计价。历史记录的币种为空时，不限制适用币种。 |
| `comp_billing.coupon_form.invoice_duration_hint` | Repeating duration counts finalized invoices, not calendar months. | 重复优惠按已出具账单计次，并非按自然月计算。 |
| `comp_billing.settings_form.provider_selection_hint` | Collection uses each customer's authorized default method; this setting does not choose their provider. | 收款使用各客户已授权的默认付款方式；此设置不会为客户选择服务商。 |
| `comp_billing.operator.cancel_immediately` | Cancel immediately | 立即取消订阅 |
| `comp_billing.operator.cancel_consequence` | Cancels this subscription now. Eligible open invoices will be voided; in-flight payments must be resolved first. | 此操作将立即取消订阅，并作废符合条件的未结清账单；处理中的付款须先解决。 |
| `comp_billing.operator.manual_settlement_hint` | Marking paid records settlement; it does not charge a payment provider. | 标记已付款仅记录结算结果，不会向支付服务商发起扣款。 |

For `remaining_invoices`, use `.one` and `.other` in **both** locale files to keep leaf-key parity; zh-CN can give both the same idiomatic value. Translate data-driven enum labels at render time, never generate them with `humanize`.

### Add server validation/outcome keys in the existing area files

These are backend/controller handoff keys used by the same frontend; they are not new frontend business rules.

| Full key and destination pair | English | zh-CN |
|---|---|---|
| `admin_settings.flash.subscriptions.plan_change_pending` — `config/locales/admin_settings.{en,zh-CN}.yml` | Your plan change is waiting for invoice collection. | 套餐变更尚待账单收款完成。 |
| `admin_settings.flash.subscriptions.plan_change_manual` — same | Your plan has changed. The invoice awaits manual settlement. | 套餐已变更，账单仍待人工结算。 |
| `admin_settings.flash.cancellations.resume_blocked` — same | Resolve outstanding payment issues before resuming this subscription. | 请先解决未完成的付款问题，再恢复订阅。 |
| `admin_settings.flash.billing.invalid_action` — same | This action is not available in the current billing state. | 当前计费状态不允许此操作。 |
| `admin_settings.flash.billing.invalid_filters` — same | Some billing filters were invalid. Review the corrected filters. | 部分计费筛选条件无效，请检查更正后的条件。 |
| `admin_settings.flash.invoices.payment_succeeded` — same | Invoice payment completed. | 账单付款已完成。 |
| `admin_settings.flash.invoices.payment_pending` — same | Invoice payment is processing. Check its status before retrying. | 账单付款处理中，请先查看状态，再决定是否重试。 |
| `admin_settings.flash.invoices.payment_failed` — same | Invoice payment failed. Review the payment method and collection status. | 账单付款失败，请检查付款方式和收款状态。 |
| `admin_settings.flash.invoices.retry_blocked` — same | This invoice cannot be retried in its current collection state. | 此账单当前的收款状态不允许重试。 |
| `admin_settings.flash.payment_methods.setup_failed` — same | Billing payment authorization could not be completed. Try again. | 无法完成账单付款授权，请重试。 |
| `admin_settings.flash.payment_methods.not_ready` — same | This method is not ready for invoices in your billing currency. | 此付款方式尚无法支付您的计费币种账单。 |
| `admin_settings.errors.validations.code_immutable` — same | cannot be changed after creation | 创建后不可更改 |
| `admin_settings.errors.validations.limit_invalid` — same | must be blank, -1, or a nonnegative whole number | 须为空、-1 或非负整数 |
| `admin_settings.errors.validations.currency_not_supported` — same | must be a supported billing currency | 须为支持的计费币种 |
| `maint_platform.flash.billing.invoice_collection_succeeded` — `config/locales/maint_platform.{en,zh-CN}.yml` | Invoice %{number} has been collected. | 账单 %{number} 已完成收款。 |
| `maint_platform.flash.billing.invoice_collection_pending` — same | Collection for invoice %{number} is processing. | 账单 %{number} 的收款正在处理中。 |
| `maint_platform.flash.billing.invoice_collection_failed` — same | Collection for invoice %{number} failed. Review its collection status. | 账单 %{number} 收款失败，请查看收款状态。 |
| `maint_platform.flash.billing.invoice_collection_manual` — same | Invoice %{number} awaits manual settlement; no gateway charge was made. | 账单 %{number} 待人工结算，未发起网关扣款。 |
| `maint_platform.flash.billing.invoice_action_in_flight` — same | Resolve the existing payment attempt before changing this invoice. | 请先处理现有付款请求，再更改此账单。 |
| `maint_platform.flash.billing.subscription_cannot_cancel` — same | This subscription cannot be cancelled immediately in its current state. | 此订阅当前状态不允许立即取消。 |

Reuse identical English already keyed elsewhere rather than adding synonyms or duplicate shared labels. Extend provider-name keys only for providers with an implemented billing setup flow; do not advertise every registered Payments gateway. New keys listed here must be added in both locales before rendering the feature.

## 10. Frontend task brief: exact files

### Existing ViewComponent pairs to update

All of these are exact existing basenames under `app/components/billing/admin/`; update the `.rb` and `.html.erb` together as props/formatting require:

1. `plan_comparison_component` — forward server contracts; eligibility/currency helpers shared with subclass.
2. `customer_subscription_component` — current/ended facts, inline review, pending request, coupon benefit, recovery, dated cancellation.
3. `payment_method_component` — forward currency/readiness/setup contracts; translated provider names.
4. `customer_payment_methods_component` — grouped all-status list and state-valid actions.
5. `payment_authorization_component` — supported provider handoff and conditional Stripe panel.
6. `invoice_table_component` — GET toolbar, collection cell/mobile datum, shared pagination.
7. `invoice_detail_component` — collection facts/eligibility, conditional tenant retry/authentication, operator explanations.
8. `subscriptions_table_component` — GET toolbar, pagination, pending/cancelling indicators, explicit immediate-cancel meaning.
9. `subscription_summary_component` — platform target identity, accurate date/coupon/pending facts and conditional operator cancellation contract.
10. `plan_form_component` — contract-backed retained values/errors and snapshot hint.
11. `coupon_form_component` — contract-backed retained values/errors and currency/invoice-duration guidance.
12. `coupon_table_component` — optional adjacent redeemability fact using existing key, not enabled = benefit.
13. `settings_form_component` — contract-backed retained/raw invalid input and actual provider-selection guidance.

### Existing mounting views to wire

```text
app/views/admin/settings/billing/subscriptions/show.html.erb
app/views/admin/settings/billing/payment_methods/index.html.erb
app/views/admin/settings/billing/invoices/index.html.erb
app/views/admin/settings/billing/invoices/show.html.erb
app/views/admin/settings/billing/invoices/download.html.erb
app/views/admin/maintenance/platform/billing/subscriptions/index.html.erb
app/views/admin/maintenance/platform/billing/subscriptions/show.html.erb
app/views/admin/maintenance/platform/billing/invoices/index.html.erb
app/views/admin/maintenance/platform/billing/invoices/show.html.erb
app/views/admin/maintenance/platform/billing/plans/new.html.erb
app/views/admin/maintenance/platform/billing/plans/edit.html.erb
app/views/admin/maintenance/platform/billing/coupons/new.html.erb
app/views/admin/maintenance/platform/billing/coupons/edit.html.erb
app/views/admin/maintenance/platform/billing/settings/show.html.erb
app/views/admin/maintenance/platform/billing/settings/edit.html.erb
app/components/admin/pagination_component.html.erb
```

Locale edits: `config/locales/settings_billing.{en,zh-CN}.yml`, `comp_billing.{en,zh-CN}.yml`, `admin_settings.{en,zh-CN}.yml`, `maint_platform.{en,zh-CN}.yml`, using the exact section 9 inventory. Shared/Stripe/navigation keys are reused from their existing files. Conditional Stripe enhancement, only if needed to fulfill setup initialization/3DS completion: `app/javascript/controllers/payments/stripe_card_controller.js`; reuse loader and controller for invoice authentication, with no new JS file.

### Server dependencies to hand off before enabling corresponding controls

| Dependency | Exact existing source touchpoints |
|---|---|
| Stored currency, ended history, read-only review and durable pending-request presentation | `app/controllers/admin/settings/billing/subscriptions_controller.rb`, `base_controller.rb`; `app/services/billing/contracts/{subscribe,change_plan}.rb`; `app/services/billing/activities/change_plan.rb`; `app/services/billing/proration.rb`; `app/models/billing/{subscription,invoice}.rb`; `app/services/payments/activities/handle_webhook.rb`. Durable linkage/storage is backend-owned; it does not exist today |
| Coupon benefit/retained errors | `app/controllers/admin/settings/billing/coupon_redemptions_controller.rb`; `app/services/billing/activities/{apply_coupon,finalize_invoice}.rb`; `app/models/billing/coupon.rb` |
| All methods, readiness, truthful provider capabilities/currency and actual setup activation | `app/controllers/admin/settings/billing/payment_methods_controller.rb`; `app/services/billing/available_providers.rb`; `app/services/billing/contracts/payment_method.rb`; `app/services/billing/activities/{set_up_payment_method,remove_payment_method}.rb`; `app/models/billing/payment_method.rb`; `app/models/payments/{subscription,payment_method}.rb`; `app/services/payments/{gateway,credential_resolver}.rb`; `app/services/payments/gateways/{alipay,stripe}.rb`; `app/services/payments/activities/handle_webhook.rb`; `config/routes.rb` for proposed admin setup/completion endpoints |
| Collection presentation, tenant retry and histories | `app/controllers/admin/settings/billing/invoices_controller.rb`; `app/controllers/admin/maintenance/platform/billing/{invoices,subscriptions}_controller.rb`; `app/services/billing/collector.rb`; `app/services/billing/activities/collect_invoice.rb`; `app/models/payments/payment.rb`; `config/routes.rb` for proposed tenant retry |
| Recovery and validated cancellations/settlement | `app/controllers/admin/settings/billing/cancellations_controller.rb`; `app/controllers/admin/maintenance/platform/billing/{cancellations,invoices}_controller.rb`; `app/services/billing/activities/{cancel_subscription,resume_subscription,mark_invoice_paid,void_invoice}.rb`; `app/services/billing/cron/{dunning,renew_subscriptions}.rb`; `app/services/payments/activities/handle_webhook.rb` |
| Real operator form validation | `app/controllers/admin/maintenance/platform/billing/{plans,coupons,settings}_controller.rb`; `app/services/billing/contracts/{plan,coupon,settings}.rb`; `app/services/billing/assign_plan_limits.rb` |

The implementation must update `doc/reference/en/billing.md` and `doc/reference/zh-CN/billing.md` in the same source change. For billing setup/payment contract additions also update `doc/reference/en/payments.md` and `doc/reference/zh-CN/payments.md`; tenant workflow changes update `doc/customer/en/billing.md` and `doc/customer/zh-CN/billing.md`. This audit records proposed design, not implemented application behavior.

### Completion criteria for the frontend handoff

- Locale change cannot change displayed live billing denomination or present a mismatched amount/cadence as selectable.
- Ended snapshots, trial/renewal/cancellation/effective dates and unresolved changes remain distinguishable after a page reload.
- Coupon attachment, remaining benefit, final invoice discount and redemption eligibility are separate facts.
- Pending/failed/removed methods remain visible; unsupported/unconfigured/incompatible setup never appears ready.
- Alipay takes the supported browser authorization path; Stripe setup appears only with functioning billing endpoints/verified association and initialized existing widget.
- Invoice paid/open state and collection state are both visible; retry/authentication works on the original payment/invoice and honors server eligibility.
- All histories are searchable and truly paginated, including older-than-100 records and platform subscription detail invoices.
- Tenant recovery/cancellation and operator actions show actual server outcomes, retained validation errors, and correct tenant/target identity.
- Small-screen and zh-CN layouts preserve action reasons and status information; every added wording uses the matching en/zh-CN keys.

Design status: **READY_FOR_FRONTEND with explicit server dependencies**. Display-only changes and form/error wiring can begin from this map. Pending-change completion, tenant retry, Stripe billing setup and debt-aware recovery require the documented server contracts before their controls are enabled.
