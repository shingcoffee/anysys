# Attribute View Modal Redesign — UX Spec
**Date:** 2026-06-04
**Surface:** Attribute Details popup (read-only view modal)
**Nav area:** Maintenance / Modules (admin, entity form page)
**Status:** READY_FOR_FRONTEND

---

## 1. Surface Inventory

| Surface | File | Nav area |
|---------|------|----------|
| View-attribute modal shell (ERB partial) | `app/views/admin/maintenance/entities/_attribute_view_modal.html.erb` | Maintenance/Modules |
| View-attribute body (JS template) | `app/javascript/controllers/entity_form/template_builder.js` → `buildAttributeViewHtml` + `buildConfigViewHtml` | Maintenance/Modules |

No new routes, no new controllers. The existing Stimulus wiring (`entity-form#viewAttribute`, `entity-form#closeViewModal`, targets `viewModal`, `viewModalContent`) is untouched.

---

## 2. Layout Spec

### 2a. Modal Shell (`_attribute_view_modal.html.erb`)

Changes from current:
- Widen from `max-w-xl` to `max-w-2xl` to give the 2-column definition grid breathing room.
- Add an icon chip in the header (eye icon on `bg-accent-subtle` background) matching the pattern in `versions_modal_component.html.erb`.
- Add a subtitle line beneath the title showing the attribute's `name` value (populated by JS after content is injected — keep it simple: the `section-header` text stays "Attribute Details"; a subtext `<p>` is filled by JS alongside `viewModalContent`).
- Keep `viewModal`, `viewModalContent`, and `closeViewModal` data attributes exactly as-is.

**Shell structure (annotated ERB pseudocode — do not generate code, only show class targets):**

```
div[data-entity-form-target="viewModal"]  hidden fixed inset-0 z-50 overflow-y-auto
  div.fixed.inset-0.bg-text-primary/60.transition-opacity  (backdrop, closeViewModal on click)
  div.flex.min-h-full.items-center.justify-center.p-4
    div.relative.bg-surface.rounded-xl.shadow-xl.w-full.max-w-2xl   ← CHANGE: max-w-xl → max-w-2xl, rounded-lg → rounded-xl

      ── HEADER ──
      div.px-6.py-4.border-b.border-border-subtle
        div.flex.items-center.justify-between.gap-4
          div.flex.items-center.gap-3                          ← NEW: icon + text stack
            span.h-9.w-9.shrink-0.flex.items-center.justify-center.rounded-lg.bg-accent-subtle.text-accent
              svg(eye icon, h-5 w-5)
            div
              h3.section-header#view-modal-title  "Attribute Details"
              p[data-entity-form-target="viewModalSubtitle"].text-caption.text-text-muted  (filled by JS)
          button[closeViewModal].icon-button.shrink-0
            svg(×, h-4 w-4)

      ── BODY ──
      div.px-6.py-5
        div[data-entity-form-target="viewModalContent"].space-y-5
        (populated by buildAttributeViewHtml)

      ── FOOTER ──
      div.px-6.py-4.bg-canvas-elevated.rounded-b-xl.border-t.border-border-subtle.flex.justify-end
        button[closeViewModal].btn.btn-secondary  "Close"
```

**New target:** `viewModalSubtitle` — a `<p>` the JS populates with the `name` value after the attribute is loaded, giving instant context before scrolling. Add `data-entity-form-target="viewModalSubtitle"` to that paragraph element in the ERB.

In `modal_manager.js#viewAttribute`, after setting `viewModalContentTarget.innerHTML`, add:
```js
if (this.c.hasViewModalSubtitleTarget) {
  this.c.viewModalSubtitleTarget.textContent = attribute.name || ""
}
```
And in `closeViewModal`, clear it:
```js
if (this.c.hasViewModalSubtitleTarget) this.c.viewModalSubtitleTarget.textContent = ""
```

---

### 2b. Body Content (`buildAttributeViewHtml` output)

#### Field order (complete, always shown)

1. Name
2. Display Label
3. Name Slug
4. HTML Type
5. Group
6. Visibility
7. Validators
8. Configuration
9. Description

#### Layout structure

Two layout zones inside a `<dl class="space-y-0">` wrapper:

**Zone A — Identity grid (2-column on sm+, 1-column on mobile):**
Fields 1–6 in a `grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4` definition grid, each field as a `<div>` block with `<dt>` label + `<dd>` value.

**Zone B — Detail sections (full-width, stacked):**
Fields 7–9 each as a borderless section with a `<p class="text-label text-text-muted uppercase tracking-wider mb-2">` heading and the content beneath. A thin `<hr class="border-border-subtle">` divides Zone A from Zone B.

#### Per-field rendering spec

| # | Field | `<dt>` label text | `<dd>` value rendering | Empty placeholder |
|---|-------|-------------------|------------------------|-------------------|
| 1 | Name | "Name" | `<span class="text-body-sm font-semibold text-text-primary">` | — (always present) |
| 2 | Display Label | "Display Label" | `<span class="text-body-sm text-text-primary">` | `<span class="text-body-sm text-text-muted">—</span>` |
| 3 | Name Slug | "Name Slug" | `<code class="font-mono text-xs text-accent bg-accent-subtle px-1.5 py-0.5 rounded">` | `<span class="text-caption text-text-muted">—</span>` |
| 4 | HTML Type | "HTML Type" | `<span class="badge badge-success px-2 py-0.5 text-xs">` (uses `formatHtmlTypeName`) | `<span class="badge badge-default px-2 py-0.5 text-xs">Unknown</span>` |
| 5 | Group | "Group" | group chip (see below) | `<span class="text-body-sm text-text-muted">Ungrouped</span>` |
| 6 | Visibility | "Visibility" | inline badge row (see below) | — (always rendered; all three shown) |
| 7 | Validators | "Validators" | badge list (see below) | `<span class="text-body-sm text-text-muted">None</span>` |
| 8 | Configuration | "Configuration" | table or text (see below) | `<span class="text-body-sm text-text-muted">None</span>` |
| 9 | Description | "Description" | `<p class="text-body-sm text-text-primary whitespace-pre-wrap">` | `<span class="text-body-sm text-text-muted italic">No description provided.</span>` |

**`<dt>` shared class:** `text-label text-text-muted uppercase tracking-wider mb-1`
(maps to the app's `text-label` typography token, which the codebase uses for small uppercase labels)

---

#### Group chip (field 5)

Resolve via `this.c.schemaManager.readAttributeGroups()`. Find `group_id` in the array; if found, render:

```html
<span class="inline-flex items-center gap-1.5">
  <span class="inline-block w-2 h-2 rounded-full ${BAR_CLASS}"></span>
  <span class="text-body-sm text-text-primary font-medium">${groupName}</span>
</span>
```

If not found / `group_id` is null/empty, render:
```html
<span class="text-body-sm text-text-muted">Ungrouped</span>
```

`BAR_CLASS` comes from the same JS color map already used in `buildAttributeGroupHeaderHtml`:

```js
const GROUP_COLOR_BAR = {
  slate: "bg-slate-500", indigo: "bg-indigo-500", sky: "bg-sky-500",
  teal: "bg-teal-500", emerald: "bg-emerald-500", amber: "bg-amber-500",
  rose: "bg-rose-500", violet: "bg-violet-500"
}
```
These raw palette classes are acceptable here because they are already in the build graph (used by `buildAttributeGroupHeaderHtml`) and the group color system has no semantic-token equivalent.

---

#### Visibility badges (field 6)

Replace the current raw-palette `indigo/gray` classes with tokens:

- **Enabled audience:** `badge badge-accent px-1.5 py-0.5 text-xs`
- **Disabled audience:** `badge badge-default px-1.5 py-0.5 text-xs line-through opacity-50`

Rendered as three badges in a `<div class="flex flex-wrap gap-1.5">`:
```html
<span class="badge badge-accent px-1.5 py-0.5 text-xs">Admin</span>
<span class="badge badge-default px-1.5 py-0.5 text-xs line-through opacity-50">Member</span>
<span class="badge badge-default px-1.5 py-0.5 text-xs line-through opacity-50">Public</span>
```
(example: admin enabled, member/public disabled)

---

#### Validator badges (field 7, Zone B)

When validators exist, render each in a `<div class="flex flex-wrap gap-1.5">`:
```html
<span class="badge badge-default border border-border-subtle px-2 py-0.5 text-xs">
  ${escapeHtml(displayLabel)}
</span>
```
Replace the current raw `blue-50/blue-700/blue-200` palette with `badge badge-default border border-border-subtle`. This conveys "neutral info" rather than the current blue which implies an actionable add-badge; in the view modal these are read-only.

When empty:
```html
<span class="text-body-sm text-text-muted">None</span>
```

---

#### Configuration display (field 8, Zone B)

**Selection options** (html_type is select/radio/checkbox):

Render as a compact table with token-based classes:

```html
<div class="overflow-hidden rounded-lg border border-border-subtle">
  <table class="w-full text-xs">
    <thead>
      <tr class="bg-canvas-elevated border-b border-border-subtle">
        <th class="px-3 py-2 text-left text-label text-text-muted uppercase tracking-wider">Label</th>
        <th class="px-3 py-2 text-left text-label text-text-muted uppercase tracking-wider">Value</th>
        <th class="px-3 py-2 text-left text-label text-text-muted uppercase tracking-wider">Default</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-border-subtle">
      <tr class="bg-surface">
        <td class="px-3 py-2 text-body-sm text-text-primary">${label}</td>
        <td class="px-3 py-2"><code class="font-mono text-xs text-accent bg-accent-subtle px-1.5 py-0.5 rounded">${value}</code></td>
        <td class="px-3 py-2">${opt.default ? '<span class="badge badge-accent px-1.5 py-0.5 text-xs">Default</span>' : ""}</td>
      </tr>
    </tbody>
  </table>
</div>
```

**File config** (html_type is file/image):

```html
<div class="flex flex-wrap gap-3">
  <div class="text-body-sm text-text-primary">
    <span class="text-text-muted">Accept: </span>${escapeHtml(config.accept)}
  </div>
  <div class="text-body-sm text-text-primary">
    <span class="text-text-muted">Multiple: </span>${config.multiple ? "Yes" : "No"}
  </div>
</div>
```

**No config** (all other types, or config is null):
```html
<span class="text-body-sm text-text-muted">None</span>
```

Note: `buildConfigViewHtml` currently returns `null` when there is no applicable config. Change the return to return the "None" placeholder string instead of `null`, so `buildAttributeViewHtml` never needs to conditionally hide the section.

---

## 3. Full HTML Structure Emitted by `buildAttributeViewHtml`

The complete template string the JS function should produce:

```html
<dl>
  <!-- Zone A: 2-col identity grid -->
  <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4">

    <!-- 1. Name -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-1">Name</dt>
      <dd><span class="text-body-sm font-semibold text-text-primary">${name}</span></dd>
    </div>

    <!-- 2. Display Label -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-1">Display Label</dt>
      <dd><span class="text-body-sm text-text-primary">${displayLabel}</span></dd>
    </div>

    <!-- 3. Name Slug -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-1">Name Slug</dt>
      <dd><code class="font-mono text-xs text-accent bg-accent-subtle px-1.5 py-0.5 rounded">${name_slug}</code></dd>
    </div>

    <!-- 4. HTML Type -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-1">HTML Type</dt>
      <dd><span class="badge badge-success px-2 py-0.5 text-xs">${displayHtmlType}</span></dd>
    </div>

    <!-- 5. Group (col-span-1 on both breakpoints) -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-1">Group</dt>
      <dd>${groupChipHtml}</dd>
    </div>

    <!-- 6. Visibility (col-span-2 on sm to use full width) -->
    <div class="sm:col-span-2">
      <dt class="text-label text-text-muted uppercase tracking-wider mb-1">Visibility</dt>
      <dd><div class="flex flex-wrap gap-1.5">${visibilityBadges}</div></dd>
    </div>

  </div>

  <!-- Divider -->
  <hr class="my-5 border-border-subtle">

  <!-- Zone B: Detail sections -->
  <div class="space-y-5">

    <!-- 7. Validators -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-2">Validators</dt>
      <dd>${validatorsHtml}</dd>
    </div>

    <!-- 8. Configuration -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-2">Configuration</dt>
      <dd>${configHtml}</dd>
    </div>

    <!-- 9. Description -->
    <div>
      <dt class="text-label text-text-muted uppercase tracking-wider mb-1">Description</dt>
      <dd>${descriptionHtml}</dd>
    </div>

  </div>
</dl>
```

---

## 4. ASCII Mockup

```
┌──────────────────────────────────────────────────────────────────┐
│  [👁 icon]  Attribute Details                          [×]        │
│             first_name                                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  NAME                        DISPLAY LABEL                        │
│  first_name                  First Name                           │
│                                                                   │
│  NAME SLUG                   HTML TYPE                            │
│  `first_name`                [Text  ✓]                            │
│                                                                   │
│  GROUP                       (col-span-2)                         │
│  ● Personal Info             VISIBILITY                           │
│                              [Admin] [Member] [~~Public~~]   │
│                                                                   │
│ ─────────────────────────────────────────────────────────────── │
│                                                                   │
│  VALIDATORS                                                       │
│  [Required]  [Max Length: 100]                                    │
│                                                                   │
│  CONFIGURATION                                                    │
│  None                                                             │
│                                                                   │
│  DESCRIPTION                                                      │
│  The member's legal first name as it appears on their ID.   │
│                                                                   │
├──────────────────────────────────────────────────────────────────┤
│  (footer: bg-canvas-elevated)                    [ Close ]        │
└──────────────────────────────────────────────────────────────────┘

Mobile (1-column):
┌──────────────────────────┐
│  [👁]  Attribute Details [×]│
│        first_name         │
├──────────────────────────┤
│  NAME                    │
│  first_name              │
│  DISPLAY LABEL           │
│  First Name              │
│  NAME SLUG               │
│  `first_name`            │
│  HTML TYPE               │
│  [Text ✓]               │
│  GROUP                   │
│  ● Personal Info         │
│  VISIBILITY              │
│  [Admin][Member]    │
│  [~~Public~~]            │
│ ───────────────────────  │
│  VALIDATORS              │
│  [Required][Max Len:100] │
│  CONFIGURATION           │
│  None                    │
│  DESCRIPTION             │
│  The member's...    │
├──────────────────────────┤
│              [ Close ]   │
└──────────────────────────┘
```

---

## 5. Interaction Flow

**Happy path (view attribute):**
1. User is on entity edit/new page (`/:cid/admin/maintenance/entities/:id/edit`)
2. User clicks the eye icon button on any attribute row → `entity-form#viewAttribute`
3. JS calls `extractAttributeFromRow(row)` → gets `{name, name_slug, display_label, html_type, description, validators, visibility, group_id, config}`
4. JS resolves group: calls `this.c.schemaManager.readAttributeGroups()`, finds group matching `group_id`
5. JS builds `buildAttributeViewHtml(attribute, group)` and sets `viewModalContentTarget.innerHTML`
6. JS sets `viewModalSubtitleTarget.textContent = attribute.name`
7. Modal becomes visible (`viewModalTarget.classList.remove('hidden')`)
8. User reads the full attribute details
9. User clicks Close button or backdrop → `entity-form#closeViewModal` → modal hidden, content cleared, subtitle cleared

**Failure / edge states (all handled in JS):**
- `group_id` present but group not found in `readAttributeGroups()` (e.g., group was deleted): show "Ungrouped" chip
- `validators` is empty array: show "None" placeholder — no conditional hiding
- `config` is null or no config for type: show "None" placeholder — `buildConfigViewHtml` must return the placeholder string, not `null`
- `description` is empty/null: show "No description provided." in italic
- `display_label` same as name: show it anyway (no deduplication)

---

## 6. Component Reuse Map

| UI element | Reused component / class pattern | Notes |
|------------|----------------------------------|-------|
| Modal shell | Inline ERB partial (existing `_attribute_view_modal.html.erb`) | No ViewComponent wrapper needed |
| Header icon chip | Pattern from `versions_modal_component.html.erb` line 13–16 | Inline in the ERB partial |
| Close button | `icon-button` class (existing pattern) | Swap `p-1.5 text-text-muted ...` for `icon-button` |
| Section header typography | `section-header` class (existing) | Used on the modal `<h3>` |
| Field label typography | `text-label` class | Used on every `<dt>` |
| Body text | `text-body-sm` class | Used on `<dd>` values |
| Caption text | `text-caption` class | Used on subtitle `<p>` |
| Name slug inline code | `font-mono text-xs text-accent bg-accent-subtle` | No new component |
| HTML type badge | `badge badge-success` | Matches `_attributes_table.html.erb` line 125 |
| Visibility enabled badge | `badge badge-accent` | Existing `BadgeComponent` variant |
| Visibility disabled badge | `badge badge-default line-through opacity-50` | Existing variant + Tailwind modifiers |
| Validator badges | `badge badge-default border border-border-subtle` | Neutral read-only styling |
| Config default badge | `badge badge-accent` | Existing variant |
| Config options table | Inline HTML in JS template | No component |
| Footer | `bg-canvas-elevated border-t border-border-subtle` + `btn btn-secondary` | Existing pattern |

**No new ViewComponent is required.** The content is entirely JS-rendered (template string in `buildAttributeViewHtml`). The shell ERB partial is lightly edited.

---

## 7. Tailwind & Stimulus Notes

### Tailwind utilities

**Modal shell changes:**
- `max-w-xl` → `max-w-2xl`
- `rounded-lg` → `rounded-xl` (header div and panel div; matches versions modal)
- Header: add `gap-4` to the flex row; add icon chip div

**Body grid:**
- `grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4` for Zone A
- `sm:col-span-2` on the Visibility field wrapper
- `space-y-5` for Zone B sections
- `my-5` on the `<hr>` divider

**Typography tokens used (do not use raw Tailwind equivalents):**
- `text-label` — field label `<dt>` elements (renders as ~10-11px semibold uppercase)
- `text-body-sm` — field value `<dd>` elements
- `text-caption` — modal subtitle line
- `section-header` — modal `<h3>` title
- `font-mono text-xs` — slug `<code>` element

**Color tokens used:**
- `text-text-primary`, `text-text-muted` — text hierarchy
- `text-accent`, `bg-accent-subtle` — slug code chip, group chip color dot background
- `bg-surface` — modal panel background
- `bg-canvas-elevated` — footer + config table header background
- `border-border-subtle` — all dividers and table borders
- `badge badge-success` — HTML type badge
- `badge badge-accent` — enabled visibility + default option
- `badge badge-default` — disabled visibility + validators + ungrouped indicators

**Raw palette classes permitted (already in build graph):**
- `bg-{color}-500` — group color dot in the group chip (same colors as `buildAttributeGroupHeaderHtml`; no semantic token alternative exists)

### Stimulus controller

No new Stimulus controller is needed. All logic lives in existing handlers:
- `entity-form#viewAttribute` (in `modal_manager.js`) — extended to populate subtitle target
- `entity-form#closeViewModal` — extended to clear subtitle target
- `buildAttributeViewHtml` in `template_builder.js` — updated signature accepts `(attribute, group)` where `group` is resolved internally from `this.c.schemaManager.readAttributeGroups()`

**`buildAttributeViewHtml` signature change:**

```js
// Current:
buildAttributeViewHtml({ name, name_slug, display_label, html_type, description, validators, visibility, config })

// New (group resolved internally, no signature change to callers):
buildAttributeViewHtml({ name, name_slug, display_label, html_type, description, validators, visibility, group_id, config })
```

Group resolution inside the method:
```js
const groups = this.c.schemaManager.readAttributeGroups()
const group = groups.find(g => g.id === group_id) || null
const groupChipHtml = group
  ? `<span class="inline-flex items-center gap-1.5">
       <span class="inline-block w-2 h-2 rounded-full ${GROUP_COLOR_BAR[group.color] || 'bg-slate-500'}"></span>
       <span class="text-body-sm text-text-primary font-medium">${escapeHtml(group.name)}</span>
     </span>`
  : `<span class="text-body-sm text-text-muted">Ungrouped</span>`
```

**`buildConfigViewHtml` return-value change:**

Currently returns `null` when no config; change to return the empty-state HTML so the caller never conditionally hides the Configuration section:
```js
// At all return null sites:
return `<span class="text-body-sm text-text-muted">None</span>`
```

**`buildVisibilityBadgesHtml` — used from view modal only (not from the row builder):**

The existing method is shared with the table row. To avoid breaking the row builder, add a `forViewModal = false` parameter, and when `true`, use the token classes instead of the raw palette classes. Alternatively, create a separate private method `buildVisibilityBadgesForViewHtml` used only inside `buildAttributeViewHtml`.

---

## 8. escapeHtml Requirement

All interpolated user-provided values (`name`, `name_slug`, `display_label`, `description`, group name, validator labels, option labels/values, config.accept) must continue to go through `escapeHtml()`. The spec does not relax this requirement anywhere.

---

## 9. `modal_manager.js#viewAttribute` — minimal diff summary

```
1. Extract attribute from row (existing)
2. Resolve group internally in buildAttributeViewHtml (NEW — no caller change)
3. Set viewModalContentTarget.innerHTML = this.c.templateBuilder.buildAttributeViewHtml(attribute)  (existing)
4. Set viewModalSubtitleTarget.textContent = attribute.name  (NEW)
5. Show modal (existing)
```

In `closeViewModal`:
```
3a. Clear viewModalSubtitleTarget.textContent = ""  (NEW, after existing innerHTML clear)
```

---

## 10. Entity form controller target registration

Add `viewModalSubtitle` to the Stimulus controller's `static targets` array so `hasViewModalSubtitleTarget` / `viewModalSubtitleTarget` resolve correctly. The existing `viewModal` and `viewModalContent` targets remain.

```js
// In entity_form_controller.js static targets array, add:
"viewModalSubtitle"
```
