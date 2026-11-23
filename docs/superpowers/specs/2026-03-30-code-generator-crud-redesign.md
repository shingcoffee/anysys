# Code Generator CRUD Pages Redesign

## Overview

Refactor the admin code generator management pages (index, show, new/edit) for visual consistency with the rest of the application and improved polish. Replace hand-rolled HTML with shared ViewComponents, standardize layout patterns, and improve information hierarchy.

## What Stays The Same

- Two-panel index layout (collapsible sidebar tree + card grid) — appropriate for hierarchical generator data
- Two show modes: inline turbo-frame `DetailPanelComponent` (from index sidebar) + full-page `ShowComponent` (direct URL)
- Stimulus controllers: `generator-search`, `generator-nav`, `generator-form`
- All existing CRUD functionality and routes

## Changes

### Index Page (`IndexComponent`)

**Layout:**
- Container width: `max-w-screen-2xl` → `max-w-[1400px] mx-auto px-4 py-8` (app standard)
- Replace inline badge HTML with `BadgeComponent` (variant mapped to element type)
- Replace inline button/link HTML with `ButtonComponent`
- Use `EmptyStateComponent` when no generators exist
- Standardize card styling: consistent `bg-white rounded-xl border border-gray-200 shadow-sm` pattern
- Clean up sidebar tree: use consistent text sizes, spacing, and hover states matching app conventions

### Show Page — Full (`ShowComponent`)

**Layout:**
- Container width: `max-w-screen-xl` → `max-w-[1400px] mx-auto px-4 py-8`
- Breadcrumb: match other show pages — simple back link with `text-sm text-gray-500 hover:text-gray-700`
- Header: title + action buttons in `flex items-center justify-between` row
- Actions: use `ButtonComponent` (primary for edit, danger for delete)
- Metadata: use `BadgeComponent` for version, category, input/output schema counts
- Source code and example output: use `CodeBlockComponent`

### Show Page — Inline (`DetailPanelComponent`)

**Layout:**
- Compact card within turbo-frame, consistent with full show page styling
- Back button: `ButtonComponent` variant ghost, size sm
- Actions: `ButtonComponent` for edit/delete, matching full show page
- Metadata badges: same `BadgeComponent` usage as full show
- Source/example: `CodeBlockComponent` (compact mode if available)

### New/Edit Form (`FormComponent`)

**Layout:**
- Single-column form (remove the side-by-side preview panel)
- Container: `max-w-3xl mx-auto px-4 py-8`
- Breadcrumb: back link matching other form pages
- Validation errors: `AlertComponent` type error, replacing custom red box
- Form fields: standardized label/input styling matching other app forms (`text-sm font-medium text-gray-700` labels, `w-full rounded-lg border-gray-300` inputs)
- Preview section: collapsible section below the form, using `CodeBlockComponent` for the generated source, triggered by the existing `generator-form` Stimulus controller

### Views (`new.html.erb`, `edit.html.erb`)

- Ensure they follow the same pattern as other admin views — render the component with minimal wrapper

## Shared Components Used

| Component | Where Used |
|-----------|-----------|
| `ButtonComponent` | All pages — actions, navigation, back links |
| `BadgeComponent` | Index cards, show metadata (version, category, schema counts) |
| `AlertComponent` | Form validation errors |
| `EmptyStateComponent` | Index when no generators |
| `CodeBlockComponent` | Show pages (source, example output), form preview |

## Testing

- Existing controller specs (`spec/controllers/admin/code_generators_controller_spec.rb`) verify CRUD behavior — update if response structure changes
- ViewComponent specs verify rendering with shared components
- No new feature logic — this is a presentation-layer refactor
