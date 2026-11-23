# Code Generator CRUD Pages Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor admin code generator CRUD pages for visual consistency with the app, using shared ViewComponents and improved layouts.

**Architecture:** Presentation-layer refactor only. Replace hand-rolled HTML with shared components (`ButtonComponent`, `BadgeComponent`, `AlertComponent`, `EmptyStateComponent`, `CodeBlockComponent`). Standardize container widths to `max-w-[1400px]`. Convert form to single-column with collapsible preview below.

**Tech Stack:** Rails 8.1, ViewComponent, TailwindCSS, StimulusJS

---

## File Structure

All files already exist — this is a modify-only refactor.

| File | Change Summary |
|------|---------------|
| `app/components/admin/code_generators/index_component.html.erb` | Container width, ButtonComponent for header, EmptyStateComponent |
| `app/components/admin/code_generators/show_component.html.erb` | Container width, ButtonComponent for actions, BadgeComponent for metadata, breadcrumb standardization |
| `app/components/admin/code_generators/detail_panel_component.html.erb` | ButtonComponent for actions, BadgeComponent for metadata |
| `app/components/admin/code_generators/form_component.html.erb` | Single-column layout, AlertComponent for errors, collapsible preview below form, ButtonComponent for actions |
| `app/components/admin/code_generators/form_component.rb` | Remove preview-related layout concern (if any) |

---

### Task 1: Refactor IndexComponent template

**Files:**
- Modify: `app/components/admin/code_generators/index_component.html.erb`

The index page keeps its two-panel layout (sidebar tree + card grid) but standardizes to app-wide patterns.

- [ ] **Step 1: Update the template**

Key changes to make in `index_component.html.erb`:

1. **Container widths** — Replace both `max-w-screen-2xl` (lines 4, 21) with `max-w-[1400px]`

2. **Header "New Generator" button** (lines 11-14) — Replace inline link with `ButtonComponent`:
```erb
<%= render ButtonComponent.new(tag: :a, variant: :primary, href: new_admin_code_generator_path(kind: "step_action")) do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
  New Generator
<% end %>
```

3. **Empty state** — After the `turbo-frame` opening tag (line 114), before the card sections, add:
```erb
<% if element_type_tree.flat_map { |n| n[:generators] }.empty? %>
  <%= render EmptyStateComponent.new(
    title: "No generators found",
    description: "Create your first code generator to get started.",
    action_path: new_admin_code_generator_path(kind: "step_action"),
    action_text: "New Generator"
  ) %>
<% else %>
  <%# ... existing card grid code ... %>
<% end %>
```

4. **Version badges in cards** (lines 149, 183) — Replace inline `<span>` with `BadgeComponent`:
```erb
<%= render BadgeComponent.new(variant: :default, size: :sm) do %>v<%= klass._metadata[:version] %><% end %>
```

- [ ] **Step 2: Verify rendering**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All pass (tests check HTTP status, not visual output)

Then open `http://localhost:3000/admin/code_generators` in browser and visually verify:
- Container is narrower (1400px max)
- "New Generator" button uses app-standard styling
- Version badges are consistent rounded pills

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/index_component.html.erb
git commit -m "refactor: index page uses shared components, standardized container"
```

---

### Task 2: Refactor ShowComponent template

**Files:**
- Modify: `app/components/admin/code_generators/show_component.html.erb`

- [ ] **Step 1: Update the template**

Key changes to make in `show_component.html.erb`:

1. **Container widths** — Replace both `max-w-screen-xl` (lines 4, 43) with `max-w-[1400px]`

2. **Breadcrumb** (lines 5-13) — Simplify to match app standard:
```erb
<div class="mb-4">
  <%= link_to admin_code_generators_path, class: "inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 transition" do %>
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
    Back to Generators
  <% end %>
</div>
```

3. **Edit button** (lines 30-33) — Replace with `ButtonComponent`:
```erb
<%= render ButtonComponent.new(tag: :a, variant: :primary, href: edit_path) do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/></svg>
  Edit
<% end %>
```

4. **Delete button** (lines 34-37) — Keep `button_to` for form semantics but style consistently:
```erb
<%= button_to delete_path, method: :delete,
    data: { turbo_confirm: "Delete this generator? This cannot be undone." },
    class: ButtonComponent::BASE_CLASSES + " " + ButtonComponent::VARIANTS[:danger] + " " + ButtonComponent::SIZES[:md] do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
  Delete
<% end %>
```

5. **Category badge** (lines 21-24) — Replace with `BadgeComponent`:
```erb
<%= render BadgeComponent.new(variant: :primary, size: :sm) do %>
  <%= metadata[:category].to_s.tr("_", " ").titleize %>
<% end %>
```

6. **Version badge** (line 25) — Replace with `BadgeComponent`:
```erb
<%= render BadgeComponent.new(variant: :default, size: :sm) do %>v<%= metadata[:version] %><% end %>
```

7. **Example output section** (lines 104-113) — Replace `<pre>` with `CodeBlockComponent`:
```erb
<% if example.present? %>
  <%= render CodeBlockComponent.new(code: example, language: "ruby", filename: "example_output.rb") %>
<% end %>
```

- [ ] **Step 2: Verify rendering**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All pass

Then open `http://localhost:3000/admin/code_generators/element_types/process/model_operations/new_model_generator` and verify layout.

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/show_component.html.erb
git commit -m "refactor: show page uses shared components, standardized container"
```

---

### Task 3: Refactor DetailPanelComponent template

**Files:**
- Modify: `app/components/admin/code_generators/detail_panel_component.html.erb`

- [ ] **Step 1: Update the template**

Key changes to make in `detail_panel_component.html.erb`:

1. **Back button** (lines 4-9) — Replace with `ButtonComponent`:
```erb
<%= render ButtonComponent.new(tag: :a, variant: :ghost, size: :sm, href: admin_code_generators_path, data: { turbo_frame: "generator-detail" }) do %>
  <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
  Back to all generators
<% end %>
```

2. **Edit button** (lines 28-31) — Replace with `ButtonComponent`:
```erb
<%= render ButtonComponent.new(tag: :a, variant: :primary, size: :sm, href: edit_path, data: { turbo_frame: "_top" }) do %>
  <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/></svg>
  Edit
<% end %>
```

3. **Delete button** (lines 32-35) — Style with ButtonComponent classes:
```erb
<%= button_to delete_path, method: :delete,
    data: { turbo_confirm: "Delete this generator?", turbo_frame: "_top" },
    class: ButtonComponent::BASE_CLASSES + " " + ButtonComponent::VARIANTS[:danger] + " " + ButtonComponent::SIZES[:sm] do %>
  <svg class="w-3.5 h-3.5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
  Delete
<% end %>
```

4. **Version badge** (line 18) — Replace with `BadgeComponent`:
```erb
<%= render BadgeComponent.new(variant: :default, size: :sm) do %>v<%= metadata[:version] %><% end %>
```

5. **Category badge** (line 23) — Replace with `BadgeComponent`:
```erb
<%= render BadgeComponent.new(variant: :primary, size: :sm) do %><%= metadata[:category].to_s.tr("_", " ").titleize %><% end %>
```

6. **Example output** (lines 79-87) — Replace `<pre>` with `CodeBlockComponent`:
```erb
<% if example.present? %>
  <div class="mb-4">
    <%= render CodeBlockComponent.new(code: example, language: "ruby", filename: "example_output.rb") %>
  </div>
<% end %>
```

- [ ] **Step 2: Verify rendering**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All pass

Then click a generator from the index sidebar to verify the turbo-frame detail panel renders correctly.

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/detail_panel_component.html.erb
git commit -m "refactor: detail panel uses shared components"
```

---

### Task 4: Refactor FormComponent to single-column with collapsible preview

**Files:**
- Modify: `app/components/admin/code_generators/form_component.html.erb`

This is the largest change — converting from split two-panel layout to single-column with preview below.

- [ ] **Step 1: Update the template**

Rewrite `form_component.html.erb` with these changes:

1. **Container width** — `max-w-screen-2xl` → `max-w-3xl`

2. **Validation errors** (lines 18-33) — Replace custom red box with `AlertComponent`:
```erb
<% if @errors.any? %>
  <%= render AlertComponent.new(message: @errors.join(". "), type: :error) %>
<% end %>
```

3. **Form layout** — Remove the `<div class="flex gap-6">` wrapper and the right preview panel entirely. The form sections become the only content in a single column.

4. **Preview section** — Add a collapsible `<details>` section after the Methods section and before the action buttons:
```erb
<details class="bg-white rounded-xl border border-gray-200 overflow-hidden shadow-sm" open>
  <summary class="px-5 py-4 border-b border-gray-200 flex items-center gap-2 cursor-pointer select-none hover:bg-gray-50 transition">
    <div class="w-7 h-7 rounded-lg bg-slate-100 flex items-center justify-center">
      <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/></svg>
    </div>
    <h2 class="text-sm font-semibold text-gray-700">Generated Source Preview</h2>
    <span data-generator-form-target="previewLineCount" class="ml-auto text-xs text-gray-400">0 lines</span>
  </summary>
  <div class="overflow-x-auto overflow-y-auto max-h-96 p-4 bg-gray-50" data-generator-form-target="previewPanel">
    <div class="text-sm text-gray-400 italic">Edit the form to see a preview...</div>
  </div>
</details>
```

5. **Action buttons** (lines 177-187) — Replace with `ButtonComponent`:
```erb
<div class="flex items-center gap-3">
  <%= render ButtonComponent.new(variant: :primary, type: "submit") do %>
    <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>
    <%= creating? ? "Create Generator" : "Save Changes" %>
  <% end %>
  <%= render ButtonComponent.new(tag: :a, variant: :secondary, href: admin_code_generators_path) do %>
    Cancel
  <% end %>
</div>
```

- [ ] **Step 2: Verify rendering**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All pass

Then open `http://localhost:3000/admin/code_generators/new?kind=step_action` and verify:
- Single-column form layout
- Collapsible preview section below the form
- Alert-style error display
- Standard button styling

- [ ] **Step 3: Commit**

```bash
git add app/components/admin/code_generators/form_component.html.erb
git commit -m "refactor: form page uses single-column layout with collapsible preview"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run all controller specs**

Run: `bundle exec rspec spec/controllers/admin/code_generators_controller_spec.rb`
Expected: All pass

- [ ] **Step 2: Run full test suite to check for regressions**

Run: `bundle exec rspec`
Expected: All pass, no regressions

- [ ] **Step 3: Visual verification of all pages**

Open in browser and verify each page:
1. `http://localhost:3000/admin/code_generators` — Index with sidebar + card grid
2. Click a generator card — Detail panel loads in turbo-frame
3. Click "View" on a generator — Full show page
4. Click "Edit" — Single-column form with preview below
5. Click "New Generator" — New form renders correctly

- [ ] **Step 4: Commit any final adjustments**

```bash
git add -A
git commit -m "chore: final visual polish for code generator pages"
```
