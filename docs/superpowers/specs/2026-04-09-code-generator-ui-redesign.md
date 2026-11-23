# Code Generator Pages UI Redesign

**Date:** 2026-04-09
**Status:** Approved
**Scope:** All code generator admin pages — index, show, detail panel, form (new/edit)

## Goals

- Align code generator pages with the application's existing light theme (entity pages)
- Improve navigation with lazy-loaded category browsing instead of loading all 125 generators at once
- Merge duplicated DetailPanelComponent and ShowComponent into one unified component
- Modernize the aesthetic to a clean SaaS dashboard feel (Linear/Vercel-inspired)
- Improve the authoring workflow with side-by-side code editing and live preview

## Architecture: Sidebar + Adaptive Content

Single-page master-detail pattern. A fixed sidebar handles all navigation. The main content area has two states:

1. **Card Grid** — browsing generators within a selected category
2. **Detail View** — viewing a specific generator's details, I/O, test runner, and source code

State transitions happen via Turbo Frame replacement of the main content area. The sidebar remains fixed throughout.

### Pages

| Page | Route | Description |
|------|-------|-------------|
| Index | `GET /admin/code_generators` | Sidebar + card grid (default: no category selected, or first category) |
| Index (category) | `GET /admin/code_generators?category=model_operations` | Sidebar + card grid filtered to category |
| Index (detail) | `GET /admin/code_generators/:path` | Sidebar + detail view (loaded in turbo frame) |
| New | `GET /admin/code_generators/new` | Form page with side-by-side layout |
| Edit | `GET /admin/code_generators/:path/edit` | Form page with side-by-side layout |

### Component Changes

| Component | Action |
|-----------|--------|
| `IndexComponent` | Complete rewrite — sidebar + adaptive content area |
| `DetailPanelComponent` | Merge into new unified `DetailComponent` |
| `ShowComponent` | Remove — absorbed into `DetailComponent` |
| `FormComponent` | Rewrite with side-by-side layout |
| `show.html.erb` view | Remove — no standalone show page |

## Sidebar Design

The sidebar is a fixed-width (`w-64`) white panel on the left, pinned to the viewport height with independent scrolling.

### Structure (top to bottom)

1. **Header**: App icon + "Code Generators" title + total count subtitle
2. **Search**: Text input with placeholder "Search generators..." — searches across all generators globally, not filtered by current category
3. **Element Types section**: Label + flat list of element types (Start, End, Decision, Loop, Timer, Error Handler, Subflow, Fork, Join). Each item shows a colored dot, name, and generator count badge.
4. **Step Actions section**: Label + flat list of step action subcategories (Model Operations, Validation, Data Operations, Communication, Security, Background, File Operations, Realtime, Response). Each item shows an icon, name, and count badge.
5. **New Generator button**: Pinned to the bottom of the sidebar with `mt-auto`. Primary indigo button.

### Sidebar Behavior

- **No nesting/collapsible tree**: The sidebar is a flat list. Clicking a category loads its generators in the main content area.
- **Active state**: Selected category gets `bg-indigo-50 text-indigo-700` with an indigo count badge.
- **Inactive state**: `text-gray-500 hover:bg-gray-50 hover:text-gray-700`
- **Turbo Frame**: Clicking a category triggers a Turbo Frame request that replaces only the main content area.

## Card Grid (Browse State)

Shown when a category is selected and no specific generator is active.

### Top Bar

- Category icon + name + generator count badge
- Background: white with `border-b border-gray-200`

### Cards

- Layout: `grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3`
- Card styling: `bg-white border border-gray-200 rounded-lg shadow-sm`
- Card hover: `hover:border-indigo-300 hover:shadow-md transition-all`
- Card content:
  - **Name**: `font-mono text-sm font-semibold text-gray-900`
  - **Version**: `text-[10px] text-gray-400 bg-gray-100 rounded px-1.5`
  - **Description**: `text-xs text-gray-500 line-clamp-2`
  - **Footer** (separated by `border-t border-gray-100`): I/O counts with colored dots — amber dot + "N in", green dot + "N out", right chevron
- Cards are links that load the detail view via Turbo Frame

### Empty State

When a category has no generators, show the existing `EmptyStateComponent` with a "New Generator" action.

## Detail View (Generator Selected State)

Replaces the card grid via Turbo Frame. Sidebar stays fixed.

### Top Bar (Breadcrumb)

- "← Back" link (indigo, returns to card grid via Turbo Frame)
- Separator dot
- Category name (gray)
- Slash separator
- Generator name (`font-mono font-semibold text-gray-900`)
- Version badge
- Right-aligned: Edit button (primary indigo) + Delete button (outlined red)

### Description

- `text-sm text-gray-500` with `max-w-2xl`

### I/O Panel

Horizontal flow layout with three sections side by side:

| Section | Background | Border | Dot Color | Label Color | Badge Colors |
|---------|-----------|--------|-----------|-------------|--------------|
| Inputs | `bg-amber-50` | `border-amber-200` | `bg-amber-500` | `text-amber-800` | `bg-white text-amber-900 border-amber-200` |
| Outputs | `bg-green-50` | `border-green-200` | `bg-green-500` | `text-green-800` | `bg-white text-green-900 border-green-200` |
| Dependencies | `bg-indigo-50` | `border-indigo-200` | `bg-indigo-500` | `text-indigo-800` | `bg-white text-indigo-900 border-indigo-200` |

- Arrow separator (`→` in `text-gray-300`) between Inputs and Outputs
- Each section has an uppercase label and flex-wrapped monospace `ctx[:key]` badges
- Inputs and Outputs sections are `flex-1`, Dependencies is `flex-[0.6]`
- "derived from code" note not needed — the info tip in the form page covers this

### Test Runner

Split-pane design inside a white card:

- **Header**: Dot + "Test Runner" label + "Run Test" button (primary indigo) on the right
- **Left pane** (config): "Config (JSON)" label + textarea pre-filled with `sample_input`. Background `bg-gray-50` with `border-gray-200`.
- **Right pane** (output): "Generated Output" label + code output area. Shows placeholder text until test is run.
- **Pane separator**: `border-r border-gray-100`
- **Results**: After running, the output pane shows syntax-highlighted generated code. I/O badges appear above the output. Validation errors show in a red alert box.

### Source Code

- Collapsible section (default: collapsed)
- Header: chevron + "Source Code" label + line count + filename
- Content: Light gray background (`bg-gray-50`) with line numbers and syntax highlighting
- Uses existing `CodeBlockComponent` adapted for light theme

## Form Page (New/Edit)

### Layout

Side-by-side layout: form on the left, live source preview on the right.

### Top Bar

- "← Back" link + "Edit Generator" / "New Generator" title
- Generator name and version badge (edit mode)
- "auto-increments on save" note (edit mode)
- Right-aligned: Cancel (secondary) + Save Changes (primary indigo) buttons

### Left Column: Form

#### Identity Section (Create Mode Only)

- Card with indigo dot + "Generator Identity" label + "create only" badge
- 3-column grid: Kind (select), File Name (text input), Category (select)
- Hidden in edit mode (values passed as hidden fields)

#### Metadata Section

- Card with indigo dot + "Metadata" label
- 2-column grid: Description (2/3 width) + Category (1/3 width, edit mode shows select)
- Registration: Registered names input (monospace, comma-separated)
- Info tip: `bg-indigo-50 border-indigo-200` explaining ctx[:key] I/O derivation

#### Code Editor (Hero Element)

- Card with green dot + "Methods" label + hint text listing method types
- **Dark textarea background** (`bg-[#1e1e2e]` — Catppuccin Mocha): This is the one intentionally dark element in the entire UI, providing contrast and focus for code editing, like an embedded code editor widget.
- Textarea: `font-mono text-sm leading-relaxed text-gray-100`
- Tab key inserts 2 spaces (existing behavior preserved)
- Triggers debounced preview update on input (existing behavior preserved)

### Right Column: Live Source Preview

- Fixed width (`w-[420px]`), always visible — not hidden in a collapsible
- Header: purple dot + "Generated Source Preview" + line count
- Content: Light gray background (`bg-gray-50`) with line numbers and syntax highlighting
- Updates live as the user edits the form (debounced 300ms via existing Stimulus controller)

### Form Input Styling

All form inputs follow the app convention:
- `bg-gray-50 border border-gray-200 text-gray-900 rounded-lg`
- `focus:ring-indigo-500 focus:border-indigo-500`
- Labels: `text-xs font-medium text-gray-500`

## Visual System

### Color Palette

| Element | Class |
|---------|-------|
| Page background | `bg-gray-50` |
| Cards/panels | `bg-white border border-gray-200 rounded-lg shadow-sm` |
| Primary accent | `indigo-600` (buttons, active states, links) |
| Active sidebar item | `bg-indigo-50 text-indigo-700` |
| Hover | `hover:bg-gray-50` (sidebar), `hover:border-indigo-300 hover:shadow-md` (cards) |
| Headings | `text-gray-900` |
| Body text | `text-gray-500` / `text-gray-600` |
| Muted text | `text-gray-400` |
| Code/names | `font-mono` |
| Input fields | `bg-gray-50 border-gray-200 focus:ring-indigo-500` |

### Semantic Colors

| Semantic | Light BG | Border | Text | Dot |
|----------|---------|--------|------|-----|
| Inputs (I/O) | `bg-amber-50` | `border-amber-200` | `text-amber-800` | `bg-amber-500` |
| Outputs (I/O) | `bg-green-50` | `border-green-200` | `text-green-800` | `bg-green-500` |
| Dependencies | `bg-indigo-50` | `border-indigo-200` | `text-indigo-800` | `bg-indigo-500` |
| Element type dots | Per-type colors (green, red, amber, violet, cyan, pink, etc.) |

### Interactive Effects

- Card hover: `hover:border-indigo-300 hover:shadow-md transition-all duration-200`
- Sidebar hover: `hover:bg-gray-50 hover:text-gray-700 transition-colors`
- Button hover: follows existing ButtonComponent conventions
- Collapsible chevron rotation: existing behavior preserved

## Stimulus Controllers

### Existing Controllers to Update

| Controller | Changes |
|-----------|---------|
| `generator_search_controller.js` | Update selectors for new sidebar structure. Search now filters sidebar items and optionally triggers a server-side search. |
| `generator_nav_controller.js` | Simplified — active state is now `bg-indigo-50 text-indigo-700` on sidebar items. No more tree branch highlighting. |
| `generator_form_controller.js` | No major changes — preview still debounces on input. Tab handling preserved. Preview panel target moves to right column. |
| `generator_test_runner_controller.js` | No major changes — same functionality, updated markup selectors if needed. |
| `collapsible_controller.js` | Still used for source code collapsible. No longer needed for sidebar tree. |

## Routing Changes

The controller needs a new action or parameter to support category-based loading:

```ruby
# Existing
resources :code_generators, only: [:index, :show, :new, :create, :edit, :update, :destroy], param: :path

# The index action should accept a `category` param to filter generators
# GET /admin/code_generators?category=model_operations&kind=step_action
# GET /admin/code_generators?element_type=start
```

The index action renders:
- With no Turbo Frame request and no path: full page (sidebar + card grid for first/default category)
- With no Turbo Frame request and a path (e.g. direct URL visit): full page (sidebar + detail view for that generator)
- With Turbo Frame `generator-content` request + category param: just the card grid partial
- With Turbo Frame `generator-content` request + path param: just the detail view partial

This ensures direct URLs (bookmarks, shared links) still work — they render the full page with the detail view pre-loaded.

## Migration Path

1. Create new `DetailComponent` (merged from DetailPanel + Show)
2. Rewrite `IndexComponent` with sidebar + adaptive content
3. Rewrite `FormComponent` with side-by-side layout
4. Update Stimulus controllers for new markup
5. Remove `ShowComponent` and `DetailPanelComponent`
6. Remove `show.html.erb` view
7. Update routes (remove standalone show, add category filtering)
8. Update controller to handle Turbo Frame category/detail requests
