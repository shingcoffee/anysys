# UI Design Spec: Entity Attribute Table — Column Truncation

**Date:** 2026-06-04
**Status:** READY_FOR_FRONTEND
**Scope:** `_attributes_table.html.erb` (server-rendered) + `template_builder.js` `buildTableHtml` / `buildAttributeRowHtml` (client-rendered). Both surfaces must be byte-for-byte identical in visual output.

---

## 1. Surface Inventory

| Surface | File | Nav Area |
|---------|------|----------|
| Entity edit form — attributes table (editable) | `app/views/admin/maintenance/entities/_attributes_table.html.erb` | Maintenance/Modules |
| Entity show — attributes table (read-only, `editable: false`) | same partial, `editable: false` | Maintenance/Modules |
| JS live-build (on attribute add/edit) | `app/javascript/controllers/entity_form/template_builder.js` | Maintenance/Modules |

No new surfaces are introduced. The change is purely visual — constrained column widths + text truncation with tooltip.

---

## 2. Column Width Allocation

### Fixed columns (unchanged)

| Column | `<th>` class | Notes |
|--------|-------------|-------|
| Color bar | `w-12` | unchanged |
| Checkbox | `w-6` | unchanged |
| Drag handle | `w-6` | unchanged |
| Actions | `w-32` | unchanged, right-aligned |

Fixed overhead (editable mode): `3rem + 1.5rem + 1.5rem + 8rem = 14rem (224px)`

### Data columns — NEW explicit widths

These replace the currently width-less `<th>` elements. Total of the five data columns must comfortably fill the remaining space in a 1024px–1440px admin viewport after the fixed overhead (~224px), giving roughly 800–1216px to distribute.

| Column | `<th>` width class | Rationale |
|--------|--------------------|-----------|
| **Name** | `w-44` (176px) | Internal machine key; typically `snake_case`, moderate length. Generous enough for "subscription_renewal_date" at 13px body-sm. |
| **Display Label** | `w-48` (192px) | Human-readable, can be longer than Name; slightly wider. |
| **HTML Type** | `w-28` (112px) | Single badge, longest value is ~"datetime-local" (~95px badge). |
| **Validators** | `w-44` (176px) | Typically 0–3 short badges; wrapping handled within cell. |
| **Visibility** | `w-40` (160px) | Always exactly 3 badges ("Admin", "Member", "Public") at ~48px each + gaps. |

**Width sum check (editable mode):**
`w-12 + w-6 + w-6 + w-44 + w-48 + w-28 + w-44 + w-40 + w-32`
= `3 + 1.5 + 1.5 + 11 + 12 + 7 + 11 + 10 + 8 = 65rem (1040px)`

This fits a 1024px content area at exactly full width and gracefully overflows into the existing `overflow-x-auto` wrapper on narrower viewports. At 1280px+ the browser distributes no extra width (table-fixed), so text columns truncate and the layout remains tidy.

**Non-editable mode** (no color bar / checkbox / drag handle columns):
The same five data-column widths apply; the Actions column becomes `w-32` and reads fine because the three narrow fixed columns drop out.

---

## 3. Cell-Content Pattern per Column

### 3a. Text columns: Name and Display Label

The `<td>` must contain a single inline element (not a bare text node) so `truncate` + `title` can be applied precisely.

**ERB pattern (server-side):**

```html
<td class="px-3 py-3 w-44">
  <span class="block truncate text-sm font-medium text-text-primary cursor-help"
        title="<%= attr["name"] %>">
    <%= attr["name"] %>
  </span>
</td>
```

```html
<td class="px-3 py-3 w-48">
  <span class="block truncate text-body-sm cursor-help"
        title="<%= display_label %>">
    <%= display_label %>
  </span>
</td>
```

Key points:
- `block` — makes the span fill the cell width so `truncate` (which requires `overflow:hidden` on a block box) functions correctly inside a `table-fixed` cell.
- `truncate` — Tailwind utility: `overflow-hidden text-ellipsis whitespace-nowrap`.
- `title="<full text>"` — native tooltip; always present regardless of truncation. This matches the `buildTruncatedDescriptionHtml` and `truncate_with_tooltip` precedent in the codebase.
- `cursor-help` — signals to the user that a tooltip is available; consistent with the existing `truncate_with_tooltip` helper.
- Do NOT add `max-w-full` explicitly; `table-fixed` + `w-44`/`w-48` on the `<th>` already constrains the column. The `block` span naturally fills that width.

**JS pattern (client-side, `buildAttributeRowHtml`):**

```js
// Name cell
<td class="px-3 py-3 w-44" data-field="name">
  <span class="block truncate text-sm font-medium text-text-primary cursor-help"
        title="${escapeHtml(name)}">${escapeHtml(name)}</span>
</td>

// Display Label cell
<td class="px-3 py-3 w-48" data-field="display_label">
  <span class="block truncate text-body-sm cursor-help"
        title="${escapeHtml(displayLabel)}">${escapeHtml(displayLabel)}</span>
</td>
```

Note: `data-field` attribute moves from the `<span>` to the `<td>` in this refactor. The JS `entity_form_controller.js` reads `.querySelector('[data-field="name"]')` — verify that it targets the `<td>` not the inner `<span>`, and adjust the querySelector to use `.textContent` via the `<td>` if needed. If it reads `element.textContent` the move is safe. If it reads `element.innerHTML` directly, keep `data-field` on the `<span>` instead and the `block truncate` classes still work correctly.

### 3b. HTML Type column

Single `<span class="badge badge-success">` badge. The badge's padding (`px-2 py-0.5`) and `inline-flex` display mean it does not overflow the `w-28` cell for any known HTML type label (longest: "datetime-local" renders as "Date & Time" or similar, roughly 80px). No truncation needed.

**ERB pattern (no change to badge markup, only add width to `<th>`):**

```html
<td class="px-3 py-3">
  <span class="badge badge-success" data-field="html_type">
    <%= HtmlTypeOptions.label_for(attr["html_type"]) %>
  </span>
</td>
```

The `<td>` needs no width class because `table-fixed` derives the cell width from the `<th>`. If a label somehow exceeds `w-28`, the badge will just clip (its text does not have `truncate`, so it would visually overflow the badge boundary into the next cell). This is acceptable because no current label is long enough to trigger this. If future label length becomes a concern, wrap the badge text in a `<span class="block truncate max-w-full">` inside the badge element.

**JS pattern:** The JS already renders the badge with raw classes; add `w-28` to the `<th>` in `buildTableHtml` (header section).

### 3c. Validators column

Badges are rendered by `render_validator_badges` (ERB) / `buildValidatorBadgesHtml` (JS). Each badge already has a `title` attribute set to the validator type string. The wrapping `<div class="flex items-center gap-1 flex-wrap">` allows badges to wrap onto multiple lines within `w-44`.

**No changes to badge markup.** Add only the width class to the `<th>`.

Overflow strategy: allow wrapping (`flex-wrap` already present). Do NOT add `overflow-hidden` or truncation on the validator container — individual badge titles already provide tooltip context, and cutting off badges would hide validators silently.

If a cell has many validators and wraps to three or more lines, the row height increases naturally. This is acceptable — it is the current behavior too, just now bounded horizontally.

### 3d. Visibility column

Three fixed badges always rendered by `render_attribute_visibility_badges` / `buildVisibilityBadgesHtml`. Labels are "Admin", "Member", "Public" — fixed and short. The `w-40` allocation fits all three badges + gaps in a single line on any viewport.

**No changes to badge markup.** Add only the width class to the `<th>`.

---

## 4. Header `<th>` — Complete Updated List

**ERB (`_attributes_table.html.erb`):**

```erb
<th scope="col" class="w-12"></th>                                       <%# color bar — editable only %>
<th scope="col" class="w-6"></th>                                        <%# checkbox — editable only %>
<th scope="col" class="w-6"></th>                                        <%# drag handle — editable only %>
<th scope="col" class="px-3 py-3 text-left w-44">Name</th>
<th scope="col" class="px-3 py-3 text-left w-48">Display Label</th>
<th scope="col" class="px-3 py-3 text-left w-28">HTML Type</th>
<th scope="col" class="px-3 py-3 text-left w-44">Validators</th>
<th scope="col" class="px-3 py-3 text-left w-40">Visibility</th>
<th scope="col" class="px-3 py-3 text-right w-32">Actions</th>           <%# editable || show_view_action %>
```

**JS (`buildTableHtml` in `template_builder.js`):**

```js
<th class="w-12"></th>
<th class="w-6"></th>
<th class="w-6"></th>
<th class="pb-3 px-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-44">Name</th>
<th class="pb-3 px-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-48">Display Label</th>
<th class="pb-3 px-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-28">HTML Type</th>
<th class="pb-3 px-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-44">Validators</th>
<th class="pb-3 px-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-40">Visibility</th>
<th class="pb-3 px-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider w-32">Actions</th>
```

Note: JS-rendered `<thead>` currently uses raw Tailwind gray utilities (`text-gray-500`) instead of design-token classes (`text-text-tertiary`). The frontend developer may harmonize these with design-token classes at the same time, matching the ERB's `<thead class="table-header">`. This is optional but recommended.

---

## 5. ASCII Row Mockup

Editable mode (full column set, ~1280px viewport):

```
|   |  |  | Name           | Display Label    | HTML Type  | Validators              | Visibility                    | Actions |
|---|--|--|----------------|-----------------|-----------|------------------------|-------------------------------|---------|
| ▌ | □ |⋮⋮| my_very_long_a… | My Very Long At… | Text      | [Required] [Min: 5]    | [Admin] [Member] [Public]| 👁 ⎘ ✎ 🗑 |
| ▌ | □ |⋮⋮| email           | Email Address   | Email     | [Required] [Email]     | [Admin] [Member] [~~Pub~~]| ✎ 🗑 |
| ▌ | □ |⋮⋮| notes           | Notes           | Textarea  | -                      | [Admin] [~~Con~~] [~~Pub~~]   | ✎ 🗑 |
```

Columns with text that fits do not truncate. Columns with long text show `…` at the column boundary and reveal the full string in the native browser tooltip on hover.

---

## 6. Component Reuse Map

No new components needed. This is a class-only change to existing partial and JS string template.

| Element | Reused as-is | Change |
|---------|-------------|--------|
| `_attributes_table.html.erb` | Yes | Add width classes to `<th>`; wrap Name/Display Label cell text in `<span class="block truncate ... cursor-help" title="...">` |
| `template_builder.js` — `buildTableHtml` | Yes | Add width classes to `<th>` strings |
| `template_builder.js` — `buildAttributeRowHtml` | Yes | Wrap Name/Display Label text in `<span class="block truncate ... cursor-help" title="...">` |
| `EntityAttributeDisplayHelper#render_attribute_visibility_badges` | Unchanged | `<th>` width class change only |
| `ValidatorDisplayHelper#render_validator_badges` | Unchanged | `<th>` width class change only |

---

## 7. Tailwind & Stimulus Notes

### Tailwind utilities

- `table-fixed` — already on `<table>`; mandatory for column-width control to work.
- `w-44`, `w-48`, `w-28`, `w-40` — new width classes on the five data `<th>` elements.
- `block` — on the `<span>` inside Name/Display Label cells. Without `block`, the span is `inline` and `overflow-hidden` does not apply. `block` makes the span stretch to the cell width.
- `truncate` — Tailwind utility (`overflow-hidden whitespace-nowrap text-ellipsis`). Applied to the `<span>` inside Name/Display Label cells.
- `cursor-help` — always present on Name/Display Label spans to signal tooltip availability.
- All text color/weight classes (`text-sm font-medium text-text-primary`, `text-body-sm`) remain exactly as they are today.

### Stimulus

No Stimulus controller changes required. The truncation is purely CSS-based. The `entity-form` controller's existing `data-field` attribute selectors are unaffected as long as `data-field` remains on the `<td>` (current ERB) or `<span>` (current JS). See note in Section 3a about where `data-field` lives.

### Responsive behavior

The outer `<div class="overflow-x-auto">` wrapper already handles mobile viewport overflow by providing horizontal scroll. The new fixed widths total ~65rem — on screens narrower than 65rem (1040px), the table scrolls horizontally. This is identical to the current behavior, just now with well-defined column proportions rather than browser-guessed widths.

---

## 8. States

| State | Appearance |
|-------|-----------|
| Normal (text fits) | Text renders fully, no ellipsis, `cursor-help` still present (native title is always-on) |
| Truncated (text overflows) | Ellipsis at column right edge; hovering shows full text via native browser tooltip |
| Empty Name/Display Label | The `display_label` fallback to `attr["name"]` already handles this; no empty-state badge needed |
| Zero validators | `render_validator_badges` / `buildValidatorBadgesHtml` already render `"-"` placeholder; no change |
| All visibility disabled | All three visibility badges render with `line-through` class; badges still fit in `w-40` |
