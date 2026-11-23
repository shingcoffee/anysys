# Default Payment Gateway (per customer)

Date: 2026-06-22
Status: Approved

## Summary

On the customer payment settings
(`/:cid/admin/settings/modules/payments/merchant_accounts`), let an admin choose
a **default gateway** for their tenant. The default is used to pre-select / order
the shopper checkout and as the fallback provider when a charge is initiated
without an explicit one. Only **enabled + configured** gateways are eligible.

Scope confirmed earlier: drives **checkout selection + server-charge fallback**;
stored in a **dedicated per-customer record**.

Brand-new app — no backward-compatibility constraints. The payment single-file
rule is preserved (no per-vendor changes; a new gateway auto-participates).

## Data

- New model `Payments::DefaultGateway` + table `payment_default_gateways`:
  `customer_id` (null:false, **unique index** — one default per tenant),
  `provider` (null:false, string), timestamps. Tenant-scoped (`TenantScoped`).
- `Payments::DefaultGateway.provider_for(customer_id)` → the stored default
  provider string, or nil. Returns nil when no row exists.
- Service `Payments::SetDefaultGateway.call(customer:, provider:)`:
  - Rejects (raises `ArgumentError`) unless `provider` is currently **eligible**
    (enabled + configured + platform-available) for the customer.
  - Upserts the single `(customer_id)` row to the new provider (atomic — one row,
    no clear-others needed).

## Eligibility — enabled + configured

- `Payments::MerchantAccount#configured?` →
  `enabled?` AND `merchant_id.present?` AND not a `unset-…` provisioner
  placeholder AND every `gateway_class.credential_fields` name has a present
  value in the `credentials` blob. (No `required` flag exists on credential
  fields, so all declared fields are treated as required.)
- `Payments::EligibleGateways.for(customer)` → ordered array of gateway **classes**
  (`Payments::Gateways::*`) that are platform-available
  (`Payments::PlatformGateway.available?`) AND have an active+configured
  `MerchantAccount` for the customer. Single source of truth for "what can be
  default / offered at checkout". Ordering: registry order
  (`Payments::Gateways.all`).

## UI — merchant_accounts gallery (`Payments::Admin::GatewayCardComponent`)

- Card gains awareness of the current default (passed down from the gallery):
  - A **"Default"** badge when this provider is the tenant default.
  - A **"Set as default"** button shown only when the gateway is eligible
    (enabled + configured) and not already the default.
- `GatewayGalleryComponent` / `MerchantAccountsController#index` compute the
  current default (`DefaultGateway.provider_for`) and pass it to the cards.
- New route under the payments settings namespace:
  `resource :default_gateway, only: :update, controller: "default_gateways"`
  (path `/:cid/admin/settings/modules/payments/default_gateway`). Admin-scoped
  (inherits the area's admin guard), tenant-scoped. `update` reads
  `params[:provider]`, calls `SetDefaultGateway`, redirects back to the gallery
  with a notice (or alert on `ArgumentError`).

## Consumption

### Checkout (`Payments::CheckoutComponent` + `CheckoutsController`)
- Replace the **hardcoded** WeChat/Alipay buttons with a dynamic list built from
  `EligibleGateways.for(@customer)`: one submit button per gateway
  (`name="provider" value="<key>"`, label = `display_name`), the **default
  first** and visually highlighted.
- `CheckoutComponent.new(order:, gateways:, default_provider:, errors:)` — render
  buttons from the passed list; no registry/DB access in the component.
- `CheckoutsController#show` passes `gateways:` (eligible) and
  `default_provider:` (`provider_for` if still eligible, else first eligible).
- `CheckoutsController#create`: `provider = params[:provider].presence ||
  default_provider`. If still blank (no eligible gateway), render the checkout
  with an error.
- Empty state: when no eligible gateway, the checkout shows a "no payment methods
  available" message instead of buttons.

### Server-initiated charges
- `Payments::DefaultGateway.provider_for(customer_id)` is the canonical fallback
  for any server path that must pick a provider without an explicit one. The
  shopper checkout `create` (above) is the primary consumer. Records that already
  carry a `provider` (e.g. existing subscriptions) are unchanged; this is purely
  a fallback when none is specified.

## Authorization & Multi-tenancy

- `default_gateways#update` is under `/:cid/admin/settings/modules/payments/…`
  (Area b, admin), guarded like the sibling `merchant_accounts` controller;
  every lookup is scoped to `current_customer`. `payment_default_gateways` rows
  carry `customer_id` and are tenant-scoped. The public checkout already pins
  every record to the URL tenant; `EligibleGateways.for(@customer)` is
  customer-scoped.

## Testing

- **Model**: `DefaultGateway` unique-per-customer; `provider_for` returns
  stored/nil.
- **MerchantAccount#configured?**: true only with real merchant_id + all
  credentials; false for placeholder/missing creds/disabled.
- **EligibleGateways**: includes only platform-available + active + configured;
  excludes disabled/unconfigured/unavailable.
- **SetDefaultGateway**: sets an eligible provider; raises for
  disabled/unconfigured/unknown.
- **Request** (`default_gateways#update`): admin sets default; member/anonymous
  rejected; cross-tenant rejected; ineligible provider → alert, no change.
- **Component**: `GatewayCardComponent` shows Default badge for the default and
  "Set as default" only for eligible non-default; `CheckoutComponent` renders a
  button per eligible gateway with the default first, and an empty state when
  none.
- **Checkout request**: `show` lists eligible gateways (default first); `create`
  with no provider falls back to the default; `create` with no eligible gateway
  errors gracefully.

## Out of scope

- Changing the separate platform-billing provider selection
  (`Billing::AvailableProviders`) — that is the customer-pays-platform flow.
- Per-shopper or per-amount gateway routing rules.
- Gating eligibility on a live Test-connection (eligibility is config-based).
