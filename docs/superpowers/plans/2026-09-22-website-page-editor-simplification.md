# Website Page Editor Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the Website page editor into a clean two-region workspace with horizontal section navigation and progressively disclosed secondary controls.

**Architecture:** Preserve the current Rails/ViewComponent form and `website-builder` Stimulus contract. Change only workspace-specific component composition and Tailwind classes; the existing section data model, persistence, preview endpoint, authorization, and non-workspace composer modes remain unchanged.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, ERB, TailwindCSS, StimulusJS, RSpec, Playwright

**Spec:** `docs/superpowers/specs/2026-09-22-website-page-editor-simplification.md`

## Global Constraints

- Use ViewComponent + Tailwind + Stimulus only.
- Preserve all current editor behavior and submitted data.
- Scope changes to workspace rendering used by `/:cid/admin/modules/website/pages/:id/edit`.
- Keep all user-facing copy in I18n with English and Simplified Chinese parity.
- Do not alter unrelated existing working-tree changes.
- Do not commit.

---

### Task 1: Specify the Simplified Workspace

**Files:**
- Modify: `spec/components/websites/admin/composer_component_spec.rb`
- Modify: `spec/components/websites/admin/section_editor_component_spec.rb`

**Interfaces:**
- Consumes: existing `data-workspace-section-nav`, `data-workspace-inspector`, `data-field-group`, `sectionNav`, and `row` hooks.
- Produces: regression expectations for a horizontal navigator, full-width inspector, compact identity row, primary fields, and secondary disclosures.

- [ ] **Step 1: Write failing composer expectations**

Add expectations that workspace navigation is horizontal at all widths, does not include `xl:w-52` or `xl:flex-col`, does not render preview excerpts, and uses a `max-w-3xl` inspector.

- [ ] **Step 2: Write failing section-editor expectations**

Assert the first workspace field group is a directly rendered primary group and later groups are collapsed `<details>` elements with accessible `<summary>` controls.

- [ ] **Step 3: Run focused specs and verify RED**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb
```

Expected: failures for the current vertical desktop rail, `max-w-2xl` inspector, rendered workspace preview excerpts, and non-disclosure secondary groups.

### Task 2: Implement the Two-Region Editor

**Files:**
- Modify: `app/components/websites/admin/composer_component.rb`
- Modify: `app/components/websites/admin/composer_sections_component.rb`
- Modify: `app/components/websites/admin/composer_sections_component.html.erb`
- Modify: `app/components/websites/admin/page_identity_component.html.erb`
- Modify: `app/components/websites/admin/section_editor_component.html.erb`

**Interfaces:**
- Consumes: unchanged component inputs and Stimulus targets/actions.
- Produces: workspace-only layout classes and disclosure composition.

- [ ] **Step 1: Simplify the main split**

Reduce the workspace editor width to approximately `38rem` with a `46%` cap so the preview remains dominant.

- [ ] **Step 2: Replace the nested rail**

Render `ComposerSectionsComponent` workspace mode as a vertical editor shell containing one horizontal, overflow-safe tab list followed by matching tab panels in the inspector. Keep number, type name, `aria-current`, and click behavior; add roving focus with arrow/Home/End keys; omit preview excerpts.

- [ ] **Step 3: Compact page settings**

Render the collapsed workspace identity summary as one compact row while preserving the existing disclosure body and form controls.

- [ ] **Step 4: Add progressive disclosure**

Render the first field group directly with no repeated group heading. Render later groups as native `<details>` disclosures using localized summary labels, separator hairlines, and a state chevron. Keep media, button, and style groups collapsed initially while opening repeatable item lists by default. Preserve every existing field component, image well, array item, and action.

- [ ] **Step 5: Run focused specs and verify GREEN**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb
```

Expected: zero failures.

### Task 3: Browser and Regression Verification

**Files:**
- Modify if required by changed assertions: `spec/e2e/website_page_composer.app.spec.js`
- Modify if required by changed assertions: `spec/e2e/website_responsive.app.spec.js`

**Interfaces:**
- Consumes: the existing Rails development server and page-8 fixture.
- Produces: updated responsive screenshots and proof that the editing workflow remains intact.

- [ ] **Step 1: Update browser expectations**

Assert the workspace uses a horizontal section navigator at desktop, secondary groups are disclosures, section switching still works, and there is no horizontal overflow.

- [ ] **Step 2: Build Tailwind**

Run:

```bash
bin/rails tailwindcss:build
```

Expected: exit 0.

- [ ] **Step 3: Run targeted Rails specs**

Run:

```bash
bundle exec rspec spec/components/websites/admin/composer_component_spec.rb spec/components/websites/admin/section_editor_component_spec.rb spec/requests/websites/admin_pages_spec.rb
```

Expected: zero failures.

- [ ] **Step 4: Start the development server**

Run:

```bash
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

- [ ] **Step 5: Run Playwright**

Run:

```bash
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/website_page_composer.app.spec.js spec/e2e/website_responsive.app.spec.js
```

Expected: zero failures and refreshed screenshots for desktop, tablet, and mobile.

- [ ] **Step 6: Final checks**

Run:

```bash
git diff --check
```

Inspect the latest desktop and mobile screenshots with `view_image`. Confirm preview dominance, a single editor navigation layer, immediately visible primary fields, collapsed secondary controls, intact responsive pane tabs, and no clipping or overflow.
