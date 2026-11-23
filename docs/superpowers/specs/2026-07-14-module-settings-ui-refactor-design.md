# Platform Module Settings — UI/UX Refactor

**Date:** 2026-07-14
**Scope:** UI/UX-only refactor of the platform owner's Module Settings surface
(`/:cid/admin/maintenance/platform/module_settings`) and the pages it links out to.
No schema, controller-logic, or route changes — this is a view/ViewComponent-layer
refactor in the spirit of the app's existing design tokens (`card`, `section-header`,
`text-body-sm`, `input-field`, `BadgeComponent`, `AlertComponent`, `ModuleToggleComponent`).
**Status:** Design — implementation in progress on `worktree-refactor-module-settings-ui`
(no auto-commit; manual review).

## 1. Goal

The Maintenance / Platform / Module Settings area is where the platform owner (customer
`81721200`) configures every feature module across the whole platform. The show page
(`module_settings/show.html.erb`) has grown into a single-column stack of ~9-10 full-width
cards — Module Info, three near-identical single-toggle cards (Status/Required/Handoff),
module-specific config links, a Models table, a Routes table, the Integration Contract, and
a Configuration Schema form — forcing heavy scrolling and burying the actual owner-facing
controls under developer-facing reference tables. This refactor reorganizes the page around
what the owner actually does (flip a setting, tune a default) versus what they occasionally
consult (technical reference), tightens the redundant toggle cards into one compact control
panel, and fixes an unpolished config-schema form that renders every field — including
booleans — as a plain text input.

## 2. Pain points addressed

| # | Pain point | Fix |
|---|-----------|-----|
| 1 | Long single-column scroll mixing owner controls with developer reference tables | Tabbed layout: **Settings** (default) vs **Technical Reference** |
| 2 | Status / Required / Handoff are each a full card (header + body) for one boolean | Single **Module Controls** card, 3 compact rows, same `ModuleToggleComponent` |
| 3 | Config Schema form always renders a text input, even for booleans | Type-aware fields: `boolean` → toggle checkbox, `number` → `number_field`, else → `text_field` |
| 4 | `emails/credential_form_component` hardcodes raw Tailwind grays/blues instead of design tokens | Swap to `text-label`, `border-border-subtle`, `AlertComponent` for the DNS hint |
| 5 | SMS credential form fields aren't grouped, unlike the Email form's fieldset/legend pattern | Add matching fieldset grouping to the SMS credential form |
| 6 | Index page module key is plain inline text; no at-a-glance summary | Add a small stat strip (total / active / required) + monospace key pill |

## 3. Show page restructure

### 3.1 Header (replaces the standalone "Module Info" card)
Icon + module name + key pill (`text-mono` badge) + version + Required/Active badges live
directly under the breadcrumb, in the existing `<h1>` block. The three `<dl>` facts (key,
version, status) that used to justify a whole card are absorbed into this header row — no
information is dropped, just de-nested from its own card.

### 3.2 Module Controls card (replaces 3 toggle cards)
One `card` with a `divide-y` list of 3 rows, each: label + one-line hint on the left,
`ModuleToggleComponent` on the right (component itself is unchanged — only the
surrounding markup collapses from 3 cards to 3 rows). Disabled/confirm/mandatory-lock
semantics are unchanged (`status_active`, `required`, `handoff_enabled` — same params, same
controller).

### 3.3 Tabs (`tabs_controller.js` — already in the codebase, currently unused)
Two tabs, `role="tablist"` semantics, first tab active by default:

- **Settings** (default): module-specific config links (SMS/Email/Payment sections, unchanged
  content), the entry/exit summary from the Integration Contract, and the Configuration
  Schema form.
- **Technical Reference**: Models table, Routes table, and the full Integration Contract
  input/output field tables (currently inside `ModuleHandoffComponent`).

`ModuleHandoffComponent` itself is not split or modified — the whole rendered component
(entry/exit summary plus the input/output field tables) moves under Technical Reference as
one unit. The Settings tab does not duplicate the entry/exit summary; it stays solely on
Technical Reference alongside the rest of the Integration Contract.

### 3.4 Configuration Schema form — type-aware fields
Schema types actually in use today (`FeatureModules::Authentication::Registration.configuration_schema`):
`"boolean"` and `"number"`. Rendering:
- `"boolean"` → a checkbox styled as a toggle (using the same track/knob visual language as
  `ModuleToggleComponent`, but as a plain form checkbox since this is a multi-field batch
  form with one submit button, not a self-submitting single toggle) **plus** a
  `hidden_field_tag` of the same name before it so an unchecked box still submits `"0"`
  (required — `ModuleSettingsController#apply_config_defaults!` reads `permitted.fetch(key, ...)`
  and a checkbox with nothing checked omits the key entirely without the hidden field).
- `"number"` → `number_field_tag`.
- anything else (future-proofing, no current schema uses it) → `text_field_tag` (today's
  behavior, kept as the fallback).

No controller change needed — `apply_config_defaults!` already permits by schema key
generically.

## 4. Index page
Add a stat strip between the header and the list: `"N modules · N active · N required"`,
computed inline from `@available_modules` (no new controller code — three `.count`/`.select`
calls in the view, consistent with how simple this page already is). Module key badge
changes from plain `<span>` text to the same `text-mono ... bg-surface-active` pill style
used elsewhere on the show page, for visual consistency between index and show.

## 5. Sub-pages
- `Admin::Maintenance::Platform::Emails::CredentialFormComponent` (`credential_form_component.html.erb`):
  replace hardcoded `text-gray-700`, `border-gray-200`, `bg-blue-50 border-blue-200
  text-blue-800/900` with the app's tokens (`text-label`/`section-header` styling for
  `<legend>`, `border-border-subtle`, and the DNS TXT hint box becomes an `AlertComponent`
  with `type: :info` instead of a hand-rolled blue box).
- `Admin::Maintenance::Platform::Sms::CredentialFormComponent` (`sms/credential_form_component.html.erb`):
  wrap the provider-specific config fields in a `<fieldset>`/`<legend>` matching the Email
  form's pattern, for visual parity between the two credential forms.
- SMS template form, payment gateway list, both credential/template index pages: no
  structural changes — they already use `AdminPageComponent` + `AdminTableComponent` and
  design tokens consistently.

## 6. Non-goals

- No new database columns, migrations, routes, or controller actions.
- No change to `ModuleSettingsController` update logic beyond what type-aware form fields
  already require submitting (still same param shape: `config_defaults[key]`).
- No new Stimulus controller — `tabs_controller.js` already exists and is unused.
- No visual redesign of `ModuleToggleComponent`, `BadgeComponent`, `AlertComponent`,
  `ModuleHandoffComponent`, or `AdminTableComponent` — reused as-is.
- Payment gateway list keeps its current per-row toggle presentation (already compact).

## 7. Testing

- Component specs: `Admin::Maintenance::Platform::Emails::CredentialFormComponent` and
  `Sms::CredentialFormComponent` render specs updated for the new markup (still assert
  field presence/values, not exact classes).
- Request/view coverage for `module_settings#show`: tab markup present, both tabs render
  their expected content (can assert via presence in the raw response body since JS-driven
  visibility uses `hidden` class rather than server-side omission), config schema form
  submits a boolean field correctly when unchecked (`"0"` reaches `apply_config_defaults!`).
- Manual verification in-browser (dev server, `SKIP_AUTH=1`) of: tab switching, all 3
  module controls toggle correctly, config schema save round-trip (check a box off, save,
  confirm default persisted as `false`), index stat strip counts match seeded data.
- JS: `tabs_controller.js` already has a Vitest spec (`spec/javascript/controllers/tabs_controller.test.js`)
  at 100% coverage; the file itself is not modified by this refactor, so no new JS test work
  is required — only wiring it into the show page's markup.
