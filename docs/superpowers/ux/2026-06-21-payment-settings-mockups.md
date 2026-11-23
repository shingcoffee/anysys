# Payment Settings — UI/UX Mockups
**Date:** 2026-06-21
**Feature:** Refactored Admin Payment Settings — Gateway Gallery + Per-Gateway Config
**Nav area:** Settings / Payments (`/:cid/admin/settings/modules/payments/`)
**Audience:** admin, owner

---

## 1. Surface Inventory

| # | Surface | URL pattern | Nav area |
|---|---------|-------------|----------|
| A | Gateway Gallery (index) | `/:cid/admin/settings/modules/payments/` | Settings / Payments |
| B | Gateway Config (per-gateway) | `/:cid/admin/settings/modules/payments/:provider` | Settings / Payments |

Both surfaces share the existing `AdminPageComponent` shell (breadcrumbs + title strip + flash alerts).

---

## 2. Status Semantics Legend

Before the mockups, the three gateway states and their visual treatment:

```
STATE          BADGE CLASS        BADGE LABEL       TILE APPEARANCE
─────────────────────────────────────────────────────────────────────
needs_setup    badge-warning      Needs setup       Muted border, warm tint
active         badge-success      Active            Normal border, no tint
disabled       badge-default      Disabled          Muted border + 40% opacity on icon
```

Transition rules:
- Needs setup → Active: Admin fills all required credential fields and saves. Status auto-derives from credential completeness (backend concern; the frontend just renders what is passed).
- Active → Disabled: Admin flips the enable/disable toggle to OFF.
- Disabled → Active: Admin flips toggle to ON (requires credentials already present).
- Active → Needs setup: Admin clears a required credential field (edge case; backend marks incomplete).

---

## 3. Surface A — Gateway Gallery

### 3.1 URL
`GET /:cid/admin/settings/modules/payments/`

### 3.2 Desktop Layout (≥ 1024px)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ BreadcrumbsComponent                                                         │
│   Settings > Payments                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ AdminPageComponent title strip                                               │
│  title:       "Payment Gateways"                                             │
│  description: "Manage the payment providers available to your customers."    │
│  actions:     (none — gateways are auto-seeded; no "New" button)            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐           │
│  │  GatewayCardComponent (Stripe)          │  │ (WeChat Pay)     │           │
│  │ ┌──────────────────────────────────┐   │  │                  │           │
│  │ │ [LOGO/ICON 40×40]                │   │  │                  │           │
│  │ │ Stripe                           │   │  │                  │           │
│  │ │ ● Active          [badge-success]│   │  │                  │           │
│  │ ├──────────────────────────────────┤   │  │                  │           │
│  │ │ [Cards] [Wallets]  (chips)       │   │  │                  │           │
│  │ ├──────────────────────────────────┤   │  │                  │           │
│  │ │ Mode: Sandbox                    │   │  │                  │           │
│  │ ├──────────────────────────────────┤   │  │                  │           │
│  │ │ [Toggle OFF●───────○] Enabled    │   │  │                  │           │
│  │ ├──────────────────────────────────┤   │  │                  │           │
│  │ │              [Configure →]       │   │  │                  │           │
│  │ └──────────────────────────────────┘   │  │                  │           │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘           │
│                                                                              │
│  ┌──────────────────┐  ┌──────────────────┐                                 │
│  │  (Alipay)        │  │ (WeChat Pay H5)  │                                 │
│  └──────────────────┘  └──────────────────┘                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

Grid: `grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3` — 1-up on mobile, 2-up on tablet, 3-up on desktop.

### 3.3 Single GatewayCardComponent — Detailed Anatomy

```
┌─────────────────────────────────────────────────────┐
│  card p-5 flex flex-col gap-4                       │
│                                                     │
│  ── Header row ─────────────────────────────────── │
│  ┌──────────┐  Stripe                               │
│  │ [LOGO]   │  text-text-primary text-lg font-semi │
│  │ 40×40 px │                                       │
│  └──────────┘  ● Active            [badge-success] │
│                                                     │
│  ── Capability chips ──────────────────────────── │
│  [Cards]  [Wallets]  [QR]                           │
│  each: badge-default text-2xs px-1.5 py-0.5         │
│                                                     │
│  ── Mode row ───────────────────────────────────── │
│  text-body-sm text-text-secondary                   │
│  Mode:  [Sandbox]    ← badge-warning if Sandbox,    │
│                         badge-success if Production │
│                                                     │
│  ── Divider ────────────────────────────────────── │
│  border-t border-border-subtle                      │
│                                                     │
│  ── Footer row (actions) ───────────────────────── │
│  [Toggle] Enabled         [Configure →]            │
│  toggle left              btn btn-secondary text-sm │
└─────────────────────────────────────────────────────┘
```

**Empty / Needs-Setup state tile variant:**

```
┌─────────────────────────────────────────────────────┐
│  card p-5  bg-warning-subtle/30  border-warning/30  │
│  (same structure as above)                          │
│  ● Needs setup        [badge-warning]               │
│  chips and mode still shown (from gateway.rb metadata)│
│  [Toggle] Disabled (toggle is OFF; grayed)          │
│  [Configure →]  ← link is still active             │
└─────────────────────────────────────────────────────┘
```

Note: the toggle is disabled (pointer-events-none opacity-50) when status is `needs_setup` — the admin must configure credentials first before enabling.

### 3.4 Tablet Layout (640px – 1023px)

Same grid but 2-column: `sm:grid-cols-2`. Cards stack taller. Typography unchanged.

### 3.5 Mobile Layout (< 640px)

Single column. Cards render full-width. The header row (logo + name + badge) collapses to a single flex row wrapping at 2 lines if name is long. Capability chips wrap naturally. Footer row stays on one line (space-between).

### 3.6 Empty State (no gateways registered at all)

Shown only if `Payments::Gateways.all` returns nothing — should not happen in production since gateways are file-registered, but shown here for completeness.

```
┌─────────────────────────────────────────────────────┐
│  card p-12 text-center                              │
│                                                     │
│  [icon: credit-card, 48px, text-text-muted]         │
│                                                     │
│  No payment gateways available                      │
│  text-text-secondary text-body-sm mt-2              │
│  Contact the platform owner to enable gateways.    │
└─────────────────────────────────────────────────────┘
```

### 3.7 Data Mapping

| Visual element | Backend field |
|----------------|---------------|
| Gateway logo/name | `Payments::Gateways::Base.display_name`, `key` |
| Status badge | `Payments::MerchantAccount#status` (`"active"` / `"inactive"`) mapped to `active`/`needs_setup`/`disabled` |
| Capability chips | `Payments::Gateways::Base.supported_flows` (`:qr`, `:h5`, `:jsapi`) mapped to display labels |
| Mode badge | `Payments::MerchantAccount#mode` (`"sandbox"` / `"production"`) |
| Toggle state | `Payments::MerchantAccount#status == "active"` |
| Configure link | `admin_settings_modules_payments_path(cid, provider: gateway.key)` |

---

## 4. Surface B — Gateway Config Page

### 4.1 URL
`GET /:cid/admin/settings/modules/payments/:provider`
`PATCH /:cid/admin/settings/modules/payments/:provider`

### 4.2 Desktop Layout (≥ 1024px)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ BreadcrumbsComponent                                                         │
│   Settings > Payments > Stripe                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│ AdminPageComponent title strip                                               │
│  title:       "Stripe"                                                       │
│  description: "Configure credentials and options for Stripe."               │
│  actions:     StatusBadgeComponent (Active) — rendered inline in title area │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────┐           │
│  │  card p-6 max-w-3xl                   GatewayConfigComponent │           │
│  │                                                               │           │
│  │  ── Environment switcher ─────────────────────────────────── │           │
│  │  [Sandbox]  [Production]                                      │           │
│  │  tabs-style segmented control, btn-group                     │           │
│  │  active tab: bg-accent text-white                            │           │
│  │  inactive:   btn-secondary                                    │           │
│  │                                                               │           │
│  │  ── Status toggle row ─────────────────────────────────────── │           │
│  │  ┌──────────────────────────────────────────────────────────┐ │           │
│  │  │ Gateway status                                            │ │           │
│  │  │ text-body-sm text-text-secondary                         │ │           │
│  │  │                          [Toggle] Enabled                │ │           │
│  │  └──────────────────────────────────────────────────────────┘ │           │
│  │  bg-canvas-elevated rounded-lg px-4 py-3 mb-6                │           │
│  │                                                               │           │
│  │  ── Credential fields ─────────────────────────────────────── │           │
│  │  CredentialFieldsComponent — see §4.4 for detail             │           │
│  │                                                               │           │
│  │  ── Static fields ─────────────────────────────────────────── │           │
│  │  Merchant ID      [text input]                               │           │
│  │  Notify URL override  [text input, placeholder auto-url]     │           │
│  │  Default currency  [select: CNY / USD / EUR / ...]           │           │
│  │                                                               │           │
│  │  ── Test connection ───────────────────────────────────────── │           │
│  │  [Test connection]  ← btn btn-secondary                      │           │
│  │  ┌─────────────────────────────────────────────────────────┐ │           │
│  │  │ (inline result area — hidden until test fires)          │ │           │
│  │  │ SUCCESS: "Connection verified · 2026-06-21 14:32 UTC"   │ │           │
│  │  │ ERROR:   "Invalid API key — check Secret Key above"     │ │           │
│  │  └─────────────────────────────────────────────────────────┘ │           │
│  │                                                               │           │
│  │  ── Form actions ──────────────────────────────────────────── │           │
│  │                      [Cancel]  [Save changes]                │           │
│  │                      btn-secondary  btn-primary              │           │
│  └───────────────────────────────────────────────────────────────┘           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Environment Switcher (Stimulus-driven)

The environment switcher is a segmented button group that switches which `MerchantAccount` row (sandbox vs production) is being edited. It is NOT a tab that hides/shows credential fields — it triggers a page reload (or a Turbo Frame reload) to fetch the correct record for the selected mode.

```html
<!-- Tailwind-annotated markup sample (no custom CSS) -->
<div class="inline-flex rounded-md border border-border overflow-hidden" 
     data-controller="gateway-env-switcher"
     data-gateway-env-switcher-current-value="sandbox">

  <button type="button"
          class="btn btn-sm px-4 py-2 rounded-none border-r border-border
                 data-[active]:bg-accent data-[active]:text-white
                 data-[active]:border-accent"
          data-gateway-env-switcher-target="tab"
          data-mode="sandbox"
          data-action="click->gateway-env-switcher#switch">
    Sandbox
  </button>

  <button type="button"
          class="btn btn-sm px-4 py-2 rounded-none
                 data-[active]:bg-accent data-[active]:text-white
                 data-[active]:border-accent"
          data-gateway-env-switcher-target="tab"
          data-mode="production"
          data-action="click->gateway-env-switcher#switch">
    Production
  </button>

</div>
```

On click, the controller updates the hidden `mode` field in the form (or navigates via Turbo Frame to `?mode=production`). The active tab has `bg-accent text-white`; the inactive tab is `bg-surface text-text-secondary`.

### 4.4 CredentialFieldsComponent — Detailed Anatomy

Each gateway's `credential_fields` array drives the rendered fields. Three field type variants:

**String field:**
```
┌───────────────────────────────────────────────────────┐
│ form-label                                            │
│ Publishable Key                                       │
│ [text input — input-field]                           │
│  pk_live_xxxxxxxx                                     │
└───────────────────────────────────────────────────────┘
```

**Password field (encrypted secret — existing record):**
```
┌───────────────────────────────────────────────────────┐
│ form-label flex items-center gap-1.5                  │
│ Secret Key  [lock icon 12px text-text-muted]         │
│ [password input — input-field]                       │
│  placeholder: "••••••••  Leave blank to keep"        │
│ text-caption text-text-muted mt-1                    │
│ "Leave blank to keep the existing encrypted value."  │
└───────────────────────────────────────────────────────┘
```

The lock icon (SVG inline, 12px) visually signals that this field is encrypted at rest. The "Leave blank to keep" hint appears ONLY when `account.persisted?` (edit mode). On the new/create form it does not appear.

**Textarea field (e.g. PEM certificate):**
```
┌───────────────────────────────────────────────────────┐
│ form-label                                            │
│ RSA Private Key (PEM)                                 │
│ [textarea 6 rows — input-field font-mono text-xs]    │
│  -----BEGIN RSA PRIVATE KEY-----                      │
│  xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx                      │
│  -----END RSA PRIVATE KEY-----                        │
└───────────────────────────────────────────────────────┘
```

PEM/certificate textareas use `font-mono text-xs` for readability.

### 4.5 Stripe Variant (Western-gateway layout)

Stripe registers: `secret_key` (password), `publishable_key` (string), `webhook_signing_secret` (password).

```
┌──────────────────────────────────────────────────────────────────┐
│  GatewayConfigComponent — Stripe / Sandbox                      │
│                                                                  │
│  [Sandbox ●]  [ Production ]   ← env switcher                   │
│                                                                  │
│  ── Status ─────────────────────────────────────────────────── │
│  Gateway enabled      [●───] ON                                 │
│                                                                  │
│  ── Credentials ────────────────────────────────────────────── │
│  Secret Key *                                                    │
│  [password field]  ●●●●●●●●  Leave blank to keep               │
│  (lock icon)                                                     │
│                                                                  │
│  Publishable Key *                                               │
│  [text field]  pk_test_xxxxxxxxxxxxxxxx                         │
│                                                                  │
│  Webhook Signing Secret *                                        │
│  [password field]  ●●●●●●●●  Leave blank to keep               │
│  (lock icon)                                                     │
│                                                                  │
│  ── Static fields ──────────────────────────────────────────── │
│  Merchant ID                                                     │
│  [text field]  acct_xxxxxxxxx                                   │
│                                                                  │
│  Notify URL override                                             │
│  [text field]  placeholder: auto-generated URL shown as hint    │
│                                                                  │
│  Default currency                                                │
│  [select]  USD ▼                                                │
│                                                                  │
│  ── Test connection ────────────────────────────────────────── │
│  [Test connection]                                               │
│  (result area hidden)                                            │
│                                                                  │
│                                     [Cancel]  [Save changes]   │
└──────────────────────────────────────────────────────────────────┘
```

### 4.6 China-Gateway Variant (WeChat Pay)

WeChat Pay registers: `app_id` (string), `mch_id` (string), `api_key` (password), `apiclient_cert` (text/PEM), `apiclient_key` (text/PEM).

```
┌──────────────────────────────────────────────────────────────────┐
│  GatewayConfigComponent — WeChat Pay / Production               │
│                                                                  │
│  [ Sandbox ]  [Production ●]   ← env switcher                  │
│                                                                  │
│  ── Status ─────────────────────────────────────────────────── │
│  Gateway enabled      [●───] ON                                 │
│                                                                  │
│  ── Credentials ────────────────────────────────────────────── │
│  App ID                                                          │
│  [text field]  wx1234567890abcdef                               │
│                                                                  │
│  Merchant ID (MCH ID)                                            │
│  [text field]  1234567890                                        │
│                                                                  │
│  API Key *                                                       │
│  [password field]  ●●●●●●●●  Leave blank to keep               │
│  (lock icon)                                                     │
│                                                                  │
│  API Client Certificate (PEM) *                                  │
│  [textarea 6 rows, font-mono text-xs]                           │
│  -----BEGIN CERTIFICATE-----                                     │
│  ●●●●●●●●●●●●●●●●●●●●●●●●●●                                     │
│  -----END CERTIFICATE-----                                       │
│  Leave blank to keep the existing encrypted value.              │
│                                                                  │
│  API Client Private Key (PEM) *                                  │
│  [textarea 6 rows, font-mono text-xs]                           │
│  (same treatment)                                               │
│                                                                  │
│  ── Static fields ──────────────────────────────────────────── │
│  Merchant ID (override)                                          │
│  [text field]  (usually same as MCH ID above — some use both)  │
│                                                                  │
│  Notify URL override                                             │
│  [text field]  placeholder: auto-generated                      │
│                                                                  │
│  Default currency                                                │
│  [select]  CNY ▼                                                │
│                                                                  │
│  ── Test connection ────────────────────────────────────────── │
│  [Test connection]                                               │
│                                                                  │
│                                     [Cancel]  [Save changes]   │
└──────────────────────────────────────────────────────────────────┘
```

### 4.7 Test Connection — Result States

Stimulus controller (`gateway-config`) fires a non-navigating POST to `/:cid/admin/settings/modules/payments/:provider/test` and replaces the result area via `data-gateway-config-target="result"`.

**Idle (default):**
```
<!-- result area hidden: class="hidden" -->
```

**Loading (in-flight):**
```
┌───────────────────────────────────────────────────────┐
│ bg-canvas-elevated rounded-lg px-4 py-3              │
│ flex items-center gap-2                               │
│ [spinner SVG animated text-text-muted]               │
│ Testing connection…  text-text-secondary text-body-sm│
└───────────────────────────────────────────────────────┘
```

**Success:**
```
┌───────────────────────────────────────────────────────┐
│ bg-success-subtle rounded-lg px-4 py-3 border         │
│ border-success/30                                     │
│ flex items-center gap-2                               │
│ [checkmark SVG text-success 16px]                    │
│ Connection verified                text-success      │
│ Last verified: 2026-06-21 14:32 UTC  text-caption    │
│                                    text-text-secondary│
└───────────────────────────────────────────────────────┘
```

**Error:**
```
┌───────────────────────────────────────────────────────┐
│ bg-danger-subtle rounded-lg px-4 py-3 border          │
│ border-danger/30                                      │
│ flex items-center gap-2 items-start                   │
│ [x-circle SVG text-danger 16px]                      │
│ Connection failed        text-danger font-medium     │
│ Invalid API key (401)    text-body-sm text-text-secon│
└───────────────────────────────────────────────────────┘
```

### 4.8 Mobile Layout (< 640px)

The `max-w-3xl` card goes full-width (the card's `max-w-3xl` class is advisory, not breakpoint-gated). The environment switcher wraps to full width (`w-full`). Each segmented button takes equal space (`flex-1`). Credential fields are single-column already. The form actions footer becomes `flex flex-col-reverse gap-2 w-full` so Save is on top.

### 4.9 Validation Error State

Inline under each invalid field:
```
[field label]
[input — border-danger focus:ring-danger/30]
text-danger text-caption mt-1  "This field is required."
```

Page-level error summary at top via `AlertComponent.new(type: :error)`.

### 4.10 Data Mapping

| Visual element | Backend field |
|----------------|---------------|
| Env switcher active tab | `MerchantAccount#mode` |
| Status toggle | `MerchantAccount#status` |
| Credential fields | `gateway.credential_fields` → `MerchantAccount#credentials` (encrypted JSON) |
| Merchant ID | `MerchantAccount#merchant_id` |
| Notify URL override | `MerchantAccount#notify_url_override` |
| Default currency | `MerchantAccount#default_currency` (new field per plan) |
| "Leave blank" hint | shown when `account.persisted? && field[:encrypted]` |
| Last verified timestamp | `MerchantAccount#last_verified_at` (new field per plan) |

---

## 5. Interaction Flows

### Flow 1: Admin browses gateway gallery and enables a gateway

```
START: /:cid/admin/settings/modules/payments/
  (gallery shown, Stripe tile shows "Needs setup" / toggle OFF)

→ Admin clicks "Configure →" on the Stripe tile
  URL: /:cid/admin/settings/modules/payments/stripe

→ Config page loads: env switcher at "Sandbox" (default mode)
  Status toggle is OFF (gateway disabled)
  All credential fields are empty

→ Admin fills Secret Key, Publishable Key, Webhook Signing Secret
→ Admin clicks [Save changes]
  POST /:cid/admin/settings/modules/payments/stripe (Sandbox)
  Success → page reloads with flash notice "Stripe (Sandbox) saved."
  Status auto-advances to "Active" (backend derives from credential completeness)

→ Admin clicks [Test connection]
  AJAX POST /:cid/admin/settings/modules/payments/stripe/test
  Result area shows spinner, then success/error

→ Admin flips status toggle to ON → PATCH fires (inline via Stimulus)
  Toggle changes to ON; badge re-renders as "Active"

→ Admin clicks breadcrumb "Payments" → back to gallery
  Stripe tile now shows badge-success "Active", toggle ON
```

### Flow 2: Admin switches from Sandbox to Production

```
START: /:cid/admin/settings/modules/payments/stripe (currently showing Sandbox)

→ Admin clicks "Production" tab in env switcher
  Stimulus: gateway-env-switcher fires, updates hidden mode field + triggers Turbo Frame
  URL: /:cid/admin/settings/modules/payments/stripe?mode=production

→ Config page reloads within frame, showing production MerchantAccount row
  All credential fields show "••••••••" placeholders (existing encrypted values)

→ Admin updates Webhook Signing Secret only (other fields blank = keep existing)
→ [Save changes] → PATCH with only the one changed field, others ignored
  Flash: "Stripe (Production) saved."
```

### Flow 3: Admin disables an active gateway

```
START: /:cid/admin/settings/modules/payments/stripe (Status toggle ON / Active)

→ Admin clicks the status toggle to OFF
  Stimulus: gateway-config fires PATCH /:cid/admin/settings/modules/payments/stripe/toggle
  (or inline within the config form — the toggle is inside the form, submit via Stimulus)
  Response updates toggle state; badge re-renders as "Disabled"

→ Admin navigates to gallery → tile shows badge-default "Disabled", opacity-40 on icon
```

### Flow 4: Validation failure

```
→ Admin clicks [Save changes] without filling required fields
  Server returns 422 Unprocessable Entity
  AlertComponent at top: "2 fields require attention."
  Each invalid field shows red border + inline error text
  Page stays at config URL; no navigation
```

### Flow 5: Test connection failure (vendor down)

```
→ Admin clicks [Test connection]
  Spinner shown; AJAX times out (30s)
  Error state shown: "Connection failed — request timed out. Check network settings."
  Gateway status unchanged; admin must investigate manually.
```

---

## 6. Component Reuse Map

### Surface A — Gateway Gallery

| Block | Component | Status |
|-------|-----------|--------|
| Page shell (breadcrumbs + title strip) | `AdminPageComponent` | reused |
| Grid container | `Payments::Admin::GatewayGalleryComponent` | NEW |
| Single tile | `Payments::Admin::GatewayCardComponent` | NEW |
| Status badge (Active/Needs setup/Disabled) | `Payments::Admin::StatusBadgeComponent` | NEW — wraps `BadgeComponent` |
| Capability chip | `BadgeComponent` (variant: :default, size: :sm) | reused |
| Enable/disable toggle | Stimulus only (no separate component) inside `GatewayCardComponent` | NEW (inline) |
| Empty state | inline ERB in `GatewayGalleryComponent` | inline |

### Surface B — Gateway Config Page

| Block | Component | Status |
|-------|-----------|--------|
| Page shell | `AdminPageComponent` | reused |
| Outer config card | `Payments::Admin::GatewayConfigComponent` | NEW |
| Environment switcher | Stimulus controller `gateway-env-switcher` inside `GatewayConfigComponent` | NEW (inline markup) |
| Status toggle row | inline within `GatewayConfigComponent` | inline |
| Dynamic credential fields | `Payments::Admin::CredentialFieldsComponent` | NEW |
| "Leave blank" encrypted hint | inline within `CredentialFieldsComponent` | inline |
| Static fields (merchant_id, notify_url, currency) | inline within `GatewayConfigComponent` | inline |
| Test connection result area | `Payments::Admin::TestConnectionResultComponent` | NEW |
| Alert (validation errors) | `AlertComponent` | reused |
| Form action buttons | `ButtonComponent` | reused |
| Breadcrumbs | `BreadcrumbsComponent` | reused |

---

## 7. Tailwind Token Usage

### Colors
| Purpose | Token |
|---------|-------|
| Card background | `bg-surface` (via `.card` component class) |
| Page background | `bg-canvas` |
| Active badge | `badge-success` (`bg-success-subtle text-success`) |
| Warning/Needs-setup badge | `badge-warning` (`bg-warning-subtle text-warning`) |
| Disabled badge | `badge-default` (`bg-surface-active text-text-secondary`) |
| Sandbox mode badge | `badge-warning` |
| Production mode badge | `badge-success` |
| Active env tab | `bg-accent text-white` |
| Inactive env tab | `bg-surface text-text-secondary border-border` |
| Test result — success | `bg-success-subtle border-success/30 text-success` |
| Test result — error | `bg-danger-subtle border-danger/30 text-danger` |
| Test result — loading | `bg-canvas-elevated text-text-secondary` |
| Invalid field border | `border-danger focus:ring-danger/30` |
| Encrypted-secret hint text | `text-caption text-text-muted` |
| "Needs setup" tile tint | `bg-warning-subtle/30 border-warning/30` |
| "Disabled" tile opacity | `opacity-50` on icon only |

### Typography
| Element | Classes |
|---------|---------|
| Page title | `text-subtitle` (alias for `text-2xl font-semibold`) |
| Gateway name in tile | `text-lg font-semibold text-text-primary` |
| Capability chip label | `text-2xs font-semibold` |
| Mode / secondary metadata | `text-body-sm text-text-secondary` |
| Encrypted hint | `text-caption text-text-muted` |
| Form label | `form-label` (project utility class) |
| Field input | `input-field` (project utility class) |
| PEM textarea | `input-field font-mono text-xs` |

### Spacing
- Card padding: `p-5` (tiles) / `p-6` (config form)
- Grid gap: `gap-4` (tiles) / `gap-6` (config form sections)
- Form fields: `space-y-4` within credential section
- Form actions: `flex items-center justify-end gap-2 pt-4 border-t border-border-subtle`

---

## 8. Stimulus Controller Specs

### `gateway-toggle` (within GatewayCardComponent and GatewayConfigComponent)

Handles the inline enable/disable toggle without a full page reload.

- **Values:** `url` (String — the PATCH endpoint), `currentState` (String — `"active"` | `"inactive"`)
- **Actions:** `toggle` — fires on `change` of the toggle input
- **Behavior:** Fires PATCH with `{ status: "active" | "inactive" }`. On success, updates badge and toggle DOM. On error, reverts toggle and shows flash.
- **Targets:** `toggle` (the `<input type="checkbox">`), `badge` (the `StatusBadgeComponent` element), `statusLabel` (the text next to toggle)

### `gateway-env-switcher` (within GatewayConfigComponent)

Handles Sandbox ↔ Production tab switching.

- **Values:** `currentMode` (String — `"sandbox"` | `"production"`), `basePath` (String)
- **Actions:** `switch` — fires on click of each tab button
- **Behavior:** When a tab is clicked, sets `data-active` attribute on the clicked button (for CSS styling), removes it from the other, then navigates via `Turbo.visit(basePath + "?mode=" + newMode)`.
- **Targets:** `tab` (both tab buttons), `modeInput` (hidden input in form)

### `gateway-config` (within GatewayConfigComponent)

Handles the Test Connection button and its result area.

- **Values:** `testUrl` (String — the test endpoint)
- **Actions:** `testConnection` — fires on click of "Test connection" button
- **Behavior:** Shows loading state in result target. Fires POST to `testUrl`. On response, renders success or error variant in result area. Stores `last_verified_at` timestamp from response.
- **Targets:** `result` (the result display div), `testButton` (disabled during in-flight request), `lastVerified` (optional timestamp span)

---

## 9. Responsive Summary

| Breakpoint | Gallery grid | Config form | Env switcher | Form actions |
|------------|-------------|-------------|--------------|--------------|
| Mobile (< 640px) | 1 column | full-width | full-width, flex-1 buttons | flex-col-reverse |
| Tablet (640–1023px) | 2 columns | full-width | row layout | row (justify-end) |
| Desktop (≥ 1024px) | 3 columns | max-w-3xl centered | row layout | row (justify-end) |

All layouts use Tailwind responsive prefixes: `sm:`, `lg:` only — no custom breakpoints.

---

## RETURN
ux_doc: docs/superpowers/ux/2026-06-21-payment-settings-mockups.md
surfaces:
  - name: Gateway Gallery (index)
    nav_area: Settings
    new_components: [Payments::Admin::GatewayGalleryComponent, Payments::Admin::GatewayCardComponent, Payments::Admin::StatusBadgeComponent]
    reused_components: [AdminPageComponent, BadgeComponent, BreadcrumbsComponent]
  - name: Gateway Config (per-gateway)
    nav_area: Settings
    new_components: [Payments::Admin::GatewayConfigComponent, Payments::Admin::CredentialFieldsComponent, Payments::Admin::TestConnectionResultComponent]
    reused_components: [AdminPageComponent, AlertComponent, ButtonComponent, BreadcrumbsComponent, BadgeComponent]
overall: READY_FOR_FRONTEND
notes: Both surfaces are fully spec'd with ASCII wireframes, responsive breakpoint behavior, Tailwind token mappings, component decomposition, three Stimulus controller contracts (gateway-toggle, gateway-env-switcher, gateway-config), and annotated Stripe and WeChat Pay credential variants. The frontend developer can implement directly without layout guesses. No production code was modified.
