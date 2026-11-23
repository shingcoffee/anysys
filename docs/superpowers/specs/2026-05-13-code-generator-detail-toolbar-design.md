# Code Generator Detail — Toolbar / Breadcrumb Alignment

**Date:** 2026-05-13
**Status:** Draft

## Problem

The code generator detail page under `Maintenance / Platform / Code Generators`
uses a custom layout (standalone breadcrumb component above a card-shaped
flex row containing sidebar + detail). The page edit screen under
`Maintenance / Pages` uses a different shell: an edge-to-edge container with
a single fixed `h-12` toolbar that combines the back button, breadcrumb-style
title, and right-aligned actions.

The user wants the code generator detail page to adopt the page-edit shell
**for the top bar and breadcrumb only**. Editor-specific affordances (center
icon-tab nav, viewport toggles, undo/redo, preview, save) do not apply to a
read-only detail screen and are out of scope.

## Goals

- Replace the standalone `BreadcrumbsComponent` and the inner header bar
  inside `Platform::CodeGenerators::DetailComponent` with one fixed `h-12`
  toolbar styled like `PageBuilder::ToolbarComponent`.
- Promote the show view to the same edge-to-edge flex shell that
  `app/views/admin/maintenance/pages/_editor.html.erb` uses, so the toolbar
  spans the full viewport width and the sidebar + main area sit beneath it.
- Keep all existing detail content (description, I/O panels, test runner,
  source code) and the existing `Platform::CodeGenerators::SidebarComponent`.

## Non-goals

- No tab navigation, viewport toggles, undo/redo, preview, or save — code
  generators are not edited from this screen.
- No changes to the index page or the edit/new forms.
- No restyling of the sidebar or the detail body itself.

## Design

### Layout (target)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ←  │  Process / version_check  v1.0.0       [Edit]  [Delete]        │   h-12 toolbar
├────┴─────────────────────────────────────────────────────────────────┤
│              │                                                       │
│   Sidebar    │   Description                                         │
│   (existing) │   Inputs → Outputs (+ Deps)                           │   main scrolls
│              │   Test Runner                                         │
│              │   Source Code (collapsible)                           │
│              │                                                       │
└──────────────┴───────────────────────────────────────────────────────┘
```

### New component: `Platform::CodeGenerators::ToolbarComponent`

Path:
- `app/components/platform/code_generators/toolbar_component.rb`
- `app/components/platform/code_generators/toolbar_component.html.erb`

Initializer:
```ruby
def initialize(generator_class:, path:, customer_id:)
```

Public derived values (private methods):
- `back_path` — `admin_maintenance_platform_code_generators_path(customer_id)`
- `category_label` — titleized category from metadata
- `kind_label` — `"Element Type"` or `"Step Action"` from `generator_kind`
- `generator_name` — fallback to `"unknown"`
- `version` — `metadata[:version]`
- `edit_path` — `edit_admin_maintenance_platform_code_generator_path(customer_id, slug: path)`
- `delete_path` — `admin_maintenance_platform_code_generator_path(customer_id, slug: path)`

Template structure (mirrors `PageBuilder::ToolbarComponent` lines 1–22 and
right-actions area, simplified):

```erb
<header class="bg-white border-b border-slate-200 flex-shrink-0 z-30">
  <div class="flex items-center h-12 px-4">
    <%# Left: back + breadcrumb-style title %>
    <div class="flex items-center gap-2 min-w-0">
      <%= link_to back_path, class: "...rounded-md...", title: "Back to Code Generators" do %>
        <svg ...> <!-- chevron-left, identical to page-edit toolbar --> </svg>
      <% end %>
      <div class="h-4 w-px bg-slate-200"></div>
      <div class="flex items-center gap-1.5 min-w-0">
        <span class="text-sm font-semibold text-slate-900 truncate"><%= category_label %></span>
        <span class="text-slate-300">/</span>
        <span class="text-sm font-mono text-slate-700 truncate"><%= generator_name %></span>
        <span class="text-[10px] font-medium text-slate-500 bg-slate-100 px-1.5 py-0.5 rounded">v<%= version %></span>
      </div>
    </div>

    <%# Center: empty (no tabs) — pushes actions to the right %>
    <div class="flex-1"></div>

    <%# Right: Edit + Delete %>
    <div class="flex items-center gap-1.5">
      <%= render ButtonComponent.new(tag: :a, variant: :primary, size: :sm, href: edit_path) do %>
        <svg ...><!-- pencil --></svg>
        Edit
      <% end %>
      <%= button_to delete_path, method: :delete,
          data: { turbo_confirm: "Delete this generator? This cannot be undone." },
          class: "#{ButtonComponent::BASE_CLASSES} #{ButtonComponent::VARIANTS[:danger]} #{ButtonComponent::SIZES[:sm]}" do %>
        <svg ...><!-- trash --></svg>
        Delete
      <% end %>
    </div>
  </div>
</header>
```

The chevron-left back-arrow SVG, vertical divider element (`h-4 w-px
bg-slate-200`), and breadcrumb-segment styling are reused verbatim from
`app/components/page_builder/toolbar_component.html.erb` so the visual
language matches.

### View rewrite: `show.html.erb`

`app/views/admin/maintenance/platform/code_generators/show.html.erb` becomes
edge-width and uses the same flex shell as `pages/_editor.html.erb`:

```erb
<% content_for :container_width, :edge %>

<div class="h-full flex flex-col bg-gray-100">
  <%= render Platform::CodeGenerators::ToolbarComponent.new(
    generator_class: @generator_class,
    path: params[:slug],
    customer_id: current_customer_id
  ) %>

  <div class="flex-1 flex overflow-hidden">
    <aside class="w-72 bg-gray-50/70 border-r border-gray-200/80 flex flex-col flex-shrink-0 overflow-y-auto">
      <%= render Platform::CodeGenerators::SidebarComponent.new(
        sidebar_data: @sidebar_data,
        search_index: @search_index || [],
        customer_id: current_customer_id,
        active_category: @generator_class&._metadata&.dig(:category).to_s,
        active_element_type: @generator_class&.generator_kind == :element_type ? @generator_class&.generator_name : nil,
        total_count: @step_actions&.size.to_i + @element_types&.size.to_i
      ) %>
    </aside>

    <main class="flex-1 overflow-y-auto bg-canvas">
      <%= render Platform::CodeGenerators::DetailComponent.new(
        generator_class: @generator_class,
        source_code: @source_code,
        path: params[:slug],
        customer_id: current_customer_id
      ) %>
    </main>
  </div>
</div>
```

The `turbo_frame_request?` branch is removed (see Turbo-frame nav below).

### `DetailComponent` cleanup

`app/components/platform/code_generators/detail_component.html.erb`:
- Delete the entire breadcrumb bar (current lines 2–28). The new
  `ToolbarComponent` owns back navigation, breadcrumb, and Edit/Delete
  actions.
- Keep the `<div class="p-6">` body (description, I/O, test runner, source).

`app/components/platform/code_generators/detail_component.rb`:
- Remove `back_url`, `kind_label`, `generator_name`, `category_label`,
  `edit_path`, `delete_path` — they were only used by the deleted header
  bar.
- Keep `metadata`, `test_result`, `input_keys`, `output_keys`, `deps`,
  `test_run_path`, `sample_json`, `sample_code`, `line_count`.

### Sidebar nav: drop turbo-frame swap

`app/components/platform/code_generators/sidebar_component.rb` line 111
currently emits `data: { turbo_frame: "generator-content" }` so clicking a
sidebar link only swaps the detail body. With the new shell, the **toolbar
breadcrumb + title** must update on each navigation, so frame-targeted
swaps no longer suffice.

Decision: drop the turbo frame entirely — sidebar links full-page navigate.
This matches the page-edit pattern (no in-page nav) and removes complexity.

Concrete changes:
- `sidebar_component.rb` line 111: remove `turbo_frame:` from the link's
  `data:` hash. Keep `generator-nav` Stimulus targets (used for active-state
  highlighting only).
- `show.html.erb`: remove the `turbo-frame#generator-content` wrapper.
- `detail_component.html.erb` / any other view: no remaining
  `turbo-frame#generator-content` references.

### Container width plumbing

Setting `content_for :container_width, :edge` in the show view propagates to
`ShellComponent` (already handles `:edge` at
`app/components/shell_component.html.erb:29` and suppresses the dashboard
sidebar at `shell_component.rb:19`). No shell changes required.

Note: `show_sidebar?` returns `false` when `container_width == :edge`. This
is already the behavior used by `pages/edit.html.erb`, and is what we want —
the dashboard's left rail collapses, leaving full width for the
generator's own sidebar + detail.

## Testing

- **rspec**: new component spec at
  `spec/components/platform/code_generators/toolbar_component_spec.rb`.
  Covers:
  - renders back link to index
  - renders category, generator name, version
  - renders Edit and Delete buttons with correct paths
  - delete button has turbo confirm
- Update / verify `spec/components/platform/code_generators/detail_component_spec.rb`
  if it asserted on the now-removed inner header.
- Manual verification: visit
  `/<cid>/admin/maintenance/code_generators` (or the platform-prefixed
  route), click any generator card, confirm the new toolbar renders, the
  back arrow returns to the index, Edit/Delete still function, sidebar nav
  swaps both the toolbar breadcrumb and detail body.

## Files touched

- `app/views/admin/maintenance/platform/code_generators/show.html.erb` (rewrite)
- `app/components/platform/code_generators/toolbar_component.rb` (new)
- `app/components/platform/code_generators/toolbar_component.html.erb` (new)
- `app/components/platform/code_generators/detail_component.html.erb` (remove inner header)
- `app/components/platform/code_generators/detail_component.rb` (remove unused helpers)
- `app/components/platform/code_generators/sidebar_component.rb` (drop turbo_frame data attr)
- `spec/components/platform/code_generators/toolbar_component_spec.rb` (new)
- `spec/components/platform/code_generators/detail_component_spec.rb` (update if affected)
