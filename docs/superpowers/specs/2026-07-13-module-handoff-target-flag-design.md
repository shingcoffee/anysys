# Per-Module "Handoff Target" Flag — Design

**Date:** 2026-07-13
**Status:** Approved, ready for implementation planning

## Problem

Today, every module that a customer has enabled is offered as a handoff
destination in the page-builder's "hand off to module" picker
(`Pages::HandoffSettingsComponent#enabled_modules`). There is no way for the
platform owner to say "this module may NOT be handed off to." We need a
per-module flag, togglable **only by the platform owner**, that governs whether
a module may be a **handoff target** — i.e. whether another resource (a Page,
etc.) may hand control *to* it after submit.

## Decisions (from brainstorming)

- **Flag meaning:** the module is a handoff **target**. When OFF, no resource
  may hand off to it and it disappears from the page-builder picker.
- **Scope & default:** the flag exists on **all** modules and defaults **OFF**
  (fail-safe) — the owner must explicitly opt each module into being a target.
- **Enforcement:** **picker + runtime**. The picker hides non-handoffable
  modules AND the runtime invocation short-circuits if the target module is not
  handoff-enabled, so a stale saved page config cannot bypass the gate.
- **Direction:** target only. The module *initiating* a handoff out
  (`default_exit` / exit target) is unaffected.
- **Tenancy:** platform-global. No per-customer override.

## Architecture

The flag reuses the exact pattern the existing `status` / `required` toggles
already use — `FeatureModules::Module` is an owner-managed, global (no
`customer_id`) table, edited only in **Maintenance / Platform / Module
Settings**, which is already owner-only (customer `81721200`). No new
authorization surface is introduced.

### 1. Data

Migration adds one column to `feature_modules`:

- `handoff_enabled` — `boolean, default: false, null: false`

No index needed (the table is tiny; queries already join/filter on
`status`). Fail-safe default OFF.

### 2. Model — `FeatureModules::Module`

- `handoff_enabled` is a plain boolean attribute (no enum).
- Add scope: `scope :handoff_enabled, -> { where(handoff_enabled: true) }`.
- No hard validation coupling to `status`; instead the controller clears the
  flag when a module is deactivated (see §3), mirroring how `required` is
  cleared. Rationale: a platform-inactive module can never be a live target
  anyway (the runtime `enabled_for?` check already fails), so keeping the flag
  set on an inactive module would only be a confusing UI state.

### 3. Platform owner toggle — `Admin::Maintenance::Platform::ModuleSettingsController#update`

Add a guard alongside the existing `apply_status!` / `apply_required!`:

```ruby
apply_status!         if params.key?(:status_active)
apply_required!       if params.key?(:required)
apply_handoff_enabled! if params.key?(:handoff_enabled)   # NEW
```

```ruby
def apply_handoff_enabled!
  @feature_module.update!(handoff_enabled: params[:handoff_enabled] == "1")
end
```

And in `apply_status!`, when a module is deactivated, also clear the flag
(same block that already sets `required = false`):

```ruby
attrs[:required]        = false unless active
attrs[:handoff_enabled] = false unless active   # NEW
```

- "Only platform owner can toggle" is enforced by the existing owner-only route
  authorization on this controller — no additional guard required.
- The switch is rendered on the module settings **show** page next to the
  Active / Required toggles.

### 4. Picker enforcement — `Pages::HandoffSettingsComponent#enabled_modules`

Add one clause to the existing query:

```ruby
FeatureModules::Module
  .where(handoff_enabled: true)                       # NEW
  .joins(:customer_feature_modules)
  .where(customer_feature_modules: { customer_id: Current.customer&.id, status: :active })
  .order(:name).distinct
```

A module that isn't handoff-enabled never appears in the "hand off to module"
picker.

### 5. Runtime enforcement — `FeatureModules::Invocation.begin!`

Right after the module is found (`invocation.rb`, before the `enabled_for?`
check):

```ruby
unless feature_module.handoff_enabled?
  raise ModuleNotEnabled,
        I18n.t("feature_modules.errors.handoff_disabled", module_name: feature_module.name)
end
```

Short-circuits any already-saved handoff whose target module the owner has since
switched OFF. Reuses the existing `ModuleNotEnabled` error class (already caught
and rendered by the page flow) with a new distinct i18n message key.

### 6. i18n (en + zh-CN, both locale files, keys in parity)

- Toggle label + hint on the show page:
  `maint_platform.module_settings.handoff_enabled.{label,hint}`.
- Flag-change flash reuses the existing
  `maint_platform.flash.module_settings.updated`.
- New runtime error: `feature_modules.errors.handoff_disabled`
  (interpolates `module_name`).

### 7. Tests

- **Model spec**: `handoff_enabled` defaults to `false`; the `handoff_enabled`
  scope returns only flagged rows.
- **Request/controller spec**: owner can flip the flag; deactivating a module
  clears `handoff_enabled`; a non-owner (admin) is blocked by the existing
  owner-only guard on the module-settings route.
- **Component spec** (`Pages::HandoffSettingsComponent`): a customer-enabled but
  non-handoffable module is excluded from the picker; a handoff-enabled one is
  included.
- **Invocation spec**: `begin!` raises `ModuleNotEnabled` (handoff_disabled
  message) when the target module has `handoff_enabled = false`, even when the
  module is customer-enabled.

## Out of scope

- No per-customer override — the flag is platform-global.
- No customer-facing Settings/Modules UI — owner-only.
- No change to the module *initiating* a handoff out (exit target / default
  exit) — target direction only.
