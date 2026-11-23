# Page Builder Toolbar Refactor

## Summary

Extract the page builder top toolbar from the monolithic `_editor.html.erb` template into a `PageBuilder::ToolbarComponent` ViewComponent, and apply a Gutenberg-style visual refresh for functional density with clear grouping.

## Goals

1. **Visual density**: More compact, professional toolbar within the existing 48px height
2. **Component structure**: Extract into a ViewComponent for maintainability (the template is 1200+ lines)

## Non-Goals

- No changes to the Stimulus controller (`page_builder_controller.js`)
- No changes to toolbar functionality or behavior
- No changes to other parts of the editor template beyond replacing the toolbar block

## Visual Design

Style reference: WordPress Gutenberg — functional density, grouped icon buttons, clear visual separation.

### Left Section (Navigation & Context)

- Back arrow button + page name + optional entity breadcrumb
- Remove the indigo square page icon (unnecessary chrome)
- Tighten gaps from `gap-3` to `gap-2`
- Page name is the primary visual landmark

### Center Section (Tabs)

- 5 icon-only buttons in a tight button group with `bg-slate-100` backing
- Each button: `p-2` square with `title` tooltip for accessibility
- Active state: `bg-white shadow-sm text-indigo-600` pill within the group
- Inactive: `text-slate-500 hover:text-slate-700`
- No text labels — icons are sufficiently distinctive:
  - Templates: layout grid icon
  - Theme: palette icon
  - Rules: clipboard-check icon
  - Calculations: calculator icon
  - Settings: gear icon

### Right Section (Actions)

- Viewport toggle group (desktop/tablet/mobile)
- Undo/redo button pair
- Preview: icon-only with tooltip (matches Gutenberg pattern)
- Save: stays as labeled button (primary CTA, `bg-indigo-600`)
- Tighten gaps from `gap-2` to `gap-1.5`

### Global Style Changes

- Dividers: `h-4 w-px bg-slate-200` (shorter, subtler)
- Migrate color palette from `gray-*` to `slate-*` (matches flowchart editor)
- Border: `border-slate-200`

## Component Structure

### `PageBuilder::ToolbarComponent`

**Files:**
- `app/components/page_builder/toolbar_component.rb`
- `app/components/page_builder/toolbar_component.html.erb`

**Constructor params:**
- `page` — the `@page` ActiveRecord model
- `customer_id` — integer, the current customer ID
- `selected_entity` — nullable Entity model

**Template structure:**
```
<header class="bg-white border-b border-slate-200 flex-shrink-0 z-30">
  <div class="flex items-center h-12 px-4">
    <!-- Left: nav -->
    <!-- Center: icon tabs -->
    <!-- Right: actions (includes hidden preview form) -->
  </div>
</header>
```

**No sub-components** — all three sections render inline. The toolbar is one logical unit; splitting would be premature abstraction.

### Template Change

In `_editor.html.erb`, replace the `<header>...</header>` block (current lines 27-187) with:

```erb
<%= render PageBuilder::ToolbarComponent.new(
  page: @page,
  customer_id: current_customer_id,
  selected_entity: selected_entity
) %>
```

### What Stays Unchanged

- All `data-page-builder-target` attributes (same target names)
- All `data-action` bindings (same controller actions)
- `page_builder_controller.js` and all sub-managers
- Tab panel overlays (they reference `tabButton` targets which remain)
- The hidden preview form moves into the component (stays functionally identical)

## Testing

- Verify all 5 tab buttons switch panels correctly
- Verify viewport toggle updates canvas frame
- Verify undo/redo buttons enable/disable appropriately
- Verify preview opens in new tab
- Verify save persists configuration
- Verify entity breadcrumb link works when entity is present
- Verify toolbar renders correctly when no entity is selected
