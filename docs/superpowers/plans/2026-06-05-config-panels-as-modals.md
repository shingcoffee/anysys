# Config Panels → Centered Modals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the five page-editor toolbar config buttons (Templates, Theme, Rules, Calculations, Settings) all open as centered pop-up modals sharing one chrome, replacing today's mix of full-screen overlays (Templates/Theme/Settings) and right-docked drawers (Rules/Calculations).

**Architecture:** A new `PageBuilder::ConfigModalComponent` provides centered-modal chrome (backdrop + dialog + header + scrollable body) and carries the `data-tab-panel`/`data-page-builder-target="tabPanel"` hooks the existing `switchTab` already drives. All five panels are wrapped in it; panel-specific controllers (e.g. `template-applier`) move to an inner body wrapper. `tab_manager.js` drops its drawer translate-x logic and shows/hides modals via `hidden` + opacity/scale; `page_builder_controller.js` gains backdrop-click, stop-propagation, and Esc-to-close handlers. Rules/Calculations keep their in-modal master→detail (`data-drawer-list`/`data-drawer-editor`) unchanged. The now-redundant `BuilderDrawerComponent` is deleted.

**Tech Stack:** Rails 8.1 / ViewComponent / TailwindCSS (only) / StimulusJS (only) / RSpec.

---

## File Structure

**Create:**
- `app/components/page_builder/config_modal_component.rb`
- `app/components/page_builder/config_modal_component.html.erb`
- `spec/components/page_builder/config_modal_component_spec.rb`

**Modify:**
- `app/views/admin/maintenance/pages/_editor.html.erb` — wrap all five panels; strip bespoke headers/overlay shells; move `template-applier` (and any panel-specific controllers) to inner body wrappers.
- `app/javascript/controllers/page_builder/tab_manager.js` — modal show/hide; remove `DRAWER_PANELS` translate logic; keep `showDrawerEditor`/`showDrawerList`.
- `app/javascript/controllers/page_builder_controller.js` — add `onModalBackdropClick`, `stopModalClose`, and Esc-to-close.

**Delete (superseded by ConfigModalComponent):**
- `app/components/page_builder/builder_drawer_component.rb`
- `app/components/page_builder/builder_drawer_component.html.erb`
- `spec/components/page_builder/builder_drawer_component_spec.rb`

---

## Task 1: `ConfigModalComponent`

**Files:**
- Create: `app/components/page_builder/config_modal_component.rb`
- Create: `app/components/page_builder/config_modal_component.html.erb`
- Test: `spec/components/page_builder/config_modal_component_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/components/page_builder/config_modal_component_spec.rb
require "rails_helper"

RSpec.describe PageBuilder::ConfigModalComponent, type: :component do
  def render_modal(**opts)
    defaults = { key: "rules", title: "Conditional Rules", subtitle: "Sub", accent: :indigo, icon: :rules, size: :md }
    render_inline(described_class.new(**defaults.merge(opts))) { "<p>BODY</p>".html_safe }
  end

  it "renders the title, subtitle and yielded body" do
    render_modal
    expect(page).to have_text("Conditional Rules")
    expect(page).to have_text("Sub")
    expect(page).to have_text("BODY")
  end

  it "carries the tab-panel hooks switchTab depends on, hidden by default" do
    render_modal
    el = page.find("[data-tab-panel='rules']", visible: :all)
    expect(el["data-page-builder-target"]).to include("tabPanel")
    expect(el[:class]).to include("hidden")
  end

  it "wires backdrop click to close and stops dialog clicks from closing" do
    render_modal
    expect(page).to have_css("[data-action='click->page-builder#onModalBackdropClick']")
    expect(page).to have_css("[data-action='click->page-builder#stopModalClose']")
  end

  it "maps size to a max-width class" do
    render_modal(size: :xl)
    expect(page.native.to_html).to include("max-w-5xl")
  end

  it "applies the accent in the header" do
    render_modal(accent: :purple)
    expect(page.native.to_html).to include("purple")
  end
end
```

- [ ] **Step 2: Run, verify it fails**

Run: `bundle exec rspec spec/components/page_builder/config_modal_component_spec.rb`
Expected: FAIL (uninitialized constant `ConfigModalComponent`).

- [ ] **Step 3: Implement the component class**

```ruby
# app/components/page_builder/config_modal_component.rb
# frozen_string_literal: true

module PageBuilder
  class ConfigModalComponent < ApplicationComponent
    include DesignTokens
    include ComponentClasses

    SIZES = {
      sm:    "max-w-md",
      md:    "max-w-2xl",
      lg:    "max-w-4xl",
      xl:    "max-w-5xl",
      :"2xl" => "max-w-6xl"
    }.freeze

    ACCENTS = {
      slate:  { soft: "bg-slate-100",  icon: "text-slate-600" },
      indigo: { soft: "bg-indigo-50",  icon: "text-indigo-600" },
      purple: { soft: "bg-purple-50",  icon: "text-purple-600" }
    }.freeze

    def initialize(key:, title:, subtitle: nil, icon: nil, accent: :slate, size: :md)
      @key = key
      @title = title
      @subtitle = subtitle
      @icon = icon&.to_sym
      @accent = accent.to_sym
      @size = size.to_sym
    end

    private

    attr_reader :key, :title, :subtitle, :icon, :accent, :size

    def max_width
      SIZES.fetch(size, SIZES[:md])
    end

    def accent_classes
      ACCENTS.fetch(accent, ACCENTS[:slate])
    end

    def icon_path
      {
        templates:    'M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1v-3z',
        theme:        'M4.098 19.902a3.75 3.75 0 005.304 0l6.401-6.402M6.75 21A3.75 3.75 0 013 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125V11l-3.75 3.75M6.75 21l3.75-3.75M6.75 21h7.5',
        rules:        'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4',
        calculations: 'M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z',
        settings:     'M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z'
      }[icon]
    end
  end
end
```

- [ ] **Step 4: Implement the template**

```erb
<%# app/components/page_builder/config_modal_component.html.erb %>
<div role="dialog" aria-modal="true" aria-label="<%= title %>"
     data-tab-panel="<%= key %>"
     data-page-builder-target="tabPanel"
     data-action="click->page-builder#onModalBackdropClick"
     class="tab-panel hidden fixed inset-0 z-40 flex items-center justify-center p-4 bg-black/50">
  <div data-modal-dialog
       data-action="click->page-builder#stopModalClose"
       class="bg-white rounded-xl shadow-2xl w-full <%= max_width %> max-h-[85vh] flex flex-col overflow-hidden">
    <%# Header %>
    <div class="flex items-start justify-between gap-3 px-5 py-4 border-b border-gray-100 flex-shrink-0">
      <div class="flex items-start gap-3 min-w-0">
        <% if icon && icon_path %>
          <div class="flex items-center justify-center w-9 h-9 rounded-lg <%= accent_classes[:soft] %> flex-shrink-0">
            <svg class="w-5 h-5 <%= accent_classes[:icon] %>" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75">
              <path stroke-linecap="round" stroke-linejoin="round" d="<%= icon_path %>" />
            </svg>
          </div>
        <% end %>
        <div class="min-w-0">
          <h2 class="text-base font-semibold text-gray-900 truncate"><%= title %></h2>
          <% if subtitle.present? %>
            <p class="text-xs text-gray-500 mt-0.5"><%= subtitle %></p>
          <% end %>
        </div>
      </div>
      <button type="button" data-action="click->page-builder#closeAllTabPanels"
              class="p-2 -mr-1 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition-colors flex-shrink-0"
              aria-label="Close">
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
    <%# Body %>
    <div class="flex-1 overflow-y-auto">
      <%= content %>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Run, verify pass**

Run: `bundle exec rspec spec/components/page_builder/config_modal_component_spec.rb`
Expected: PASS (5 examples).

---

## Task 2: Stimulus — modal show/hide + dismiss handlers

**Files:**
- Modify: `app/javascript/controllers/page_builder/tab_manager.js`
- Modify: `app/javascript/controllers/page_builder_controller.js`

- [ ] **Step 1: Simplify `_showPanel`/`_hidePanel` and drop drawer logic**

In `tab_manager.js`, remove the `DRAWER_PANELS` static Set and `_isDrawerPanel`, and replace the show/hide helpers so all panels are modals:

```js
  _showPanel(panel) {
    panel.classList.remove("hidden")
  }

  _hidePanel(panel) {
    panel.classList.add("hidden")
  }
```

Keep `showDrawerEditor` / `showDrawerList` exactly as-is (they drive the Rules/Calc master→detail swap and still apply).

- [ ] **Step 2: Add backdrop-close, stop-propagation, and Esc handlers**

In `page_builder_controller.js`, add three methods (delegating to the tab manager where relevant):

```js
  onModalBackdropClick(event) {
    // Only close when the click is on the backdrop itself, not the dialog
    if (event.target === event.currentTarget) {
      this.tabManager.closeAllTabPanels()
    }
  }

  stopModalClose(event) {
    event.stopPropagation()
  }

  closeModalsOnEscape(event) {
    if (event.key !== "Escape") return
    const anyOpen = this.tabPanelTargets.some(p => !p.classList.contains("hidden"))
    if (anyOpen) this.tabManager.closeAllTabPanels()
  }
```

- [ ] **Step 3: Wire Esc globally**

If `page_builder_controller.js` already binds a `keydown` listener in `connect()`, add an `if (event.key === "Escape") this.closeModalsOnEscape(event)` branch there. Otherwise add to `connect()`:

```js
    this._onKeydown = (e) => this.closeModalsOnEscape(e)
    document.addEventListener("keydown", this._onKeydown)
```
and in `disconnect()`:
```js
    if (this._onKeydown) document.removeEventListener("keydown", this._onKeydown)
```
VERIFY first whether a keydown handler / `disconnect()` already exists to avoid duplicate bindings; integrate rather than duplicate.

---

## Task 3: Wrap all five panels in `_editor.html.erb`

**Files:**
- Modify: `app/views/admin/maintenance/pages/_editor.html.erb`

For EACH panel, replace the existing tab-panel root (and its bespoke header + close button + full-screen overlay shell) with a `ConfigModalComponent` render whose block holds the panel's body. Move any panel-specific `data-controller` (and its `*-value` attributes) from the old root onto an INNER wrapper inside the modal body.

- [ ] **Step 1: Templates panel** (`data-tab-panel="templates"`, currently `data-controller="template-applier"` + values, max-w-5xl gallery)

```erb
<%= render PageBuilder::ConfigModalComponent.new(
      key: "templates", title: "Layout Templates",
      subtitle: "Switch to a different layout template for your page",
      icon: :templates, accent: :slate, size: :xl) do %>
  <div class="p-6 space-y-6"
       data-controller="template-applier"
       data-template-applier-page-id-value="<%= @page.id %>"
       data-template-applier-customer-id-value="<%= current_customer_id %>"
       data-template-applier-entity-id-value="<%= entity_id %>">
    <%# ...existing templates body: warning banner + TemplateCardComponent grid... %>
    <%# (remove the old <h2>/subtitle/close-button header block — chrome provides it) %>
  </div>
<% end %>
```

- [ ] **Step 2: Theme panel** (`data-tab-panel="theme"`, theme controls)

Wrap the existing theme body in:
```erb
<%= render PageBuilder::ConfigModalComponent.new(
      key: "theme", title: "Form Theme",
      subtitle: "Customize the visual appearance of your form",
      icon: :theme, accent: :slate, size: :lg) do %>
  <div class="p-6 space-y-6"><%# ...existing theme controls, header stripped... %></div>
<% end %>
```
Preserve any `data-controller`/targets that were on the old theme root by moving them onto this inner `<div>`.

- [ ] **Step 3: Settings panel** (`data-tab-panel="settings"`, form)

```erb
<%= render PageBuilder::ConfigModalComponent.new(
      key: "settings", title: "Page Settings",
      subtitle: "Configure page-level options",
      icon: :settings, accent: :slate, size: :md) do %>
  <div class="p-6 space-y-6"><%# ...existing settings form, header stripped... %></div>
<% end %>
```

- [ ] **Step 4: Rules panel** (replace the `BuilderDrawerComponent` render)

```erb
<%= render PageBuilder::ConfigModalComponent.new(
      key: "rules", title: "Conditional Rules",
      subtitle: "Show or hide fields based on conditions",
      icon: :rules, accent: :indigo, size: :md) do %>
  <div data-drawer-list="rules" data-page-builder-target="rulesPanel" class="p-4">
    <%= render PageBuilder::RulesPanelComponent.new(
          rules: @page.configuration_json&.dig("rules") || [],
          fields: @page.configuration_json&.dig("pages")&.flat_map { |p| p["fields"] || [] } || []) %>
  </div>
  <div data-drawer-editor="rules" class="hidden" data-page-builder-target="ruleEditorModal"></div>
<% end %>
```

- [ ] **Step 5: Calculations panel** (replace the `BuilderDrawerComponent` render)

```erb
<%= render PageBuilder::ConfigModalComponent.new(
      key: "calculations", title: "Calculated Fields",
      subtitle: "Automatically calculate field values using formulas",
      icon: :calculations, accent: :purple, size: :md) do %>
  <div data-drawer-list="calculations" data-page-builder-target="calculationsPanel" class="p-4">
    <%= render PageBuilder::CalculationsPanelComponent.new(
          calculations: @page.configuration_json&.dig("calculations") || [],
          fields: @page.configuration_json&.dig("pages")&.flat_map { |p| p["fields"] || [] } || []) %>
  </div>
  <div data-drawer-editor="calculations" class="hidden" data-page-builder-target="formulaEditorModal"></div>
<% end %>
```

- [ ] **Step 6: Confirm no leftover overlay shells / duplicate headers**

Run: `grep -n "fixed top-16 left-72\|BuilderDrawerComponent" app/views/admin/maintenance/pages/_editor.html.erb`
Expected: zero hits.

---

## Task 4: Delete the superseded `BuilderDrawerComponent`

**Files:**
- Delete: `app/components/page_builder/builder_drawer_component.rb`
- Delete: `app/components/page_builder/builder_drawer_component.html.erb`
- Delete: `spec/components/page_builder/builder_drawer_component_spec.rb`

- [ ] **Step 1: Verify no references remain**

Run: `grep -rn "BuilderDrawerComponent\|builder_drawer" app/ spec/`
Expected: zero hits (after Task 3 replaced both usages).

- [ ] **Step 2: Delete**

Run: `git rm app/components/page_builder/builder_drawer_component.rb app/components/page_builder/builder_drawer_component.html.erb spec/components/page_builder/builder_drawer_component_spec.rb`

---

## Task 5: Verification

- [ ] **Step 1: Component specs**

Run: `bundle exec rspec spec/components/page_builder/`
Expected: PASS (the one pre-existing `ComponentPaletteComponent` failure remains unrelated; rewrite any spec asserting old drawer/overlay markup).

- [ ] **Step 2: Assets + server**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`

- [ ] **Step 3: Modal smoke (release engineer, Playwright ~/pw-tools)**

For each of the five buttons: click → confirm a centered modal pops up over a dark backdrop (not a side drawer, not a full-screen overlay); confirm the **X**, a **backdrop click**, and the **Esc** key each close it; confirm clicking inside the dialog does NOT close it. No console errors.

- [ ] **Step 4: DEEP Rules & Calculations functional verification (explicit user requirement)**

In the browser, exercise EVERY feature and confirm it works inside the modal and persists after Save:
- **Rules:** open modal → list renders; Add Rule → editor (master→detail) appears; set rule name; add a condition group; pick a field, an operator (try several incl. `between`/`is_empty`), enter the contextual value; toggle group AND/OR and top-level AND/OR; add a 2nd condition + 2nd group; add actions of multiple types (show/hide field, show/hide/skip page, enable/disable, set required, set value) with target + value; enable Test Mode and confirm sample inputs show which actions fire; Save the rule → returns to list with summary; toggle enable/disable; duplicate; edit; delete; (if >6 rules) search. Save the page and reload → rules persist.
- **Calculations:** open modal → list renders; Add Calculation → editor; select target field (grouped by page); build a formula in the pill editor (field autocomplete via `{`/`@`, function autocomplete by typing); use the function inserter (switch Math/Logic/Text/Date tabs, filter, click a chip → `FN()` inserted, caret inside parens); set format type/decimals/prefix/suffix; enter sample values → live preview + validation status update; Save → returns to list with badge + formula; edit; delete; (if >6) search. Save the page and reload → calculations persist.
- Report PASS/FAIL per feature with screenshots and any console errors.

---

## Self-Review notes
- **Spec coverage:** shared modal chrome (T1), Stimulus show/hide + dismiss incl. Esc/backdrop (T2), all five panels wrapped + controllers preserved on inner wrappers (T3), drawer component removed (T4), component specs + modal smoke + deep Rules/Calc verification (T5). All spec sections mapped.
- **Parity guard:** Rules/Calc bodies are rendered by the SAME existing components (RulesPanelComponent/CalculationsPanelComponent + the editor templates) and the `data-drawer-list`/`data-drawer-editor` master→detail hooks are unchanged, so no feature is dropped; T5 Step 4 verifies each behavior end-to-end.
- **No data/route/auth changes** — admin surface only.
