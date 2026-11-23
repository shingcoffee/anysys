# Visual Foundation Design Spec

**Date:** 2026-03-26
**Scope:** Establish a consistent design system (color, spacing, typography, depth) across the flowchart editor
**Style Reference:** Webflow/Retool — professional, structured, visible affordances

---

## Overview

Migrate the editor from ad-hoc `gray-*` Tailwind classes to a deliberate `slate-*` design system. Slate's subtle blue undertone pairs better with the indigo primary color and gives a cooler, more professional feel. Standardize spacing, typography, and depth layering across all panels.

**What changes:** Colors, spacing, typography consistency, shadow/depth hierarchy.
**What does NOT change:** Layout structure (widths, positions), element type colors, canvas SVG rendering, functional behavior.

---

## Change 1: Color Migration (gray → slate)

**Rule:** Every `gray-*` Tailwind class becomes the equivalent `slate-*` class across all editor files. This is a mechanical find-and-replace with no exceptions — the editor's neutral palette moves entirely to slate.

Examples:
- `bg-gray-50` → `bg-slate-50`
- `border-gray-200` → `border-slate-200`
- `text-gray-700` → `text-slate-700`
- `hover:bg-gray-50` → `hover:bg-slate-50`
- `placeholder-gray-400` → `placeholder-slate-400`
- `placeholder:text-gray-400` → `placeholder:text-slate-400`

**Files:**

| File | Scope |
|------|-------|
| `app/views/flowcharts/_editor.html.erb` | All gray classes in template |
| `app/components/flowchart_elements/base_element_component.rb` | `base_classes` method |
| `app/javascript/controllers/flowchart_canvas_controller.js` | Dynamic HTML strings (~15 occurrences) |
| `app/javascript/controllers/property_editor/form_builder.js` | Input/label classes (~3 occurrences) |
| `app/javascript/controllers/property_editor/templates.js` | Template HTML strings (~85 occurrences) |
| `app/javascript/controllers/property_editor/step_manager.js` | Step UI classes |
| `app/javascript/controllers/property_editor/branch_manager.js` | Branch UI classes (~13 occurrences) |
| `app/javascript/controllers/property_editor/io_manager/input_operations.js` | Input mapping UI |
| `app/javascript/controllers/property_editor/io_manager/output_operations.js` | Output mapping UI |

**Does NOT touch:** Element-specific color classes (green, red, blue, amber, purple, orange in component subclasses and `ELEMENT_COLORS` constant).

---

## Change 2: Surface Hierarchy

Four named surface levels applied consistently:

| Surface | Class | Usage |
|---------|-------|-------|
| Canvas | `bg-slate-100` | Canvas workspace background (was `bg-gray-50` in `canvasContainer` and `bg-gray-50` in canvas area) |
| Panel | `bg-white` | Toolbar, left sidebar, right sidebar, bottom panel body |
| Panel-inset | `bg-slate-50` | Tab bar, section headers, input backgrounds, table headers |
| Panel-hover | `hover:bg-slate-50` | List item hovers, button hovers within panels |

**Specific changes:**
- **Left sidebar:** `bg-gray-50` → `bg-white` (becomes a Level 1 panel like other sidebars)
- **Canvas container:** `bg-gray-50` → `bg-slate-100` (darker, creates contrast with white panels)
- **Bottom panel tab bar:** `bg-gray-50` → `bg-slate-50` (already close, just slate migration)
- **Overflow menu hovers:** `hover:bg-gray-50` → `hover:bg-slate-50`

**Files:**
- `app/views/flowcharts/_editor.html.erb` — sidebar bg, canvas container bg

---

## Change 3: Border Hierarchy

| Border | Class | Usage |
|--------|-------|-------|
| Default | `border-slate-200` | Panel edges (toolbar bottom, sidebar edges, panel top) |
| Subtle | `border-slate-100` | Internal separators (between list items, form sections) |
| Focus | `focus:ring-indigo-500 focus:border-indigo-500` | Input focus states |

Already largely correct after the gray→slate migration. This is a verification step — ensure no `border-gray-300` remains on panel edges (should be `border-slate-200`).

**Files:** Covered by Change 1 migration.

---

## Change 4: Typography Scale

Standardize text treatment across the editor:

| Role | Classes | Usage |
|------|---------|-------|
| Panel title | `text-sm font-semibold text-slate-900` | Property editor header, panel headings |
| Section header | `text-[10px] font-medium uppercase tracking-wider text-slate-500` | ELEMENTS, FLOWS in sidebar; field group headers |
| Field label | `text-xs font-medium text-slate-500` | Form field labels in property editor |
| Field value | `text-sm text-slate-900` | Input text, select values |
| Body text | `text-sm text-slate-600` | Descriptions, help text |
| Muted text | `text-xs text-slate-400` | Placeholders, secondary info |
| Active tab | `text-xs font-medium text-indigo-600` | Active bottom panel tab |
| Inactive tab | `text-xs font-medium text-slate-500` | Inactive bottom panel tabs |

**Specific changes:**
- **Property editor title:** `text-lg font-medium text-gray-900` → `text-sm font-semibold text-slate-900` (line ~504 in _editor.html.erb)
- **Tab labels:** Already `text-xs font-medium` — just needs gray→slate

**Files:**
- `app/views/flowcharts/_editor.html.erb` — property editor header
- Covered by Change 1 migration for other typography

---

## Change 5: Depth & Shadow Hierarchy

Four elevation levels:

| Level | Usage | Treatment |
|-------|-------|-----------|
| 0 — Canvas | Workspace | `bg-slate-100`, no shadow (recessed) |
| 1 — Chrome | Toolbar, sidebars, bottom panel | `bg-white`, `border-slate-200` edges only |
| 2 — Floating | Overflow menu, context menu, search bar | `bg-white shadow-lg ring-1 ring-slate-200 rounded-lg` |
| 3 — Modal | Step modal, branch modal | `bg-white shadow-xl` |

**Specific changes:**
- **Bottom panel:** Add `shadow-sm` to give subtle lift above canvas (currently no shadow, just border-t)
- **Overflow menu:** Already has `shadow-lg ring-1 ring-black/5` — change to `shadow-lg ring-1 ring-slate-200` for consistency
- **Context menu:** Same as overflow — `shadow-lg ring-1 ring-slate-200`
- **Shortcut panel:** Currently `shadow-lg` — add `ring-1 ring-slate-200` for consistency
- **Search bar:** Currently `shadow-lg` — add `ring-1 ring-slate-200` for consistency

**Files:**
- `app/views/flowcharts/_editor.html.erb` — bottom panel, overlay elements
- `app/javascript/controllers/flowchart_canvas_controller.js` — context menu dynamic HTML

---

## Files Impact Summary

| File | Changes |
|------|---------|
| `app/views/flowcharts/_editor.html.erb` | 1, 2, 4, 5 |
| `app/components/flowchart_elements/base_element_component.rb` | 1 |
| `app/javascript/controllers/flowchart_canvas_controller.js` | 1, 5 |
| `app/javascript/controllers/property_editor/form_builder.js` | 1 |
| `app/javascript/controllers/property_editor/templates.js` | 1 |
| `app/javascript/controllers/property_editor/step_manager.js` | 1 |
| `app/javascript/controllers/property_editor/branch_manager.js` | 1 |
| `app/javascript/controllers/property_editor/io_manager/input_operations.js` | 1 |
| `app/javascript/controllers/property_editor/io_manager/output_operations.js` | 1 |
