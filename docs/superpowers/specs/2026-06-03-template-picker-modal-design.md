# Template Picker Modal — Design Spec

**Date:** 2026-06-03
**Status:** Approved for planning

## Problem

When creating or editing an Entity, the "Referenced Template" section renders **every
industry-filtered `PageBuilder::TemplateCardComponent` inline at page load**. Each card is a
~187-line ERB partial that draws a mini-form preview, and there can be 100+ of them. The same
eager-render pattern exists in the Page builder's "New Page" form (`pages/new.html.erb`), which
renders `PageLayoutTemplates.all` inline.

This makes both forms heavy to render and ship a large DOM the user may never interact with.

## Goal

Redesign template selection on **both** surfaces (entity create/edit and page builder "New
Page") into a **trigger + modal**, and **load the template cards only when the modal first
opens** (lazy load). The page builder's `_editor.html.erb` is **out of scope** — it uses a
separate `template-applier` controller, not `template-selector`.

## Decisions (from brainstorming)

1. **Selection flow:** Clicking a card inside the modal sets a *pending* highlight only. A
   footer **"Use Template"** button commits the selection and closes the modal. (Avoids
   accidental destructive overwrites.)
2. **Scope:** Both the entity form **and** the page builder adopt the modal + lazy-load. The
   shared `template-selector` Stimulus controller becomes a single modal code path.
3. **Overwrite protection (entity form only):** When editing an entity that already has
   attributes, committing a *different* template shows a styled confirmation before
   wiping/repopulating. Page builder is unaffected (new page has no attributes).

## Architecture

### Unit 1 — Lazy-load endpoint

`Admin::Maintenance::TemplatePickerCardsController#show`

- **Route:** `GET /:customer_id/admin/maintenance/template_picker_cards` → admin URL category;
  guarded by the admin-or-owner `before_action`; tenant-scoped via `current_customer`.
- **Params:**
  - `scope` — `"industry"` (default, entity form) →
    `PageLayoutTemplates.for_industry(current_customer&.industry)`; `"all"` (page builder) →
    `PageLayoutTemplates.all`.
  - `selected` (optional) — template key to mark as selected in the rendered cards.
- Renders `shared/_template_picker_grid` with `layout: false`. Mirrors the existing
  `Admin::Maintenance::Platform::IndustryTemplateCardsController#show` precedent.

### Unit 2 — Cards partial

`app/views/shared/_template_picker_grid.html.erb`

- Renders only the card grid: `<div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4
  gap-3 …">` containing one `PageBuilder::TemplateCardComponent` per template, plus the
  "no results" empty node.
- Locals: `templates:`, `selected_key:`, `controller_name:` (default `"template-selector"`).
- This is the only heavy payload, and it is now deferred to first modal open.

### Unit 3 — Reusable modal ViewComponent

`PageBuilder::TemplatePickerComponent` (`.rb` + `.html.erb`)

Renders three deduplicated pieces, used by both surfaces:

- **Trigger area** (server-rendered, cheap):
  - No selection → dashed placeholder with icon + "Choose Template" button.
  - Selected → compact summary (template name, category + theme badge) + "Change" and "Clear"
    buttons.
- **Picker modal shell:**
  - Search input (`searchInput` / `searchClear` targets).
  - Category tabs via `shared/category_tabs` — **rendered statically** (counts are cheap to
    compute and don't require rendering cards).
  - Empty grid container (`templateContainer` target) + a loading spinner (`loadingState`
    target) shown until cards arrive; an error state for fetch failures.
  - `searchResultsCount` / `noResults` nodes.
  - Footer: Cancel button + **"Use Template"** confirm button (`confirmBtn` target).
- **Preview zoom modal** — moved here once, replacing the copy-pasted markup in both views.

**Params:** `selected_template:` (hash or nil), `category_counts:`, `cards_url:`,
`field_name:`, `field_value:`, `field_data:` (hash — handles the entity form's full-JSON value
+ `data-template-key` attribute vs. the page builder's plain-key hidden field),
`confirm_label:` (default `"Use Template"`), `controller_name:`.

The hidden field carries `data-template-selector-target="selectedTemplate"` as today.

### Unit 4 — Refactored `template-selector` Stimulus controller

Single modal code path (both surfaces). Cards no longer exist at `connect()`.

- **New value:** `cardsUrl: String`.
- **New targets:** `pickerModal`, `triggerSummary`, `loadingState`, `confirmBtn` (in addition
  to existing).
- `connect()` — read the selected key from the hidden field's value / `data-template-key`
  (not from cards, which aren't rendered yet); set `pendingKey = selectedKey`.
- `openModal()` — reveal `pickerModal`; if `!this.loaded`, call `loadTemplates()`.
- `loadTemplates()` — fetch `cardsUrlValue`; inject HTML into `templateContainerTarget`; set
  `this.loaded = true`; hide loading state; then `updateCardStates()` + `applyFilters()` to
  reflect current selection/filters. Show error state on failure.
- `selectTemplate(event)` — set `this.pendingKey` and highlight the pending card only (no
  commit, no event dispatch).
- `confirmSelection()` — commit: `selectedKey = pendingKey`; write hidden field; update theme
  if applicable; `dispatch("templateSelected", { detail: { key } })`; close modal; refresh
  trigger summary. (No pending selection → confirm is a no-op / disabled.)
- `closeModal()` — hide modal; reset `pendingKey` back to committed `selectedKey`.
- `clearTemplate()` — clear hidden field; `dispatch("templateCleared")`; refresh trigger to
  empty state.
- **Retained unchanged:** `searchTemplates`, `clearSearch`, `filterCategory`, `toggleGroup`,
  `applyFilters`, `updateCategoryTabs`, `updateCardStates`, preview-modal methods, theme-selector
  methods, `entityChanged`/`autoSelectTemplate` (page builder entity-binding auto-select still
  works — it opens/loads then commits programmatically).

### Unit 5 — Entity overwrite confirmation

`entity-form#handleTemplateSelected`

- Before `populateAttributesFromTemplate`, if existing attribute rows exist **and** the new key
  differs from the current `entity[referenced_template]` key, show a styled Tailwind
  confirmation: "This will replace your N existing attribute(s). Continue?"
- Cancel aborts the repopulation (and reverts the picker selection to the prior committed key).
- Implemented with Tailwind + Stimulus only (no native `confirm()`), consistent with the
  existing entity-form modal patterns.

## Data flow

1. Page load → trigger renders current selection; **modal grid is empty (zero cards rendered).**
2. User clicks "Choose"/"Change" → `openModal()`.
3. First open → `loadTemplates()` fetches cards, injects, applies selection + filters.
4. User searches / filters / clicks a card → pending highlight.
5. "Use Template" → `confirmSelection()` commits hidden field, dispatches `templateSelected`,
   closes modal, updates trigger summary.
6. Entity form: `handleTemplateSelected` fetches `template_fields`, confirms overwrite if
   needed, repopulates attributes. Page builder: theme selector reveals; `layout_template`
   hidden field holds the key for page creation.

## Files

**New**
- `app/controllers/admin/maintenance/template_picker_cards_controller.rb`
- `app/views/shared/_template_picker_grid.html.erb`
- `app/components/page_builder/template_picker_component.rb`
- `app/components/page_builder/template_picker_component.html.erb`
- Route entry in `config/routes.rb`
- `spec/requests/admin/maintenance/template_picker_cards_spec.rb` (auth guard, tenant scoping,
  `scope` param behavior, renders cards)
- `spec/components/page_builder/template_picker_component_spec.rb` (trigger states, modal shell,
  field config for both modes)
- Optional system spec for open → lazy load → confirm flow.

**Modified**
- `app/views/admin/maintenance/entities/_form.html.erb` — replace inline section with
  `TemplatePickerComponent` (scope `"industry"`, entity field config).
- `app/views/admin/maintenance/pages/new.html.erb` — replace inline grid + preview modal with
  `TemplatePickerComponent` (scope `"all"`, page field config); keep the theme selector in the
  page, revealed after selection.
- `app/javascript/controllers/template_selector_controller.js` — modal + lazy load + pending /
  confirm.
- `app/javascript/controllers/entity_form_controller.js` — overwrite confirmation.

**Out of scope**
- `app/views/admin/maintenance/pages/_editor.html.erb` — uses the separate `template-applier`
  controller, untouched.

## UX

Mockups / layout for the trigger area, modal shell, loading state, and overwrite confirmation
are produced via the **frontend-design plugin** (through the `anysys-ux-designer`) as a
build-phase task, then implemented by `anysys-frontend-developer`.

## Testing

- Request spec: endpoint authorization (admin/owner only), tenant scoping, `scope=industry` vs
  `scope=all`, renders expected card count.
- Component spec: trigger empty vs selected states, modal shell presence, hidden-field config
  for entity vs page modes.
- Targeted JS-adjacent system spec (optional): modal opens, cards lazy-load on first open,
  pending → confirm commits, overwrite confirmation in edit mode.
- Per AGENTS.md scoping: run the touched layers' specs (component + request + entity request
  specs), not the full suite, unless the auth/tenant changes warrant broader coverage.
