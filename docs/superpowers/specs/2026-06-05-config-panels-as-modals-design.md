# Page-Editor Config Panels → Centered Modals

**Date:** 2026-06-05
**Surface:** Page editor toolbar (`/:cid/admin/maintenance/pages/:id/edit`) — the five config buttons: Templates, Theme, Rules, Calculations, Settings.

## Problem / Goal

The five toolbar config buttons currently open in three different ways:
- **Templates / Theme / Settings** — full-screen overlay panels (`fixed top-16 left-72 right-0 bottom-0`).
- **Rules / Calculations** — right-docked slide-over drawers (`BuilderDrawerComponent`, added in the prior redesign).

Goal: make all five open as **centered pop-up modals** with one consistent chrome. Full feature parity for every panel.

## Decisions (from brainstorming)

1. **One shared modal component** (`PageBuilder::ConfigModalComponent`) provides consistent chrome for all five; each panel sets its own max-width.
2. **Rules & Calculations keep their master→detail flow inside one modal** — the list and the editor swap in place (`data-drawer-list` / `data-drawer-editor`), with a back button. No stacked second modal.
3. **Dismiss via X + backdrop click + Esc.**

## Design

### `PageBuilder::ConfigModalComponent` (new — replaces `BuilderDrawerComponent`)
A single centered-modal chrome.

**Initializer:**
```ruby
PageBuilder::ConfigModalComponent.new(
  key:,            # String — data-tab-panel value ("templates"/"theme"/"rules"/"calculations"/"settings")
  title:,          # String — header title
  subtitle: nil,   # String — optional header subtitle
  icon: nil,       # Symbol — optional header icon (:templates/:theme/:rules/:calculations/:settings)
  accent: :slate,  # Symbol — :slate (default) | :indigo (rules) | :purple (calculations)
  size: :md        # Symbol — :sm | :md | :lg | :xl | :"2xl" → maps to max-w-*
)
```
Renders (block = body content):
```
<div role="dialog" aria-modal="true"
     data-tab-panel="<key>" data-page-builder-target="tabPanel"
     class="tab-panel hidden fixed inset-0 z-40 flex items-center justify-center p-4
            bg-black/50 opacity-0 transition-opacity duration-150"
     data-action="click->page-builder#onModalBackdropClick">
  <div data-modal-dialog
       class="bg-white rounded-xl shadow-2xl w-full <max-w by size> max-h-[85vh] flex flex-col
              scale-95 transition-transform duration-150"
       data-action="click->page-builder#stopModalClose">
    <header> accent icon + title + subtitle + X (closeAllTabPanels) </header>
    <div class="flex-1 overflow-y-auto"> <%= content %> </div>
  </div>
</div>
```
- **Size → max-width:** `sm`→`max-w-md`, `md`→`max-w-2xl`, `lg`→`max-w-4xl`, `xl`→`max-w-5xl`, `2xl`→`max-w-6xl`.
- **Accent → header icon tint / focus rings:** slate (neutral), indigo, purple.
- Backdrop is the outer element; its `click` calls `onModalBackdropClick`, which closes only when `event.target === currentTarget` (the dialog stops propagation via `stopModalClose`).

### Per-panel wiring (`app/views/admin/maintenance/pages/_editor.html.erb`)

| Panel | key | size | accent | body |
|-------|-----|------|--------|------|
| Templates | `templates` | `xl` (max-w-5xl) | slate | existing template gallery grid (TemplateCardComponent), header/close stripped |
| Theme | `theme` | `lg` (max-w-4xl) | slate | existing theme controls, header/close stripped |
| Settings | `settings` | `md` (max-w-2xl) | slate | existing settings form, header/close stripped |
| Rules | `rules` | `md` (max-w-2xl) | indigo | `data-drawer-list="rules"` (RulesPanelComponent) + `data-drawer-editor="rules"` mount — unchanged |
| Calculations | `calculations` | `md` (max-w-2xl) | purple | `data-drawer-list="calculations"` (CalculationsPanelComponent) + `data-drawer-editor="calculations"` mount — unchanged |

Each existing panel's bespoke header + close button and the full-screen `fixed top-16 left-72…` shell are removed — the modal chrome now provides backdrop, centering, header, and close.

### Stimulus

**`page_builder/tab_manager.js`:**
- Remove the `DRAWER_PANELS` Set and translate-x logic. All panels are modals now:
  - `_showPanel(panel)` → `panel.classList.remove("hidden")`, then on next frame remove `opacity-0` and the dialog's `scale-95` (fade + scale-in).
  - `_hidePanel(panel)` → add `opacity-0` + dialog `scale-95`; add `hidden` (after transition or immediately — keep simple: add `hidden`).
- Keep `showDrawerEditor` / `showDrawerList` (drive the Rules/Calc master→detail swap via `data-drawer-list`/`data-drawer-editor`). No logic change.

**`page_builder_controller.js`:**
- Add `onModalBackdropClick(event)` → if `event.target === event.currentTarget`, `this.tabManager.closeAllTabPanels()`.
- Add `stopModalClose(event)` → `event.stopPropagation()`.
- **Esc to close:** if a global `keydown` handler isn't already closing panels, add one that calls `closeAllTabPanels()` on `Escape` (only when a modal is open). Verify existing handler first to avoid duplication.

### Component / file plan
- **Create:** `app/components/page_builder/config_modal_component.rb` + `.html.erb` + `spec/components/page_builder/config_modal_component_spec.rb`.
- **Delete:** `app/components/page_builder/builder_drawer_component.rb` + `.html.erb` + `spec/components/page_builder/builder_drawer_component_spec.rb` (superseded).
- **Modify:** `app/views/admin/maintenance/pages/_editor.html.erb` (wrap all five panels), `app/javascript/controllers/page_builder/tab_manager.js`, `app/javascript/controllers/page_builder_controller.js`.

## Constraints
- Tailwind only, Stimulus only, ViewComponent encapsulation.
- Admin surface only — no routes, controllers, auth, schema, or data-model changes.
- Responsive: modal `w-full max-w-*` with `p-4` gutter; `max-h-[85vh]` scroll on small screens.
- Full feature parity for all five panels.

## Out of scope
- Changing any panel's internal content/behavior (rules engine, formula engine, template apply, theme model, settings form).
- New config surfaces.

## Testing
- Component spec for `ConfigModalComponent` (chrome, sizes, accents, tab-panel data attributes, backdrop action).
- Existing rule/calc/panel component specs must stay green; rewrite any that asserted the old drawer/overlay markup (stale-test policy).
- **Deep browser verification of ALL Rules & Calculations functionality** (explicit user requirement): see Verification section in the plan.
