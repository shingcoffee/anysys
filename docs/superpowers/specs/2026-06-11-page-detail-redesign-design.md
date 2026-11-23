# Page Detail View Redesign — Design Spec
**Date:** 2026-06-11
**Surface:** `/:cid/admin/maintenance/pages/:id`
**File:** `app/views/admin/maintenance/pages/show.html.erb`
**Status:** READY_FOR_FRONTEND

---

## 1. Critique + Design Direction

### What is wrong with the current layout

1. **No visual hierarchy.** All four cards (`Publishing`, `Visibility`, `Rendered Views`, `Page Information`) share identical visual weight. The admin cannot identify the page's publication state at a glance — they must read every card header to orient themselves.

2. **100 % width single column is wasteful on desktop.** The page uses `space-y-6` over a full-width column, leaving enormous dead space on both sides at `lg+` breakpoints. The entity detail view (`entities/show.html.erb`) also stacks cards but its cards each have rich table content that justifies full width. The page detail has short-form content that is a natural two-column fit.

3. **Related concerns are scattered.** Publishing status, Visibility toggles, and Rendered View links are three facets of the same question — "who can reach this page, and how?" — but they appear as three separate cards separated by visual weight equals, with no grouping cue.

4. **The `Visibility` form's "Save visibility" button is the highest-affordance primary action on the screen, yet it is buried third.** The publish/unpublish toggle — the true primary lifecycle action — shares equal card prominence with the slug display field.

5. **Repetitive card headers** add noise ("Publishing", "Visibility", "Rendered Views", "Page Information") without communicating the hierarchy of importance.

6. **Metadata is bottom-weighted.** The page name, slug, entity binding, and field count are useful for orientation but appear at the very bottom, below all functional panels.

### Design direction

Adopt a **status-strip + asymmetric two-column grid** pattern:

- A full-width **Status Strip** immediately below the existing breadcrumbs + header row: renders publication state, audience enablement dots, field count, and entity binding in a single horizontal line readable in two seconds. This strip is purely display — no forms, no buttons.
- Below the strip: `lg:grid lg:grid-cols-3 lg:gap-6`
  - **Left / main column (2/3 width):** Lifecycle concerns — Publishing (publish toggle + public URL), then the combined Visibility + Rendered Views panel stitched together so their audiences are visually colocated.
  - **Right / sidebar column (1/3 width):** Page Information (name, slug, entity, fields, description, timestamps). Static metadata reads naturally at narrow width.
- Mobile/tablet: columns collapse to a single stack in the order: Status Strip → Publishing → Visibility + Rendered Views → Page Information.

The two existing component templates (`VisibilityCardComponent`, `AudienceLinksCardComponent`) are redesigned as templates only; their Ruby APIs, `AUDIENCES` constant, `rows` / `enabled?` / `disabled_reason` / `dot_class` / `checked?` methods, and all Stimulus data-* attributes remain completely unchanged.

---

## 2. Layout Structure

### 2a. Full annotated ERB skeleton (show.html.erb content area only)

The breadcrumbs render and the `<div class="flex items-center justify-between mb-6">` header row (with Preview/Edit/Delete) are kept exactly as they are today.

```erb
<%# ─── Status Strip ─────────────────────────────────────────────── %>
<%= render Pages::StatusStripComponent.new(page: @page) %>

<%# ─── Two-column grid ──────────────────────────────────────────── %>
<div class="mt-6 grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">

  <%# ── LEFT / MAIN COLUMN (spans 2 of 3) ─────────────────────── %>
  <div class="lg:col-span-2 space-y-5">

    <%# Publishing card — lifecycle primary action %>
    <div class="card overflow-hidden">
      <%# header: title + publish/unpublish button %>
      <div class="px-6 py-4 border-b border-border-subtle flex items-center justify-between gap-3">
        <div class="flex items-center gap-2.5">
          <h3 class="section-header">Publishing</h3>
          <%# badge: Published (success) | Unpublished (default) %>
        </div>
        <%# publish / unpublish button_to — unchanged endpoints %>
      </div>
      <%# body: public URL row (when published) | unpublished notice (when not) %>
      <div class="px-6 py-5">
        <%# ... identical to today's publishing card body ... %>
      </div>
    </div>

    <%# Unified Distribution card — Visibility + Rendered Views per audience %>
    <%= render Pages::DistributionCardComponent.new(page: @page, customer_id: current_customer_id) %>

  </div><%# end main column %>

  <%# ── RIGHT / SIDEBAR COLUMN (spans 1 of 3) ──────────────────── %>
  <div class="space-y-5">

    <%# Page Information card — metadata at a glance %>
    <div class="card">
      <div class="px-6 py-4 border-b border-border-subtle">
        <h3 class="section-header">Page Information</h3>
      </div>
      <div class="p-6">
        <dl class="space-y-4">
          <%# Name, Slug, Bound Entity, Fields, Description — see §3 %>
        </dl>
      </div>
      <%# Timestamp footer — canvas-elevated strip — see §3 %>
    </div>

  </div><%# end sidebar column %>

</div><%# end grid %>
```

### 2b. ASCII layout — desktop (lg+)

```
┌─ breadcrumbs ────────────────────────────────────────────────────────────┐
│  Maintenance / Pages / Contact Form                                       │
└───────────────────────────────────────────────────────────────────────────┘
┌─ page header row (unchanged) ────────────────────────────────────────────┐
│  h1.text-subtitle  "Contact Form"    [Preview] [Edit] [Delete]           │
└───────────────────────────────────────────────────────────────────────────┘
┌─ STATUS STRIP (full width) ───────────────────────────────────────────────┐
│  ● Published    Admin ● Member ● Public ●    5 fields    Entity: Customer │
└───────────────────────────────────────────────────────────────────────────┘

 ┌── MAIN (2/3) ─────────────────────┐  ┌── SIDEBAR (1/3) ──────────────┐
 │ ┌─ Publishing card ─────────────┐ │  │ ┌─ Page Information card ───┐ │
 │ │ Publishing  [Published]  [Un] │ │  │ │ Name          Contact Form │ │
 │ │─────────────────────────────── │ │  │ │ Slug          contact-form │ │
 │ │ Public URL __________________ │ │  │ │ Bound Entity  [Customer]   │ │
 │ │            [Open ↗]          │ │  │ │ Fields        [5 fields]   │ │
 │ └───────────────────────────────┘ │  │ │ Description   ...          │ │
 │                                   │  │ └─────────────────────────── │ │
 │ ┌─ Distribution card ───────────┐ │  │   created / updated footer   │ │
 │ │ Audience  Visible  Open       │ │  │ └───────────────────────────┘ │
 │ │ ─────────────────────────────  │ │  └───────────────────────────────┘
 │ │ ◉ Admin   [✓]     [Open ↗]   │ │
 │ │ ◉ Member  [✓]     [Open ↗]   │ │
 │ │ ◉ Public  [ ]     Not visible │ │
 │ │─────────────────────────────── │ │
 │ │          [Save visibility]     │ │
 │ └───────────────────────────────┘ │
 └───────────────────────────────────┘
```

### 2c. ASCII layout — mobile (< lg)

```
breadcrumbs
h1 + action buttons (wrap to two rows on xs)
STATUS STRIP (stacked, 2 columns)
Publishing card (full width)
Distribution card (full width)
Page Information card (full width)
```

---

## 3. Per-Section Spec

### 3.1 Status Strip — `Pages::StatusStripComponent`

**Purpose:** Surface the four most important facts in a horizontal pill strip so admins get orientation at a glance without scrolling into any card.

**Tailwind classes:**

```erb
<div class="card px-5 py-3 flex flex-wrap items-center gap-x-6 gap-y-2 mb-0">
  <%# Fact pills, separated by a thin vertical divider %>

  <%# 1. Publication state %>
  <div class="flex items-center gap-2">
    <%# Published state dot %>
    <span class="w-2 h-2 rounded-full flex-shrink-0
                 <%= page.published? ? 'bg-success' : 'bg-text-muted' %>"></span>
    <%# Badge %>
    <%# published: BadgeComponent variant: :success, size: :sm — "Published" %>
    <%# unpublished: BadgeComponent variant: :default, size: :sm — "Unpublished" %>
  </div>

  <span class="hidden sm:block w-px h-4 bg-border-subtle flex-shrink-0"></span>

  <%# 2. Audience dots (admin / member / public) %>
  <div class="flex items-center gap-3">
    <span class="text-caption">Visible to</span>
    <%# For each audience: dot + label %>
    <%# dot enabled:  admin=bg-accent, member=bg-member-accent, public=bg-success %>
    <%# dot disabled: bg-border %>
    <%# label: text-caption + (enabled ? text-text-primary : text-text-muted) %>
    <%# example: %>
    <span class="flex items-center gap-1.5">
      <span class="w-2 h-2 rounded-full bg-accent"></span>
      <span class="text-caption text-text-primary">Admin</span>
    </span>
    <span class="flex items-center gap-1.5">
      <span class="w-2 h-2 rounded-full bg-border"></span>
      <span class="text-caption text-text-muted">Member</span>
    </span>
    <span class="flex items-center gap-1.5">
      <span class="w-2 h-2 rounded-full bg-success"></span>
      <span class="text-caption text-text-primary">Public</span>
    </span>
  </div>

  <span class="hidden sm:block w-px h-4 bg-border-subtle flex-shrink-0"></span>

  <%# 3. Field count %>
  <div class="flex items-center gap-1.5">
    <%# DocumentText icon w-3.5 h-3.5 text-text-muted %>
    <span class="text-caption"><%= page.fields.length %> fields</span>
  </div>

  <span class="hidden sm:block w-px h-4 bg-border-subtle flex-shrink-0"></span>

  <%# 4. Bound entity (or "Standalone") %>
  <div class="flex items-center gap-1.5">
    <%# Cube icon w-3.5 h-3.5 text-text-muted %>
    <% if page.entity %>
      <span class="text-caption">Entity:</span>
      <%# BadgeComponent variant: :primary, size: :sm — entity name %>
    <% else %>
      <span class="text-caption text-text-muted">Standalone page</span>
    <% end %>
  </div>
</div>
```

**Data fields used:**
- `page.published?`
- `page.visible_to?("admin")`, `page.visible_to?("member")`, `page.visible_to?("public")`
- `page.fields.length`
- `page.entity&.name`

**Empty/edge states:**
- Zero fields: shows "0 fields" — no special treatment needed.
- No entity: shows "Standalone page" without entity badge.
- All audiences disabled: all three dots render in `bg-border` (muted grey).

**Component props:**
```ruby
Pages::StatusStripComponent.new(page:)
```

---

### 3.2 Publishing Card (refactored inline in show.html.erb)

This card keeps the same structure as today. The only change is its placement inside the left column and the removal of the full-width constraint. The card content is unchanged word for word.

**Card header classes (unchanged):**
```
px-6 py-4 border-b border-border-subtle flex items-center justify-between gap-3
```

**Title + badge row (unchanged):**
```
flex items-center gap-2.5
  h3.section-header "Publishing"
  BadgeComponent variant: :success/:default size: :sm
```

**Publish/Unpublish button (unchanged):**
- Published → `btn btn-secondary` with Unpublish label
- Unpublished → `btn btn-success` with Publish label
- Both `button_to` endpoints are unchanged.

**Body (unchanged):**
- Published: public URL + "Open" `btn btn-ghost` link
- Unpublished: muted caption text
- Classes: `px-6 py-5`

---

### 3.3 Distribution Card — `Pages::DistributionCardComponent` (NEW)

**Purpose:** Replace the two separate `VisibilityCardComponent` and `AudienceLinksCardComponent` cards with a single unified card that shows per-audience: (a) the visibility toggle and (b) the rendered-view Open link, side by side in the same row. This colocation eliminates the cognitive gap between "is this audience enabled?" and "can I open its view?"

**Ruby API (new component — wraps both existing components' logic):**

```ruby
# app/components/pages/distribution_card_component.rb
module Pages
  class DistributionCardComponent < ViewComponent::Base
    def initialize(page:, customer_id:)
      @page        = page
      @customer_id = customer_id
    end
    # delegates to existing logic — no new methods needed;
    # VisibilityCardComponent::AUDIENCES, checked?, enabled?, disabled_reason,
    # dot_class, and row data are all reproduced inline in the template
    # OR the component can instantiate the two child components and expose
    # their public methods. Either approach is fine; the simpler inline
    # approach is recommended.
    private
    attr_reader :page, :customer_id
  end
end
```

**Template structure:**

```erb
<div class="card overflow-hidden">
  <%# Card header %>
  <div class="px-6 py-4 border-b border-border-subtle flex items-center justify-between gap-3">
    <div>
      <h3 class="section-header">Audience & Distribution</h3>
      <p class="text-body-sm text-text-muted mt-0.5">
        Who can open this page once published, and how to reach each view.
      </p>
    </div>
  </div>

  <%# Audience rows — one per audience %>
  <%= form_with url: admin_maintenance_page_visibility_path(customer_id, page),
                method: :patch,
                class: "divide-y divide-border-subtle" do |f| %>

    <% audiences_with_rows.each do |item| %>
      <%# item = { key:, label:, hint:, dot_class:, checked:, enabled:,
      #            disabled_reason:, open_url: } %>

      <div class="px-6 py-4">
        <%# Three-column layout per row:
            col-1: dot + audience label + hint
            col-2: visibility toggle (checkbox)
            col-3: Open link or disabled reason %>
        <div class="grid grid-cols-1 sm:grid-cols-[1fr_auto_auto] gap-x-6 gap-y-3
                    sm:items-center">

          <%# Col 1: audience identity %>
          <div class="flex items-start gap-3 min-w-0">
            <span class="w-2 h-2 rounded-full flex-shrink-0 mt-1.5
                         <%= item[:dot_class] %>"></span>
            <div class="min-w-0">
              <p class="text-sm font-medium text-text-primary"><%= item[:label] %></p>
              <p class="text-body-sm text-text-muted"><%= item[:hint] %></p>
              <% if item[:key] == "member" %>
                <p class="text-xs text-text-muted mt-1 flex items-center gap-1">
                  <%# InformationCircle icon w-3.5 h-3.5 flex-shrink-0 %>
                  Requires an active member session to open.
                </p>
              <% end %>
            </div>
          </div>

          <%# Col 2: visibility checkbox — exact markup preserved from VisibilityCardComponent %>
          <div class="sm:text-center">
            <label class="flex sm:justify-center items-center gap-2 cursor-pointer">
              <input type="hidden"
                     name="page[visibility][<%= item[:key] %>]"
                     value="0">
              <input type="checkbox"
                     name="page[visibility][<%= item[:key] %>]"
                     value="1"
                     <%= "checked" if item[:checked] %>
                     class="h-4 w-4 rounded border-border text-accent
                            focus:ring-accent shrink-0">
              <span class="form-label mb-0">Visible</span>
            </label>
          </div>

          <%# Col 3: Open link or disabled reason — exact logic from AudienceLinksCardComponent %>
          <div class="flex-shrink-0">
            <% if item[:enabled] %>
              <a href="<%= item[:open_url] %>" target="_blank" rel="noopener noreferrer"
                 class="btn btn-ghost">
                <%# ArrowTopRightOnSquare icon w-4 h-4 mr-1.5 %>
                Open
              </a>
            <% else %>
              <span class="inline-flex items-center gap-1.5 text-sm text-text-muted py-2">
                <%# EyeSlash or XCircle icon — same condition as AudienceLinksCardComponent %>
                <span><%= item[:disabled_reason] %></span>
              </span>
            <% end %>
          </div>

        </div>
      </div>
    <% end %>

    <%# Save visibility button row %>
    <div class="px-6 py-4 bg-canvas-elevated flex justify-end">
      <%= f.submit "Save visibility", class: "btn btn-primary" %>
    </div>

  <% end %>
</div>
```

**`audiences_with_rows` helper method on the component** merges `VisibilityCardComponent::AUDIENCES` with `AudienceLinksCardComponent#rows` data:

```ruby
def audiences_with_rows
  dot_classes = { "admin" => "bg-accent", "member" => "bg-member-accent",
                  "public" => "bg-success" }
  open_urls   = {
    "admin"  => helpers.admin_maintenance_page_render_path(customer_id, page),
    "member" => helpers.member_page_path(customer_id, page),
    "public" => page.public_token ? helpers.public_page_url(customer_id: customer_id, token: page.public_token) : "#"
  }
  hints = {
    "admin"  => "Admins and owners of this customer",
    "member" => "Signed-in members of this customer",
    "public" => "Anyone with the link, including anonymous visitors"
  }

  %w[admin member public].map do |key|
    not_published = !page.published?
    not_visible   = !page.visible_to?(key)
    disabled_reason = if not_published
                        "Not published"
                      elsif not_visible
                        "Not visible to #{key.capitalize}"
                      end
    {
      key:             key,
      label:           key.capitalize,
      hint:            hints[key],
      dot_class:       dot_classes[key],
      checked:         page.visible_to?(key),
      enabled:         page.published? && page.visible_to?(key),
      disabled_reason: disabled_reason,
      open_url:        open_urls[key]
    }
  end
end
```

All URL helpers, the `page.visible_to?` predicate, and the `page.published?` predicate are unchanged. The `form_with` posts to the unchanged `admin_maintenance_page_visibility_path` with the unchanged param shape.

---

### 3.4 Page Information Card (sidebar — refactored inline)

**Purpose:** Metadata at a glance in a narrow right-hand column. Replaces the current bottom-weighted full-width `Page Information` card.

**Layout:** Single vertical `dl` in a `space-y-4` stack (not the current 2-column `sm:grid-cols-2` grid, which is unnecessary at sidebar width).

```erb
<div class="card">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h3 class="section-header">Page Information</h3>
  </div>

  <div class="p-6">
    <dl class="space-y-4">

      <div>
        <dt class="form-label">Name</dt>
        <dd class="mt-1 text-body text-text-primary"><%= @page.name %></dd>
      </div>

      <div>
        <dt class="form-label">Slug</dt>
        <dd class="mt-1">
          <span class="text-code"><%= @page.name_slug %></span>
        </dd>
      </div>

      <div>
        <dt class="form-label">Bound Entity</dt>
        <dd class="mt-1">
          <% if @page.entity %>
            <%= link_to admin_maintenance_entity_path(current_customer_id, @page.entity),
                        class: "inline-flex items-center gap-1" do %>
              <%= render BadgeComponent.new(variant: :primary, size: :sm) do %>
                <%# Cube icon w-3 h-3 mr-1 %>
                <%= @page.entity.name %>
              <% end %>
            <% end %>
          <% else %>
            <span class="text-body-sm text-text-muted">None (Standalone)</span>
          <% end %>
        </dd>
      </div>

      <div>
        <dt class="form-label">Fields</dt>
        <dd class="mt-1">
          <%= render BadgeComponent.new(variant: :info, size: :sm) do %>
            <%= @page.fields.length %> fields
          <% end %>
        </dd>
      </div>

      <% if @page.description.present? %>
        <div>
          <dt class="form-label">Description</dt>
          <dd class="mt-1 text-body-sm text-text-secondary"><%= @page.description %></dd>
        </div>
      <% end %>

    </dl>
  </div>

  <%# Timestamp footer — matches entities/show.html.erb pattern exactly %>
  <div class="px-6 py-3 bg-canvas-elevated border-t border-border-subtle rounded-b-xl">
    <div class="space-y-2">
      <div>
        <p class="stat-label">Created</p>
        <p class="mt-0.5 text-body-sm text-text-secondary">
          <%= @page.created_at.strftime("%Y-%m-%d %H:%M") %>
        </p>
      </div>
      <div>
        <p class="stat-label">Last Updated</p>
        <p class="mt-0.5 text-body-sm text-text-secondary">
          <%= @page.updated_at.strftime("%Y-%m-%d %H:%M") %>
        </p>
      </div>
    </div>
  </div>
</div>
```

Note: `text-code` is used for the slug, matching how `entities/show.html.erb` renders `name_slug`. Timestamps are added (pattern taken from entities detail — the data is available, currently just not displayed on pages).

---

## 4. Component Reuse Map

| Section | Component / element | Action |
|---|---|---|
| Breadcrumbs | `BreadcrumbsComponent` | Unchanged |
| Page header row | Inline ERB in show.html.erb | Unchanged |
| Status Strip | `Pages::StatusStripComponent` | **New** (see §3.1) |
| Publishing card | Inline ERB in show.html.erb | Restructured (moved into grid, content unchanged) |
| Audience & Distribution | `Pages::DistributionCardComponent` | **New** (replaces `VisibilityCardComponent` + `AudienceLinksCardComponent` template-only; Ruby logic migrated/inlined) |
| Page Information card | Inline ERB in show.html.erb | Restructured (moved to sidebar, `dl` layout changed, timestamps added) |
| Badges | `BadgeComponent` | Unchanged API, same call sites |

### Existing components retired from show.html.erb rendering:
- `Pages::VisibilityCardComponent` — its template is superseded by `DistributionCardComponent`. The Ruby class can remain or be deleted; the template is abandoned.
- `Pages::AudienceLinksCardComponent` — same: template abandoned, logic migrated.

If the frontend developer prefers to keep the two Ruby classes and delegate to them internally from `DistributionCardComponent`, that is acceptable. The simplest path is to inline the merged logic directly in `DistributionCardComponent` as specified in §3.3.

---

## 5. New ViewComponents — Specifications

### `Pages::StatusStripComponent`

**File:** `app/components/pages/status_strip_component.rb`

**Props:**
```ruby
def initialize(page:)
  @page = page
end
```

**Template file:** `app/components/pages/status_strip_component.html.erb`

**Renders:** Full-width `.card` strip with `flex flex-wrap items-center gap-x-6 gap-y-2 px-5 py-3`

**Pill structure per fact:** icon (optional) + label text using `.text-caption` or `.text-body-sm`

**Dividers between pills:** `<span class="hidden sm:block w-px h-4 bg-border-subtle flex-shrink-0">` — hidden on xs so pills wrap gracefully.

**Audience dot colors:**
- Admin enabled: `bg-accent`
- Member enabled: `bg-member-accent`
- Public enabled: `bg-success`
- Any disabled: `bg-border`

**No Stimulus controller needed** — purely display.

---

### `Pages::DistributionCardComponent`

**File:** `app/components/pages/distribution_card_component.rb`

**Props:**
```ruby
def initialize(page:, customer_id:)
  @page        = page
  @customer_id = customer_id
end
```

**Template file:** `app/components/pages/distribution_card_component.html.erb`

**No new Stimulus controller needed.** The existing form_with + Turbo submit behaviour covers the visibility save. The Open links are plain `<a target="_blank">` as today.

**Key data helper:** `audiences_with_rows` as specified in §3.3.

---

## 6. Responsive Behavior Notes

| Breakpoint | Layout |
|---|---|
| `xs` (< 640px) | Single column stack. Status strip fact pills wrap to up to 2 per row. Distribution card audience rows stack col-1/col-2/col-3 vertically (grid-cols-1). |
| `sm` (640px–1023px) | Still single column. Status strip dividers visible. Distribution card rows go 3-column (`sm:grid-cols-[1fr_auto_auto]`). Page Information dl is single column. |
| `lg+` (≥ 1024px) | Two-column grid: main (2/3) + sidebar (1/3). Both columns scroll independently (`items-start` on parent grid prevents stretching). |

**Grid utilities on wrapper:**
```
grid grid-cols-1 lg:grid-cols-3 gap-6 items-start mt-6
```

**Main column:**
```
lg:col-span-2 space-y-5
```

**Sidebar column:**
```
(default col-span-1, implicit) space-y-5
```

No `min-height` or fixed heights anywhere — all cards grow with content.

---

## 7. Tailwind & Stimulus Notes

### Tailwind utilities summary

| Purpose | Classes |
|---|---|
| Two-column grid wrapper | `grid grid-cols-1 lg:grid-cols-3 gap-6 items-start mt-6` |
| Main column | `lg:col-span-2 space-y-5` |
| Status strip card | `card px-5 py-3 flex flex-wrap items-center gap-x-6 gap-y-2` |
| Strip fact divider | `hidden sm:block w-px h-4 bg-border-subtle flex-shrink-0` |
| Distribution card audience row | `grid grid-cols-1 sm:grid-cols-[1fr_auto_auto] gap-x-6 gap-y-3 sm:items-center` |
| Distribution card save row | `px-6 py-4 bg-canvas-elevated flex justify-end` |
| Page Info slug | `text-code` (already in design system) |
| Timestamps footer | `px-6 py-3 bg-canvas-elevated border-t border-border-subtle rounded-b-xl` — matches entities detail pattern |
| Audience enabled dot | `w-2 h-2 rounded-full bg-accent` / `bg-member-accent` / `bg-success` |
| Audience disabled dot | `w-2 h-2 rounded-full bg-border` |

### Stimulus controllers

**No new Stimulus controllers are required.** All interactions are:
1. Standard Turbo form submits (visibility save)
2. Standard `button_to` Turbo deletes (publish/unpublish)
3. Plain `<a target="_blank">` links (Open rendered view)

If future work adds auto-save on checkbox change (toggling visibility without a button click), a `visibility-autosave` Stimulus controller would be appropriate — but that is out of scope for this redesign.

---

## 8. What Explicitly Does Not Change

- Breadcrumbs component render and its crumb data.
- The page header row (`flex items-center justify-between mb-6`) with Preview, Edit, Delete actions — classes, icon SVGs, link targets, `button_to` endpoints, `turbo_confirm` data attributes: all unchanged.
- `admin_maintenance_page_publication_path` endpoint (publish POST / unpublish DELETE).
- `admin_maintenance_page_visibility_path` endpoint (PATCH) and the param shape `page[visibility][admin]`, etc.
- `admin_maintenance_page_render_path`, `member_page_path`, `public_page_url` endpoints.
- `BadgeComponent` Ruby class and variant/size API.
- `Pages::VisibilityCardComponent` Ruby class (`AUDIENCES` constant, `checked?`, `visible_to?` delegation).
- `Pages::AudienceLinksCardComponent` Ruby class (`rows`, `enabled?`, `disabled_reason`, `dot_class`, `public_url`).
- Any Stimulus data-* attributes on existing elements.
- Route definitions, controller actions, model methods.

---

## RETURN
```
ux_doc: docs/superpowers/specs/2026-06-11-page-detail-redesign-design.md
surfaces:
  - name: admin/maintenance/pages/:id (show)
    nav_area: Maintenance/Modules
    new_components:
      - Pages::StatusStripComponent
      - Pages::DistributionCardComponent
    reused_components:
      - BreadcrumbsComponent
      - BadgeComponent
      - Pages::VisibilityCardComponent (Ruby class only, template retired)
      - Pages::AudienceLinksCardComponent (Ruby class only, template retired)
overall: READY_FOR_FRONTEND
notes: >
  The redesign introduces a status strip for at-a-glance orientation, moves to
  an asymmetric lg:grid-cols-3 two-column layout (2/3 lifecycle + 1/3 metadata),
  and merges the Visibility and AudienceLinks concerns into a single
  DistributionCardComponent. All existing endpoints, param shapes, Ruby component
  APIs, and Stimulus wiring are preserved exactly. Two new ViewComponents are
  needed (StatusStripComponent and DistributionCardComponent); no new controllers,
  routes, or Stimulus controllers are required.
```
