# Website Page Editor Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the Website page edit workspace into a professional clean-minimal editor with accessible responsive pane tabs, calmer content fields, and an unobstructed live preview.

**Architecture:** Preserve the existing `AdminPageComponent`, `Websites::Admin::ComposerComponent`, and `website-builder` Stimulus contract. Scope visual changes to `workspace?`; non-workspace composer modes, routes, controllers, persistence, authorization, public website rendering, and Website settings remain unchanged.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, ERB, TailwindCSS, StimulusJS, RSpec, Vitest, Playwright

**Spec:** `docs/superpowers/specs/2026-09-22-website-page-editor-ux.md`

## Global Constraints

- Use ViewComponent + Tailwind + Stimulus only; do not add custom CSS or another JavaScript framework.
- Preserve explicit Save, standalone Preview, `Cmd/Ctrl+S`, live draft preview, upload/link/list/reset behavior, and the sections JSON format.
- Scope changes to `GET/PATCH /:cid/admin/modules/website/pages/:id/edit` and `Websites::Admin::ComposerComponent#workspace?`.
- Keep all visible and accessibility wording in I18n with English and Simplified Chinese parity.
- Preserve admin/owner authorization and tenant scoping; do not change routes, controllers, models, or persistence.
- Do not alter unrelated existing working-tree changes, especially Website settings and skeleton surfaces.
- Do not commit; the human reviewer will commit manually.
- Any changed JavaScript under `app/javascript/**` must retain 100% Vitest line and branch coverage.

---

### Task 1: Accessible Workspace Chrome

**Files:**
- Modify: `app/components/websites/admin/composer_component.html.erb`
- Modify: `app/components/websites/admin/composer_component.rb`
- Modify: `app/javascript/controllers/website_builder_controller.js`
- Modify: `spec/components/websites/admin/composer_component_spec.rb`
- Modify: `spec/javascript/controllers/website_builder_controller.test.js`
- Modify: `spec/e2e/website_page_composer.app.spec.js`
- Modify: `spec/e2e/website_responsive.app.spec.js`

**Interfaces:**
- Consumes: existing `paneBtn`, `editorPane`, `previewPane`, `viewportBtn`, `previewStage`, `previewFrame`, `unsaved`, and `previewLoading` Stimulus targets.
- Produces: ARIA tab state synchronized by `setWorkspacePane`, unchanged preview viewport behavior, and a cleaner preview stage without decorative browser chrome.

- [ ] **Step 1: Write failing component expectations**

Add expectations proving the workspace renders:

```ruby
expect(page).to have_css("[role='tablist'][aria-label='#{I18n.t("website.admin.pages.edit.workspace_panes")}']")
expect(page).to have_css("button[role='tab'][aria-selected='true'][aria-controls='website-editor-panel']")
expect(page).to have_css("#website-editor-panel[role='tabpanel'][aria-labelledby='website-editor-tab']")
expect(page).to have_css("#website-preview-panel[role='tabpanel'][aria-labelledby='website-preview-tab']")
expect(page).to have_css("[data-website-builder-target='previewLoading'][role='status'][aria-live='polite']", visible: :all)
expect(page).not_to have_css("[data-preview-browser-chrome]")
```

- [ ] **Step 2: Run the component spec and verify RED**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb
```

Expected: failures for the missing tab semantics, status semantics, or browser-chrome removal selector.

- [ ] **Step 3: Write failing Stimulus expectations**

Extend the workspace-pane test fixture with stable IDs and tab semantics, then assert:

```javascript
expect(editBtn.getAttribute("aria-selected")).toBe("true")
expect(editBtn.getAttribute("tabindex")).toBe("0")
expect(previewBtn.getAttribute("aria-selected")).toBe("false")
expect(previewBtn.getAttribute("tabindex")).toBe("-1")
expect(editor.getAttribute("aria-hidden")).toBe("false")
expect(preview.getAttribute("aria-hidden")).toBe("true")
```

Add keyboard tests that call the pane-tab keyboard action and prove ArrowRight, ArrowLeft, Home, and End activate the expected tab while unsupported keys do nothing.

- [ ] **Step 4: Run the JavaScript test and verify RED**

Run:

```bash
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/website_builder_controller.test.js
```

Expected: failures because `#applyWorkspacePane` does not synchronize tab/panel ARIA state and no keyboard action exists.

- [ ] **Step 5: Implement the workspace chrome**

In `composer_component.html.erb`:

- Compose the below-`xl` switcher as `role="tablist"`.
- Give tabs stable IDs, `role="tab"`, `aria-selected`, `aria-controls`, and roving `tabindex`.
- Give panes stable IDs, `role="tabpanel"`, `aria-labelledby`, and initial `aria-hidden`.
- Keep Save as the only filled-accent action; retain the existing header actions.
- Keep the preview toolbar compact, with text-bearing live and unsaved states.
- Mark the loading overlay as `role="status" aria-live="polite"`.
- Remove decorative browser dots/address-bar markup if present; retain the white iframe frame, ring, radius, and responsive stage widths.

In `composer_component.rb`, keep workspace-only helper classes neutral:

```ruby
def pane_btn_class
  "rounded-md px-3 py-1.5 text-sm font-medium text-text-secondary transition-colors hover:text-text-primary aria-selected:bg-surface aria-selected:text-text-primary aria-selected:shadow-sm"
end
```

In `website_builder_controller.js`:

- Add a `keydown->website-builder#navigateWorkspaceTabs` action to the tabs.
- Synchronize `aria-selected`, `tabindex`, panel `aria-hidden`, and the existing `max-xl:hidden` classes.
- ArrowRight/ArrowLeft wrap between tabs; Home selects Edit; End selects Preview.
- Prevent default only for handled keys and focus the activated tab without moving focus into the iframe.

- [ ] **Step 6: Verify Task 1 GREEN**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/website_builder_controller.test.js
```

Expected: both commands pass.

- [ ] **Step 7: Update browser coverage**

In the app-backed Playwright specs, assert the below-`xl` controls expose tab semantics, keyboard navigation switches panes, desktop still shows both panes, and no horizontal overflow occurs at the existing desktop/tablet/mobile viewports.

---

### Task 2: Clean-Minimal Inspector and Section Navigation

**Files:**
- Modify: `app/components/websites/admin/composer_sections_component.html.erb`
- Modify: `app/components/websites/admin/composer_sections_component.rb`
- Modify: `app/components/websites/admin/page_identity_component.html.erb`
- Modify: `app/components/websites/admin/section_editor_component.html.erb`
- Modify: `app/components/websites/admin/section_editor_component.rb`
- Modify: `app/components/websites/admin/prop_field_component.html.erb`
- Modify: `app/components/websites/admin/prop_field_component.rb`
- Modify: `spec/components/websites/admin/composer_component_spec.rb`
- Modify: `spec/components/websites/admin/section_editor_component_spec.rb`
- Modify: `spec/components/websites/admin/prop_field_component_spec.rb` if it exists; otherwise cover through the section-editor spec.

**Interfaces:**
- Consumes: normalized sections, localized group/field labels, current link/image/array controls, and the `focusSection` rail behavior.
- Produces: flat section navigation, Field-style controls, separator-based groups, and outlined repeatable items without changing submitted data or actions.

- [ ] **Step 1: Write failing hierarchy expectations**

Add focused specs proving workspace rendering uses:

```ruby
expect(page).to have_css("nav[data-workspace-section-nav]")
expect(page).to have_css("[data-workspace-inspector]")
expect(page).to have_css("[data-field-group] + [data-field-group][class*='border-t']")
expect(page).to have_css("[data-array-item][class*='border']")
expect(page).not_to have_css("[data-field-group][class*='bg-canvas-elevated']")
expect(page).not_to have_css("[data-field-group][class*='shadow']")
```

Also assert section navigation preserves number, localized name, preview text, `aria-current`, and horizontal/vertical responsive behavior.

- [ ] **Step 2: Run focused component specs and verify RED**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb
```

Expected: failures for the new semantic hooks or separator-based group structure.

- [ ] **Step 3: Implement flat navigation and inspector composition**

In `composer_sections_component.html.erb`:

- Add stable `data-workspace-section-nav` and `data-workspace-inspector` hooks.
- Keep the desktop rail at `xl:w-52`, horizontal below `xl`, independently scrollable, and flat.
- Preserve numbering, localized type labels, preview text, selected accent border, and Add section behavior for unlocked callers.
- Keep the inspector centered at `max-w-2xl px-5 py-6 sm:px-6`.

In `page_identity_component.html.erb`:

- Preserve the collapsed persisted-page disclosure.
- Keep page settings fields as one-column Field-style stacks in workspace mode.
- Use quiet checkbox rows in workspace mode and retain native `fieldset`/`legend`.

- [ ] **Step 4: Implement field and group hierarchy**

In `section_editor_component.html.erb`:

- Render the section title and description once at the top.
- Add `data-field-group` to each localized Text, Photo, Buttons, Style, or Items group.
- Use `flex flex-col gap-4`; add `border-t border-border-subtle pt-5` to every group after the first.
- Remove shaded/elevated group wrappers in workspace mode.
- Keep repeatable items outlined with `rounded-lg border border-border-subtle`, no shadow, a compact number/toolbar row, and unchanged controls.
- Keep Restore original copy as a muted ghost action at the bottom.

In `prop_field_component.html.erb`:

- Preserve label/control/hint/error order.
- Keep the page picker before the custom link control.
- Keep character counts hidden at zero.
- Retain consistent `.input-field` controls and adjacent image upload/status/error UI.

Use Ruby helpers only when they remove repeated conditional class strings; do not change field schemas or labels in this task.

- [ ] **Step 5: Verify Task 2 GREEN**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb spec/components/websites/admin/prop_field_component_spec.rb
```

If `spec/components/websites/admin/prop_field_component_spec.rb` does not exist, omit it and report that coverage remains in the section-editor spec.

- [ ] **Step 6: Rebuild Tailwind and run JavaScript coverage**

Run:

```bash
bin/rails tailwindcss:build
npx vitest run --config config/javascript/vitest.config.js --coverage
```

Expected: build exits 0 and JavaScript coverage reports 100% lines and branches for changed source.

- [ ] **Step 7: Run app-backed visual QA**

Browser plugin classification: unavailable in this session, so use the repository Playwright workflow.

Start the development server:

```bash
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Run:

```bash
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test spec/e2e/website_page_composer.app.spec.js spec/e2e/website_responsive.app.spec.js
```

Capture page 8 at `1440x900`, `1280x800`, `768x1024`, `390x844`, and `320x568`. Verify Save hierarchy, three-region desktop layout, accessible tabs below `xl`, independent scrolling, no fake browser chrome, no nested shaded field-group cards, preserved live preview, preserved pane state, and no horizontal overflow.

- [ ] **Step 8: Final targeted verification**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb spec/requests/websites/admin_pages_spec.rb
npx vitest run --config config/javascript/vitest.config.js --coverage
git diff --check
```

Expected: zero RSpec failures, 100% required JavaScript coverage, and no whitespace errors.

