# Module Status/Required Toggles + Platform Payment Tenders + Merged Customer Gateway Settings

Date: 2026-06-22
Status: Approved

## Summary

Three related refactors centered on the platform owner page
`/:cid/admin/maintenance/platform/module_settings` and the customer payment
settings:

- **A.** Every feature module gets two platform-owner toggles — **Status**
  (active/inactive, default **inactive**) and **Required** (only settable when
  active). The **User Authentication** module is the sole exception: it is
  permanently active + required ("mandatory"), with both toggles locked.
- **B.** The platform owner can configure which payment **tenders** (Alipay,
  WeChat Pay, Stripe, future gateways) are available to all customers, from the
  payment module's `show` page on the same `module_settings` surface.
- **C.** The customer payment settings merge the (currently dead) "Gateway"
  sidebar entry into the existing **Merchant Accounts** page — a single surface
  that both enables/disables tenders and configures their credentials.

AGENTS.md note: this is a brand-new application — no backward-compatibility
constraints. The payment single-file rule (new gateway = one file under
`app/services/payments/gateways/`) is preserved by all changes below.

## Part A — Module Status / Required toggles

### Model — `FeatureModules::Module`
- Change `status` enum default from `:active` to **`:inactive`**.
- Add `mandatory?` — delegates to the registration class
  (`registration_class.respond_to?(:mandatory?) && registration_class.mandatory?`).
- **Hard-gate inactive everywhere**: `enabled_for_customer` and `enabled?` must
  additionally require the module's own `status = active`. An inactive module
  stops resolving for every customer even if a `customer_feature_modules` row
  still says `active`. `.available` (= `where(status: :active)`) already gates
  the customer-facing enable page correctly and is unchanged.

### Registration DSL — `FeatureModules::BaseModule`
- Rename `required!` → **`mandatory!`** (semantic: permanently active +
  required, NOT owner-toggleable). Update `required?` accessor to `mandatory?`.
  - `authentication` keeps `mandatory!`.
  - `email` **drops** the declaration → becomes a normal toggleable module
    (default inactive, optional).
- Rewrite `register!` so it stops clobbering owner choices on every boot:
  - **Mandatory module** → always force `status: :active, required: true`.
  - **New record (first registration)** → seed `status: :inactive,
    required: false`.
  - **Existing record** → update metadata only (name, description,
    `configuration_schema`, version); **preserve** the persisted
    `status`/`required` set by the owner.

### Consumers of `required!`
- `config/initializers/feature_modules.rb` and `Customer#enable_required_feature_modules`
  iterate `FeatureModules::Module.required` to auto-provision. These still work:
  mandatory modules carry `required: true` in their row, and any module the owner
  marks required is provisioned by the controller's existing loop.

### Controller — `Admin::Maintenance::Platform::ModuleSettingsController`
- `index`: list **all** modules (`FeatureModules::Module.by_name`), not just
  `.available` — otherwise inactive modules vanish from the page meant to toggle
  them.
- `update`: accept `status` and/or `required` params with guards:
  - Mandatory module → reject (no-op, informative notice).
  - `required = 1` while status inactive → reject.
  - Setting `status = inactive` → also force `required = false`.
  - When `required` flips true, keep the existing provisioning loop over all
    customers. Going inactive does not destructively deprovision customer data —
    it is hard-gated at read time.

### View
- `index.html.erb`: each row shows both a **Status** badge and a **Required**
  badge (Status badge wiring already present).
- `show.html.erb`: add a **Status** toggle card above the existing Required
  card. The Required toggle is **disabled/greyed when status is inactive**.
  Mandatory modules render both toggles locked-on with a "Locked — always
  required" note.
- Extract the duplicated switch markup into a reusable
  **`ModuleToggleComponent`** ViewComponent (Tailwind + optional Stimulus),
  used by both the Status and Required switches and reused in Part B.

## Part B — Platform-wide payment tender availability

### Store — `Payments::PlatformGateway`
- A lightweight model/table `payment_platform_gateways` with `provider` (string,
  unique) and `available` (boolean, **default false**), created on demand via a
  `for_provider(key)` finder (mirrors `Captcha::ProviderSettings.for_provider`).
- No per-vendor migration, no typed columns on `payment_merchant_accounts`.
  Newly-added gateway files auto-appear here and default to **unavailable** until
  the platform owner enables them.

### UI — payment module `show` page
- Render a section listing every registered gateway (`Payments::Gateways.all`)
  with an availability toggle per tender, reusing `ModuleToggleComponent`.
- Toggling PATCHes the platform settings controller (a new nested action/route
  under the platform area, owner-only).

### Customer-side filtering
- The customer gateway gallery and `FeatureModules::Payment::Provisioner` offer
  / seed only tenders where `available = true`. Disabling a tender platform-wide
  hides it from all customers (consistent with the inactive hard-gate).

## Part C — Merge customer Gateway + Merchant Accounts

- Remove the dead **"Gateway"** sidebar settings stub
  (`ModuleContribution.new(label: "Gateway", entry_key: "gateway")` with no
  path) from `FeatureModules::Payment::Registration`.
- Keep the single live settings entry named **"Merchant Accounts"**
  (`/:cid/admin/settings/modules/payments/merchant_accounts`). It continues to
  do both jobs it does today — the gallery (enable/disable + configure via
  `GatewayConfigComponent`) — with the gallery now filtered to
  **platform-available tenders only**.
- No new customer route/controller.

## Authorization & Multi-tenancy
- All `module_settings` and platform-gateway actions live under
  `/:cid/admin/maintenance/platform/...`, owner-only (visible only under
  platform owner customer `81721200`), guarded by the existing
  `RouteAuthorization` admin/owner check plus the platform-owner constraint.
- Customer payment settings remain `admin`-scoped under
  `/:cid/admin/settings/modules/payments/...` with `customer_id` scoping via
  `MerchantAccount.for_current_customer`.

## Testing
- **Model**: status default inactive; `mandatory?`; `register!` preserves
  owner-set status/required on existing rows and seeds inactive on new rows;
  `enabled?`/`enabled_for_customer` hard-gate on module status;
  `PlatformGateway.for_provider` default false + availability filtering.
- **Request**: toggle status; required-requires-active guard; mandatory
  rejection; tender availability toggle; owner-only authorization and
  cross-tenant isolation; customer gallery hides unavailable tenders.
- **Component**: `ModuleToggleComponent` (on/off/disabled/locked states).

## Out of scope
- Per-customer tender overrides or tying availability to billing plans.
- Destructive deprovisioning of customer data when a module/tender goes
  inactive (handled by read-time hard-gating instead).
- Any change to the gateway API surface or checkout flow.
