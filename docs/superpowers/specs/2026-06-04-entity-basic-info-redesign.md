# Entity Basic Information Card — Redesign Spec
**Date:** 2026-06-04
**Surface:** `app/views/admin/maintenance/entities/show.html.erb` — lines 62-120 (the first `.card` block)
**Nav area:** Maintenance / Modules (entity detail page under `/:customer_id/maintenance/entities/:id`)
**Audience:** admin, owner
**Status:** implementation-ready

---

## 1. Surface Inventory

| Surface | Location | Change |
|---|---|---|
| Basic Information card | `show.html.erb` lines 62-120 | Full redesign of the `.card` block |

Nothing else on the page changes. The Bridge Entity alert, Entity Attributes card, Associations card, and code cards below it are untouched.

---

## 2. ASCII Mockup

### Desktop (≥ md breakpoint, two-column grid)

```
┌─────────────────────────────────────────────────────────────────────┐
│  CARD HEADER (px-6 py-4, border-b border-border-subtle)             │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  [COLOR CHIP]  Entity Name                  [Kind badge]     │   │
│  │  [ICON inside]  (text-heading text-text-primary)             │   │
│  └──────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────┤
│  DEFINITION GRID (p-6, dl, grid grid-cols-1 md:grid-cols-2 gap-6)  │
│                                                                      │
│  ┌────────────────────────────┬────────────────────────────────┐    │
│  │  Name Slug                 │  Type                          │    │
│  │  [text-code chip]          │  [badge-default chip]          │    │
│  ├────────────────────────────┼────────────────────────────────┤    │
│  │  Description               │  Referenced Template           │    │
│  │  Free text or em-dash      │  [pill link] or "None"         │    │
│  │                            │  [caption below pill]          │    │
│  └────────────────────────────┴────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────────┤
│  TIMESTAMP FOOTER (px-6 py-3 bg-canvas-elevated rounded-b-xl)       │
│  Created: 2026-01-15 10:30:00          Updated: 2026-06-03 14:22:05 │
└─────────────────────────────────────────────────────────────────────┘
```

### Mobile (< md, single column)

```
┌───────────────────────────────────────┐
│  [COLOR CHIP + ICON]  Entity Name     │
│                       [Kind badge]    │
├───────────────────────────────────────┤
│  Name Slug                            │
│  [text-code chip]                     │
│                                       │
│  Type                                 │
│  [badge-default chip]                 │
│                                       │
│  Description                          │
│  Free text                            │
│                                       │
│  Referenced Template                  │
│  [pill link] + caption                │
├───────────────────────────────────────┤
│  Created    Updated                   │
└───────────────────────────────────────┘
```

---

## 3. Layout Spec — Region by Region

### 3a. Card Header

**Container:** `px-6 py-4 border-b border-border-subtle`

Two sub-regions arranged `flex items-center justify-between gap-4 flex-wrap`:

**Left — Identity block** (`flex items-center gap-3`):

1. **Color + Icon chip**
   - A square `w-9 h-9 rounded-lg flex-shrink-0 flex items-center justify-center` whose background color is driven by `attribute_group_color_classes(@entity.color, variant: :bar)`.
   - Inside: `attribute_group_icon(@entity.icon, css_class: "w-5 h-5 text-white")`.
   - When `@entity.color` or `@entity.icon` is nil/blank, fall back to `bg-surface-active` background and `text-text-muted` icon color (same guard the helper already applies via `DEFAULT_COLOR` / `DEFAULT_ICON`).

2. **Entity name** — `<h3 class="section-header">@entity.name</h3>` (replaces the old `<h3 class="section-header">Basic Information</h3>`)

**Right — Kind badge** (`flex-shrink-0`):

- If `@entity.bridge_entity?` → `<span class="badge badge-accent">Bridge</span>`
- Else → `<span class="badge badge-default">Standard</span>`

The section header text "Basic Information" is removed; the entity name takes that role. The card header label is no longer needed because the breadcrumb already establishes context.

### 3b. Definition Grid (body)

**Container:** `p-6`

Use a `<dl>` with class `grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-5`.

Each field is a `<div>` containing:
- `<dt class="form-label">LABEL</dt>`
- `<dd class="mt-1">VALUE</dd>`

Field order and rendering rules follow below.

---

#### Field 1 — Name Slug (top-left on desktop)

```
<dt class="form-label">Name Slug</dt>
<dd class="mt-1">
  <span class="text-code"><%= @entity.name_slug %></span>
</dd>
```

No change to the chip rendering itself (`text-code` is the correct token). The label changes from the old `<p class="form-label">` to `<dt>` for semantic correctness.

---

#### Field 2 — Type (top-right on desktop)

```
<dt class="form-label">Type</dt>
<dd class="mt-1">
  <span class="badge badge-default"><%= @entity.element_type %></span>
</dd>
```

Previously plain text; now rendered as a `badge badge-default` pill for visual distinction from prose values.

---

#### Field 3 — Description (bottom-left on desktop)

```
<dt class="form-label">Description</dt>
<dd class="mt-1 text-body text-text-primary"><%= @entity.description.presence || "—" %></dd>
```

Empty state: em-dash (`—`) inline, no separate element needed. The old `"-"` becomes a typographically correct `"—"`.

When description is long (> ~200 chars) it naturally wraps within its grid cell.

---

#### Field 4 — Referenced Template (bottom-right on desktop)

This field retains its full existing logic, only the wrapper changes from `<div>` + `<p>` to `<div>` (dd cell).

**When template is present AND parsed successfully (`ref_data && ref_data[:name]`):**

```
<dt class="form-label">Referenced Template</dt>
<dd class="mt-1">
  <%= link_to admin_maintenance_entity_template_preview_path(current_customer_id, @entity),
      target: "_blank",
      class: "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium
              bg-accent-subtle text-accent-text rounded-lg ring-1 ring-inset
              ring-accent-muted hover:bg-accent-muted transition-base" do %>
    <svg class="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24"
         stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round"
            d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0
               01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1
               1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1
               1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
    </svg>
    <%= ref_data[:name] %>
    <svg class="w-3.5 h-3.5 flex-shrink-0 text-accent" fill="none"
         viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round"
            d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14
               4h6m0 0v6m0-6L10 14" />
    </svg>
  <% end %>
  <% if ref_data[:description].present? %>
    <p class="mt-1.5 text-caption"><%= ref_data[:description] %></p>
  <% end %>
</dd>
```

Design changes from old markup:
- `rounded-full` → `rounded-lg` (consistent with card's `radius-xl` family; pills are for tags, chips are for interactive links)
- `px-3 py-1` → `px-3 py-1.5` (slightly taller hit target)
- `gap-1.5` replaces `mr-1.5` / `ml-1.5` — cleaner flex gap approach
- Everything else (href, `target="_blank"`, icons, caption class) is preserved exactly

**When template present but JSON parse fails (raw string fallback):**

```
<dd class="mt-1 text-body-sm text-text-secondary"><%= @entity.referenced_template.truncate(80) %></dd>
```

Unchanged from current behavior.

**When no template (`@entity.referenced_template` blank):**

```
<dd class="mt-1">
  <span class="text-caption italic">None</span>
</dd>
```

Old markup used `<p class="mt-1 text-body-sm">None</p>`. New version uses `text-caption italic` to visually de-emphasize the empty state (consistent with the dashed-border empty states used elsewhere on the page: `text-caption italic`).

---

### 3c. Timestamp Footer

**Container:** `px-6 py-3 bg-canvas-elevated border-t border-border-subtle rounded-b-xl`

```
<div class="grid grid-cols-2 gap-4">
  <div>
    <dt class="stat-label">Created</dt>
    <dd class="mt-0.5 text-body-sm text-text-secondary">
      <%= @entity.created_at.strftime("%Y-%m-%d %H:%M:%S") %>
    </dd>
  </div>
  <div>
    <dt class="stat-label">Last Updated</dt>
    <dd class="mt-0.5 text-body-sm text-text-secondary">
      <%= @entity.updated_at.strftime("%Y-%m-%d %H:%M:%S") %>
    </dd>
  </div>
</div>
```

This matches exactly the timestamp footer pattern used in `FlowchartInfoCardComponent` (`stat-label` + `text-sm text-text-secondary`). The `stat-label` token is `text-xs font-semibold uppercase tracking-wide text-text-muted`.

---

## 4. Complete ERB Structure

Replace lines 62-120 of `show.html.erb` with the following block verbatim. The Ruby logic for `ref_data` is preserved inside the block.

```erb
<%# Basic Information Card — redesigned %>
<div class="card">

  <%# Card Header: color chip + name + kind badge %>
  <div class="px-6 py-4 border-b border-border-subtle">
    <div class="flex items-center justify-between gap-4 flex-wrap">

      <%# Left: color/icon chip + entity name %>
      <div class="flex items-center gap-3 min-w-0">
        <div class="w-9 h-9 rounded-lg flex-shrink-0 flex items-center justify-center
                    <%= attribute_group_color_classes(@entity.color.presence || 'slate', variant: :bar) %>">
          <%= attribute_group_icon(
                @entity.icon.presence || 'folder',
                css_class: "w-5 h-5 text-white"
              ) %>
        </div>
        <h3 class="section-header truncate"><%= @entity.name %></h3>
      </div>

      <%# Right: Kind badge %>
      <div class="flex-shrink-0">
        <% if @entity.bridge_entity? %>
          <span class="badge badge-accent">Bridge</span>
        <% else %>
          <span class="badge badge-default">Standard</span>
        <% end %>
      </div>

    </div>
  </div>

  <%# Definition grid: 1-col mobile → 2-col desktop %>
  <div class="p-6">
    <dl class="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-5">

      <%# Name Slug %>
      <div>
        <dt class="form-label">Name Slug</dt>
        <dd class="mt-1">
          <span class="text-code"><%= @entity.name_slug %></span>
        </dd>
      </div>

      <%# Type %>
      <div>
        <dt class="form-label">Type</dt>
        <dd class="mt-1">
          <span class="badge badge-default"><%= @entity.element_type %></span>
        </dd>
      </div>

      <%# Description — spans full width when content is present so prose
          does not compete with the template chip in the adjacent column %>
      <div class="md:col-span-2">
        <dt class="form-label">Description</dt>
        <dd class="mt-1 text-body text-text-primary">
          <%= @entity.description.presence || "—" %>
        </dd>
      </div>

      <%# Referenced Template %>
      <div class="md:col-span-2">
        <dt class="form-label">Referenced Template</dt>
        <% if @entity.referenced_template.present? %>
          <%
            ref_data = begin
              JSON.parse(@entity.referenced_template).with_indifferent_access
            rescue JSON::ParserError
              nil
            end
          %>
          <% if ref_data && ref_data[:name] %>
            <dd class="mt-1">
              <%= link_to admin_maintenance_entity_template_preview_path(current_customer_id, @entity),
                  target: "_blank",
                  class: "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium
                          bg-accent-subtle text-accent-text rounded-lg ring-1 ring-inset
                          ring-accent-muted hover:bg-accent-muted transition-base" do %>
                <svg class="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24"
                     stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round"
                        d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0
                           01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1
                           1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1
                           1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
                </svg>
                <%= ref_data[:name] %>
                <svg class="w-3.5 h-3.5 flex-shrink-0 text-accent" fill="none"
                     viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round"
                        d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14
                           4h6m0 0v6m0-6L10 14" />
                </svg>
              <% end %>
              <% if ref_data[:description].present? %>
                <p class="mt-1.5 text-caption"><%= ref_data[:description] %></p>
              <% end %>
            </dd>
          <% else %>
            <dd class="mt-1 text-body-sm text-text-secondary">
              <%= @entity.referenced_template.truncate(80) %>
            </dd>
          <% end %>
        <% else %>
          <dd class="mt-1">
            <span class="text-caption italic">None</span>
          </dd>
        <% end %>
      </div>

    </dl>
  </div>

  <%# Timestamp footer %>
  <div class="px-6 py-3 bg-canvas-elevated border-t border-border-subtle rounded-b-xl">
    <div class="grid grid-cols-2 gap-4">
      <div>
        <p class="stat-label">Created</p>
        <p class="mt-0.5 text-body-sm text-text-secondary">
          <%= @entity.created_at.strftime("%Y-%m-%d %H:%M:%S") %>
        </p>
      </div>
      <div>
        <p class="stat-label">Last Updated</p>
        <p class="mt-0.5 text-body-sm text-text-secondary">
          <%= @entity.updated_at.strftime("%Y-%m-%d %H:%M:%S") %>
        </p>
      </div>
    </div>
  </div>

</div>
```

---

## 5. Design Decision Notes

### Description field: why full-width (`md:col-span-2`)

Description prose can be multi-sentence. Constraining it to half the grid width causes awkward line-wrapping at ≥ md breakpoints. Full-width avoids that and keeps the grid cleaner. The Name Slug + Type pair in row 1 is short enough to share a row.

### Referenced Template: why full-width

The template pill + caption can be 60-80 chars wide. On a two-column grid at a typical 700px card width, the right-column cell is ~310px — tight for the pill + external-link icon + optional caption below. Full-width gives it breathing room.

### Header name replaces "Basic Information" label

The old header label was redundant: breadcrumbs already say the entity name, and the page `<h1>` above the card also shows the name. The redesign promotes the color/icon identity motif from the attributes-table group headers into the card header itself, giving the card a visual anchor that also doubles as the section title. The "Basic Information" text is removed.

### Kind badge positioning

The badge sits in the card header (top-right), not inside the `<dl>`, because it is identity metadata, not a field value. This matches how `FlowchartInfoCardComponent` puts the Type badge inline with the header region.

### No Stimulus needed

The card is purely read-only. No JavaScript interactions are required. The `data-controller="entity-form"` wrapper that encloses the entire `show.html.erb` page is unaffected.

---

## 6. Component Reuse Map

| Region | Reused component / token | Notes |
|---|---|---|
| Color chip background | `attribute_group_color_classes(color, variant: :bar)` helper | Already in scope via `EntityAttributeGroupingHelper` |
| Icon inside chip | `attribute_group_icon(icon, css_class:)` helper | Same helper |
| Kind badge | `badge badge-accent` / `badge badge-default` tokens | Inline span, no ViewComponent needed for a simple badge |
| `form-label` tokens | `@layer components .form-label` | 13px medium text-secondary |
| `text-code` chip | `@layer components .text-code` | Mono, surface-active background |
| Template preview link | Inline `link_to` — existing logic preserved | No component |
| Timestamp footer pattern | Mirrors `FlowchartInfoCardComponent` footer | `stat-label` + `text-body-sm text-text-secondary` |
| `section-header` | `@layer components .section-header` | 15px semibold |

No new ViewComponent is required. The entire redesign is inline ERB.

---

## 7. Tailwind & Stimulus Notes

**Tailwind tokens used (no raw palette classes):**

| Token class | Role |
|---|---|
| `card` | Outer card shell |
| `border-b border-border-subtle` | Header/body separator |
| `px-6 py-4` | Card header padding |
| `p-6` | Body padding |
| `section-header` | Entity name in header |
| `badge badge-accent` | Bridge kind indicator |
| `badge badge-default` | Standard kind indicator / Type field value |
| `form-label` | `<dt>` labels |
| `text-body text-text-primary` | Description value |
| `text-body-sm text-text-secondary` | Timestamp values, raw template fallback |
| `text-code` | Name Slug chip |
| `text-caption` | Template description caption, "None" empty state |
| `bg-accent-subtle text-accent-text ring-accent-muted hover:bg-accent-muted` | Template preview pill |
| `rounded-lg` | Template pill corners |
| `transition-base` | Template pill hover transition |
| `bg-canvas-elevated` | Timestamp footer background |
| `border-t border-border-subtle` | Footer top separator |
| `rounded-b-xl` | Footer bottom rounding (matches card's border-radius) |
| `stat-label` | Timestamp section labels |
| `grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-5` | Responsive definition grid |
| `md:col-span-2` | Description + Template full-width rows |
| `w-9 h-9 rounded-lg` | Color chip square |
| `w-5 h-5 text-white` | Icon inside color chip |
| `flex items-center gap-3` / `flex items-center justify-between gap-4 flex-wrap` | Layout primitives |

**Stimulus:** None required. The card is read-only static markup.

**Responsive breakpoints:**
- `< md` (< 768px): single-column `dl`, header wraps via `flex-wrap`, chip + name stack to one line naturally.
- `≥ md` (≥ 768px): two-column `dl`; Name Slug top-left, Type top-right; Description and Referenced Template span full width via `md:col-span-2`.

---

## 8. Empty / Loading / Error States

| Field | Empty state | Rendering |
|---|---|---|
| Description | `@entity.description` blank | Em-dash `—` inline (no separate element) |
| Referenced Template | `@entity.referenced_template` blank | `<span class="text-caption italic">None</span>` |
| Referenced Template (parse error) | JSON::ParserError | Truncated raw string, `text-body-sm text-text-secondary` |
| Color chip | `@entity.color` nil | `attribute_group_color_classes` falls back to `DEFAULT_COLOR` ("slate") via existing helper guard |
| Icon chip | `@entity.icon` nil | `attribute_group_icon` falls back to `DEFAULT_ICON` ("folder") via existing helper guard |
| Timestamps | Never nil (DB-managed) | Always rendered |

No loading state — this is a synchronous server-rendered detail view. No error state within the card itself.
