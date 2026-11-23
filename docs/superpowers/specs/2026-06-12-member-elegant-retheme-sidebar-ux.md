# Member Portal — Elegant Re-theme + Sidebar Shell (UX / Implementation Spec)

**Date:** 2026-06-12
**Status:** Ready for frontend
**Upstream design:** `docs/superpowers/specs/2026-06-12-member-elegant-retheme-sidebar-design.md`
**Implements for:** anysys-frontend-developer

Scope: member **chrome** only (shell, sidebar, headers, shared member component classes).
The inner page-builder render (`member/pages/show` `@content`) is untouched. No routes,
controllers, models, or auth changes. Tailwind only, Stimulus only, ViewComponent purity.

---

## 1. Surface inventory

| Surface | Nav area | What changes |
|---|---|---|
| Member shell (every `/:cid/member/*` page) | member | Top-nav shell → left-sidebar shell (desktop rail + mobile drawer) |
| Member design tokens (`application.css`) | member (shared) | Cyan → violet/warm "elegant" re-tune; serif display headings; soft buttons; radius/shadow softening |
| Member page/section/hero headers | member | Serif violet-ink display treatment |
| Auth surfaces (`layouts/auth`, auth shell) | public | Inherit re-tuned tokens automatically — no template change required (one optional heading class, §6) |

All changes are presentation-only and stay inside the existing member URL category.

---

## 2. Deliverable 1 — Token re-tuning map

All edits in `app/assets/tailwind/application.css`.

### 2.1 `@theme` token table (current → NEW)

| Token | Current (cyan) | NEW (elegant violet/warm) | Note |
|---|---|---|---|
| `--color-member-accent` | `#0891b2` | `#7c3aed` | violet-600. White-on-accent = 4.8:1 → AA pass (avatar, logo glyph, focus ring) |
| `--color-member-accent-hover` | `#0e7490` | `#6d28d9` | violet-700 |
| `--color-member-accent-active` | `#155e75` | `#5b21b6` | violet-800 |
| `--color-member-accent-subtle` | `#ecfeff` | `#f5f3ff` | violet-50 — idle-hover wash, flash bg |
| `--color-member-accent-muted` | `#a5f3fc` | `#ddd6fe` | violet-200 — rings, soft-button hover |
| `--color-member-accent-text` | `#0e7490` | `#6d28d9` | violet-700. On `#fbf8f2` paper = 6.5:1 → AA pass for links/labels |
| `--color-member-accent-soft` | `#cffafe` | `#ede9fe` | violet-100 — active nav bg, soft-button bg |
| `--color-member-accent-ink` | `#083344` | `#4c1d95` | violet-900. On violet-100 = 9.3:1, on paper = 11+:1 → AA/AAA |
| `--color-member-paper` | `#fbfaf6` | `#fbf8f2` | warm cream canvas |
| `--color-member-paper-elevated` | `#ffffff` | `#fffdf9` | warm white (sidebar, cards via `--color-surface` stay pure white — see 2.4) |
| `--color-member-border-warm` | `#ece8df` | `#e9e3d6` | warm subtle border |

Also rewrite the prose comment block above these tokens (currently "slate-cyan (cyan-700
base) — civic / professional") to describe the new language: *"violet (violet-600 base) +
warm cream paper — elegant, matches the page-builder 'elegant' preset (page 43). Rest-state
base is violet-600 so white-on-bg passes WCAG AA 4.5:1; ladder steps to violet-700/800 on
hover/active."*

`--gradient-member-hero` references `--color-member-accent*` via `color-mix` — it re-themes
to a violet radial automatically. **No change.**

### 2.2 New token — serif display stack

`--font-family-serif` does **not** exist yet. Add it to `@theme` directly under
`--font-family-mono`:

```css
--font-family-serif: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, Cambria, "Times New Roman", ui-serif, serif;
```

System-only stack (no webfont request). Body text stays `--font-family-sans` (Inter) —
serif is for display headings only.

### 2.3 Radius + shadow re-tune

| What | Current | NEW | Rationale |
|---|---|---|---|
| `.card-member-elevated` `border-radius` | `var(--radius-2xl)` (1rem) | `var(--radius-lg)` (0.625rem) | Visual parity with page 43's `rounded-md` content cards, slightly softened |
| `.hero-member` `border-radius` | `var(--radius-2xl)` | `var(--radius-xl)` (0.75rem) | Radius scales with surface size; one step above cards |
| Controls (`.btn-member`, `.input-member`, `.input-otp`, nav items) | `var(--radius-md)` | unchanged (`--radius-md`, 0.5rem) | Already at page-43 parity |
| `--shadow-member-card` | inset highlight + `0 8px 24px -8px` lift | see below | Soften to a `shadow-sm`-class elevation |

New shadow token value:

```css
--shadow-member-card:
  inset 0 1px 0 rgb(255 255 255 / 0.7),
  0 1px 2px rgb(76 29 149 / 0.04),
  0 1px 3px rgb(15 23 42 / 0.05);
```

(Keeps the warm inset highlight; drops the 24px ambient lift; faint violet tint in the
contact shadow.) `.card-member-elevated:hover` keeps `box-shadow: var(--shadow-md)` —
hover lift is still gentle.

### 2.4 Surface color for cards

`.card-member-elevated` currently uses `background: var(--color-surface)` (pure white).
Change it to `background: var(--color-member-paper-elevated)` so cards sit on the warm
ramp. `.input-member` / `.input-otp` keep `var(--color-surface)` (pure-white wells read as
interactive).

### 2.5 `.btn-member` → soft button (page 43's `button_style: soft`)

Replace the solid treatment. Keep display/gap/padding/font/radius/cursor/whitespace lines
exactly as-is; change only color/border/shadow declarations:

```css
.btn-member {
  background: var(--color-member-accent-soft);          /* was: var(--color-member-accent) */
  color: var(--color-member-accent-ink);                /* was: white */
  border: 1px solid color-mix(in oklab, var(--color-member-accent-muted) 60%, transparent);
  box-shadow: var(--shadow-xs);                         /* was: var(--shadow-button) */
  /* ...existing display/gap/font/padding/border-radius/transition/cursor/white-space unchanged... */
}

.btn-member:hover:not(:disabled) {
  background: var(--color-member-accent-muted);         /* violet-200 */
  border-color: var(--color-member-accent-muted);
  box-shadow: var(--shadow-sm);
}

.btn-member:active:not(:disabled) {
  background: #c4b5fd;                                  /* violet-300 — pressed; ink on it = 6.0:1 */
  box-shadow: var(--shadow-inset);
}
```

`:focus-visible` rule is already token-driven (`0 0 0 2px var(--color-member-paper),
0 0 0 4px var(--color-member-accent)`) — keep verbatim; it re-themes to violet.
Ink-on-soft contrast: 9.3:1 (AA/AAA). Disabled state unchanged (opacity 0.5 inherited
pattern — N/A here; `.btn-member` has no explicit disabled rule and needs none).

### 2.6 `.nav-item-member` → vertical rail item

The top nav is being deleted (§4); the sidebar becomes the only consumer, so repurpose the
class in place rather than adding a variant:

```css
.nav-item-member {
  display: flex;                /* was inline-flex */
  width: 100%;
  align-items: center;
  gap: 0.625rem;
  padding: 0.5625rem 0.75rem;   /* was 0.5rem 0.875rem */
  font-size: var(--text-sm);
  font-weight: var(--font-normal);   /* idle is normal weight; active gets medium */
  color: var(--color-text-secondary);
  border-radius: var(--radius-md);
  transition: background var(--duration-fast) var(--ease-member),
              color var(--duration-fast) var(--ease-member);
}

.nav-item-member:hover {
  color: var(--color-member-accent-ink);
  background: var(--color-member-accent-subtle);   /* violet-50 — lighter than active */
}

.nav-item-member:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px var(--color-member-paper-elevated), 0 0 0 4px var(--color-member-accent);
}

.nav-item-member-active {
  color: var(--color-member-accent-ink);
  background: var(--color-member-accent-soft);     /* violet-100 */
  font-weight: var(--font-medium);
}

.nav-item-member-active:hover {
  color: var(--color-member-accent-ink);
  background: var(--color-member-accent-soft);
}
```

State ladder: idle (transparent / text-secondary) → hover (violet-50 / ink) → active
(violet-100 / ink / medium). Active is always visually stronger than hover.

### 2.7 New component class — serif display heading

Add at the END of the member block in `@layer components` (must come after `.text-heading`
etc. so its declarations win on shared properties):

```css
/* Serif display treatment for member chrome headings — page 43's
   `text-violet-900 font-serif`. Size/leading come from the co-applied
   text-* utility or explicit size classes; this sets family/weight/
   tracking/color only. Override color with text-white on gradient heroes. */
.heading-member-display {
  font-family: var(--font-family-serif);
  font-weight: var(--font-semibold);
  letter-spacing: -0.01em;   /* serif needs less negative tracking than Inter */
  color: var(--color-member-accent-ink);
}
```

Where it is applied (template edits, §4.6):
- `Member::PageHeaderComponent` `<h1>` (page titles)
- `Member::PageSectionComponent` `<h2>` (section/card titles, alongside `text-heading`)
- `Member::HeroCardComponent` `<h1>` (with `text-white` override — white-on-violet gradient stays)
- Sidebar wordmark (§3)
- Mobile top bar wordmark (§3)

`text-member-accent-ink`, `bg-member-paper-elevated`, etc. are auto-generated utilities
from the `@theme` tokens (Tailwind v4) — already in use, nothing to wire.

### 2.8 Cyan literals + reduced motion

- No cyan literal classes exist in member components/views (verified by grep; the only
  `cyan` hits are the flowchart editor palette, out of scope). The only fixes are the
  stale **comment block** (§2.1) and the token values themselves.
- Extend the existing `@media (prefers-reduced-motion: reduce)` block in the member
  section to also cover the drawer: add `#member-sidebar` alongside
  `.card-member-elevated, .btn-member, .nav-item-member` (transition: none).

---

## 3. Deliverable 2 — Left-sidebar shell

### 3.1 ASCII mockups

**Desktop (≥ lg):**

```
┌──────────────────────┬──────────────────────────────────────────────────────┐
│ [✓] Customer Name    │                                                      │  sidebar: w-64,
│  (serif, violet-900) │   ← Back to forms        (eyebrow, violet-700)       │  bg-member-paper-elevated,
├──────────────────────┤   Page Title              [badge]  [soft btn]        │  border-r warm
│  ▢ Home              │   (serif, violet-900)                                │
│  ▣ Forms      ◄active│   subtitle (sans, text-secondary)                    │  content column:
│  ▢ Payments          │                                                      │  bg-member-paper,
│                      │   ┌────────────────────────────────────────────┐    │  max-w-6xl centered
│   (nav: flex-1,      │   │ Section title (serif, violet-900)          │    │
│    overflow-y-auto)  │   │ ────────────────────────────────────────── │    │  cards: warm white,
│                      │   │ body content (sans)                        │    │  rounded-lg,
│                      │   │                                            │    │  soft shadow-sm,
│                      │   └────────────────────────────────────────────┘    │  warm border
├──────────────────────┤                                                      │
│ (JD) Jane Doe     ▴  │                 warm cream background                │  footer: user menu,
│  └ menu opens UP     │                                                      │  opens upward
└──────────────────────┴──────────────────────────────────────────────────────┘
```

**Mobile (< lg), drawer closed:**

```
┌────────────────────────────┐
│ ☰  [✓] Customer Name       │  ← slim top bar, h-14, sticky, warm white, blur
├────────────────────────────┤
│  Page Title (serif violet) │
│  ┌──────────────────────┐  │
│  │ content card         │  │
│  └──────────────────────┘  │
│        warm cream bg       │
└────────────────────────────┘
```

**Mobile, drawer open:**

```
┌──────────────────────┬─────┐
│ [✓] Customer Name    │▒▒▒▒▒│  ← drawer slides in from left (w-64, full height)
│──────────────────────│▒▒▒▒▒│
│  ▢ Home              │▒▒▒▒▒│  ▒ = scrim (violet-ink/30 + slight blur);
│  ▣ Forms             │▒▒▒▒▒│      click closes; Esc closes
│  ▢ Payments          │▒▒▒▒▒│
│                      │▒▒▒▒▒│  body scroll locked while open
│──────────────────────│▒▒▒▒▒│
│ (JD) Jane Doe     ▴  │▒▒▒▒▒│  ← same footer user menu as desktop
└──────────────────────┴─────┘
```

The drawer is the **same `<aside>` element** as the desktop rail — off-canvas
(`-translate-x-full fixed`) below `lg`, static sticky rail at `lg+`. One markup tree, no
duplicated nav.

### 3.2 DOM structure + exact classes — `Member::ShellComponent` template

Full replacement of `app/components/member/shell_component.html.erb`:

```erb
<div data-shell="member"
     class="min-h-screen bg-member-paper lg:flex"
     data-controller="member-sidebar"
     data-action="keydown.esc@window->member-sidebar#close turbo:before-cache@window->member-sidebar#close">

  <%# scrim — mobile drawer backdrop %>
  <div class="fixed inset-0 z-30 hidden bg-member-accent-ink/30 supports-[backdrop-filter]:backdrop-blur-[2px] lg:hidden"
       data-member-sidebar-target="scrim"
       data-action="click->member-sidebar#close"
       aria-hidden="true"></div>

  <%# sidebar — off-canvas drawer below lg, sticky rail at lg+ %>
  <%= render Member::SidebarComponent.new(
        customer: customer,
        user: user,
        items: nav_items,
        current_nav: current_nav
      ) %>

  <%# content column %>
  <div class="flex min-h-screen w-full min-w-0 flex-1 flex-col">

    <%# mobile top bar %>
    <header class="sticky top-0 z-20 flex h-14 shrink-0 items-center gap-2 border-b border-member-border-warm bg-member-paper-elevated/90 px-4 supports-[backdrop-filter]:backdrop-blur-sm lg:hidden">
      <button type="button"
              class="inline-flex h-10 w-10 items-center justify-center rounded-lg text-text-secondary hover:bg-member-accent-subtle motion-safe:transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-member-accent"
              aria-label="Open navigation"
              aria-expanded="false"
              aria-controls="member-sidebar"
              data-member-sidebar-target="trigger"
              data-action="click->member-sidebar#toggle">
        <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16"/>
        </svg>
      </button>

      <%= link_to home_path, class: "inline-flex min-w-0 items-center gap-2 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-member-accent focus-visible:ring-offset-2" do %>
        <span class="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-member-accent text-white ring-1 ring-member-accent-muted/60 shadow-sm">
          <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 12l2-2 4 4 8-8 4 4"/>
          </svg>
        </span>
        <span class="heading-member-display truncate text-base leading-tight"><%= customer.name %></span>
      <% end %>
    </header>

    <%# flash %>
    <% if helpers.flash.any? %>
      <div class="<%= container_classes %> pt-4 lg:pt-6">
        <% helpers.flash.each do |type, message| %>
          <div class="rounded-lg px-4 py-3 mb-3 text-sm ring-1 <%= type.to_s == 'alert' ? 'bg-danger-subtle text-danger ring-danger/20' : 'bg-member-accent-subtle text-member-accent-text ring-member-accent-muted/60' %>"
               role="alert" data-controller="flash" data-flash-auto-dismiss-value="true">
            <%= message %>
          </div>
        <% end %>
      </div>
    <% end %>

    <main class="flex-1 <%= container_classes %> py-8 lg:py-12">
      <%= content %>
    </main>
  </div>
</div>
```

### 3.3 `Member::ShellComponent` class changes (`shell_component.rb`)

- Keep `initialize(customer:, user:, current_nav:, container_width: :default)` and the
  `ArgumentError` guard — **the layout contract is unchanged** (`content_for :member_nav`
  / `:member_container_width` keep working; `app/views/layouts/member.html.erb` needs **no
  edit**).
- Re-tune `CONTAINER_CLASSES` (content now lives beside a 16rem rail; add `w-full` so
  `mx-auto` centers inside the flex column):

```ruby
CONTAINER_CLASSES = {
  default: "w-full max-w-6xl mx-auto px-4 sm:px-6 lg:px-10",
  narrow:  "w-full max-w-3xl mx-auto px-4 sm:px-6 lg:px-10",
  edge:    "w-full"
}.freeze
```

- Add `def home_path = "/#{customer.id}/member"` (used by the mobile top bar; mirrors the
  method being deleted with TopNavComponent).
- Update the class comment: shell is now "sidebar rail (lg+) / off-canvas drawer (< lg) +
  content column".

### 3.4 NEW — `Member::SidebarComponent`

**`app/components/member/sidebar_component.rb`**

```ruby
# frozen_string_literal: true

module Member
  # Left navigation rail for the member shell. Off-canvas drawer below lg
  # (slid in/out by the member-sidebar Stimulus controller on the shell),
  # sticky rail at lg+. Stateless — items come from Member::Navigation via
  # the shell.
  class SidebarComponent < ApplicationComponent
    def initialize(customer:, user:, items:, current_nav:)
      @customer    = customer
      @user        = user
      @items       = items
      @current_nav = current_nav
    end

    attr_reader :customer, :user, :items, :current_nav

    def nav_link_class(item)
      base = "nav-item-member"
      base += " nav-item-member-active" if item.key == current_nav
      base
    end

    def home_path
      "/#{customer.id}/member"
    end

    # Heroicons-outline path data keyed by Member::Navigation::Item#icon.
    # Fallback: plain circle.
    ICON_PATHS = {
      home:          "M3 10.5L12 3l9 7.5M5 9.5V21h5v-6h4v6h5V9.5",
      document_text: "M9 12h6m-6 4h6M7 3h7l5 5v13a1 1 0 01-1 1H7a1 1 0 01-1-1V4a1 1 0 011-1z",
      credit_card:   "M2 8h20M2 12h20M5 6h14a3 3 0 013 3v6a3 3 0 01-3 3H5a3 3 0 01-3-3V9a3 3 0 013-3z",
      user:          "M16 14a4 4 0 10-8 0M12 11a3 3 0 100-6 3 3 0 000 6zM4 21a8 8 0 0116 0",
      shield_check:  "M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3zM9 12l2 2 4-4"
    }.freeze

    def icon_path(item)
      ICON_PATHS[item.icon&.to_sym]
    end
  end
end
```

**`app/components/member/sidebar_component.html.erb`**

```erb
<aside id="member-sidebar"
       data-component="member-sidebar"
       class="fixed inset-y-0 left-0 z-40 flex h-dvh w-64 -translate-x-full flex-col border-r border-member-border-warm bg-member-paper-elevated motion-safe:transition-transform motion-safe:duration-[var(--duration-base)] motion-safe:ease-[var(--ease-member)] lg:sticky lg:top-0 lg:z-auto lg:translate-x-0"
       data-member-sidebar-target="drawer"
       aria-label="Member navigation">

  <%# wordmark %>
  <div class="flex h-16 shrink-0 items-center border-b border-member-border-warm px-4">
    <%= link_to home_path, class: "inline-flex min-w-0 items-center gap-2.5 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-member-accent focus-visible:ring-offset-2 focus-visible:ring-offset-member-paper-elevated" do %>
      <span data-logo="member"
            class="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-member-accent text-white ring-1 ring-member-accent-muted/60 shadow-sm">
        <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M3 12l2-2 4 4 8-8 4 4"/>
        </svg>
      </span>
      <span class="heading-member-display truncate text-lg leading-tight"><%= customer.name %></span>
    <% end %>
  </div>

  <%# nav %>
  <nav class="flex-1 overflow-y-auto px-3 py-4" aria-label="Primary">
    <ul class="space-y-1">
      <% items.each do |item| %>
        <li>
          <%= link_to item.path_for(customer),
                      class: nav_link_class(item),
                      "aria-current": (item.key == current_nav ? "page" : nil),
                      data: { action: "click->member-sidebar#close" } do %>
            <svg class="h-5 w-5 shrink-0 opacity-75" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
              <% if icon_path(item) %>
                <path stroke-linecap="round" stroke-linejoin="round" d="<%= icon_path(item) %>"/>
              <% else %>
                <circle cx="12" cy="12" r="8"/>
              <% end %>
            </svg>
            <span class="truncate"><%= item.label %></span>
          <% end %>
        </li>
      <% end %>
    </ul>
  </nav>

  <%# footer — user menu, opens upward %>
  <div class="shrink-0 border-t border-member-border-warm p-3">
    <%= render Member::UserMenuComponent.new(customer: customer, user: user) %>
  </div>
</aside>
```

Notes:
- `lg:sticky lg:top-0` overrides `fixed` at lg; `lg:translate-x-0` overrides the
  off-canvas transform; `h-dvh` gives full-height at every breakpoint. The rail is
  `shrink-0` by virtue of `w-64` + sticky inside `lg:flex` (no flex-shrink issue because
  the content column has `min-w-0 flex-1`).
- `data-action="click->member-sidebar#close"` on each nav link closes the drawer before
  Turbo navigates (no-op at lg+ where the scrim/transform classes are inert).
- `aria-current="page"` on the active item is the accessibility complement of
  `nav-item-member-active`.

### 3.5 `Member::UserMenuComponent` rework (sidebar footer, opens up)

The sidebar is now its only consumer — rework in place, no variant param.

**`user_menu_component.rb`:** unchanged API (`customer:`, `user:`; `initials`,
`profile_path`, `security_path`, `sign_out_path` all stay).

**`user_menu_component.html.erb`:** replace the trigger + panel classes:

- Trigger (`<button>` — full-width footer row, was a pill):

```
flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm font-medium text-text-primary hover:bg-member-accent-subtle motion-safe:transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-member-accent focus-visible:ring-offset-2 focus-visible:ring-offset-member-paper-elevated
```

  Inside: keep the avatar span exactly as today
  (`inline-flex h-7 w-7 items-center justify-center rounded-full bg-member-accent text-white text-xs font-semibold tracking-wide ring-1 ring-member-accent-muted/60`),
  then `<span class="min-w-0 flex-1 truncate text-left"><%= user.display_name %></span>`
  (drop `hidden sm:inline` — the name is always visible in the footer), then the chevron
  svg rotated to point up: same path, add class `rotate-180` →
  `class="h-4 w-4 shrink-0 rotate-180 text-text-tertiary"`.

- Panel (`role="menu"` div — opens upward, radius softened):

```
absolute bottom-full left-0 mb-2 w-56 min-w-[14rem] origin-bottom-left rounded-lg bg-member-paper-elevated py-1 shadow-[var(--shadow-member-card)] ring-1 ring-member-border-warm divide-y divide-member-border-warm hidden motion-safe:animate-fade-in
```

  (Was `right-0 mt-3 ... origin-top-right rounded-2xl`.) Parent `div.relative` and all
  menu-item links/rows stay byte-identical. `user_menu_controller.js` is reused unchanged
  (toggle/outside-click/Escape already work).

### 3.6 Heading template edits (serif violet-ink)

| File | Edit |
|---|---|
| `app/components/member/page_header_component.html.erb` | `<h1>` class → `heading-member-display text-[1.875rem] sm:text-[2.125rem] leading-tight` (drop `font-semibold tracking-[-0.025em] text-text-primary` — supplied by the component class) |
| `app/components/member/page_section_component.html.erb` | `<h2 class="text-heading">` → `<h2 class="text-heading heading-member-display">` (size/leading from `text-heading`; family/weight/tracking/color from `heading-member-display`, which is defined later in the stylesheet and therefore wins) |
| `app/components/member/hero_card_component.html.erb` | `<h1>` class → `heading-member-display text-white mb-2 text-[2.25rem] sm:text-[2.625rem] leading-[1.05]` (utility `text-white` outranks the component-layer ink color — white-on-gradient is preserved) |

Everything else (status cards, tables, empty states, pagination, detail grids, auth views)
consumes the shared tokens/classes and re-themes automatically — verified: every member
surface file references `member-accent*` / `member-paper*` / `btn-member` /
`card-member-elevated` tokens, no hard-coded cyan anywhere.

### 3.7 Stimulus — NEW `member_sidebar_controller.js`

`app/javascript/controllers/member_sidebar_controller.js` (eager-loaded automatically by
`eagerLoadControllersFrom`, no registration step):

- **Identifier:** `member-sidebar` (controller lives on the shell root div).
- **Targets:** `drawer` (the `<aside>`), `scrim`, `trigger` (hamburger).
- **Actions (declared in markup, no manual listeners):**
  - `click->member-sidebar#toggle` on the hamburger
  - `click->member-sidebar#close` on the scrim and on each nav link
  - `keydown.esc@window->member-sidebar#close` and
    `turbo:before-cache@window->member-sidebar#close` on the root element (the
    before-cache hook prevents Turbo from caching an open drawer)
- **Behavior:**
  - `open()`: `drawerTarget.classList.remove("-translate-x-full")`;
    `scrimTarget.classList.remove("hidden")`;
    `triggerTarget.setAttribute("aria-expanded", "true")` (guard `hasTriggerTarget`);
    `document.body.classList.add("overflow-hidden")` (scroll lock).
  - `close()`: exact inverse; early-return if already closed
    (`drawerTarget.classList.contains("-translate-x-full")`). Must also run the body
    scroll-lock removal in `disconnect()` so a Turbo visit never strands a locked body.
  - `toggle()`: dispatch to open/close based on the `-translate-x-full` presence.
- All visual state is class-toggling only (`-translate-x-full`, `hidden`) — the slide
  animation comes from the Tailwind `motion-safe:transition-transform` classes already on
  the drawer; reduced-motion users get an instant swap (§2.8).
- At `lg+` the toggled classes are inert (`lg:translate-x-0` / `lg:hidden` on the scrim),
  so a resize mid-open cannot wedge the layout.

**DELETE** `app/javascript/controllers/mobile_nav_controller.js` — its only consumer is
the top nav being removed (verified by grep). `user_menu_controller.js` and
`flash_controller.js` are reused unchanged.

### 3.8 Files changed — complete list

| File | Action |
|---|---|
| `app/assets/tailwind/application.css` | Edit — §2 token re-tune, serif token, soft `.btn-member`, rail `.nav-item-member`, card radius/shadow/bg, `.heading-member-display`, comment rewrite, reduced-motion addition |
| `app/components/member/shell_component.html.erb` | Rewrite — §3.2 |
| `app/components/member/shell_component.rb` | Edit — §3.3 (container classes, `home_path`, comment) |
| `app/components/member/sidebar_component.rb` | **New** — §3.4 |
| `app/components/member/sidebar_component.html.erb` | **New** — §3.4 |
| `app/components/member/top_nav_component.rb` | **Delete** (folded into shell mobile bar + sidebar) |
| `app/components/member/top_nav_component.html.erb` | **Delete** |
| `app/components/member/user_menu_component.html.erb` | Edit — §3.5 (trigger row, upward panel) |
| `app/components/member/page_header_component.html.erb` | Edit — §3.6 |
| `app/components/member/page_section_component.html.erb` | Edit — §3.6 |
| `app/components/member/hero_card_component.html.erb` | Edit — §3.6 |
| `app/javascript/controllers/member_sidebar_controller.js` | **New** — §3.7 |
| `app/javascript/controllers/mobile_nav_controller.js` | **Delete** |
| `app/views/layouts/member.html.erb` | **No change** (shell API preserved) |

Spec impact (for QA): `spec/components/member/top_nav_component_spec.rb` (if present) →
replaced by `sidebar_component_spec.rb` (renders items, active state via
`nav-item-member-active` + `aria-current`, wordmark, footer user menu); shell spec updated
for the new structure (drawer targets, mobile top bar, scrim); any spec asserting cyan hex
values or `rounded-2xl` member chrome re-asserts the violet/warm/rounded-lg values
(stale-test policy: rewrite).

---

## 4. Interaction flows

**Desktop navigation:** any `/:cid/member/*` page → click a rail item → Turbo visit →
shell re-renders with the new `current_nav`; active item shows violet-100 bg + violet-900
ink + medium weight + `aria-current="page"`. No drawer/JS involvement at `lg+`.

**Mobile open/close:** `/:cid/member` on a phone → tap hamburger → drawer slides in
(220ms, `--ease-member`), scrim fades in, `aria-expanded="true"`, body scroll locked →
either (a) tap a nav item → drawer closes → Turbo navigates; (b) tap scrim → closes;
(c) press Esc → closes; (d) resize to ≥ lg while open → rail renders normally (toggled
classes inert), body scroll-lock cleared on next close/disconnect.

**User menu (sidebar footer):** click the footer row → panel opens **upward**
(`bottom-full mb-2`) with Profile / Security / Sign out → outside click or Esc closes
(existing `user-menu` controller). Sign out keeps `data: { turbo_method: :delete }`.

**Flash / error:** after a redirect with flash, the notice renders at the top of the
content column inside `container_classes` — violet-50 pill for notices, danger-subtle for
alerts; auto-dismiss via the existing `flash` controller. Validation errors render inside
the page's own forms (unchanged).

**Empty nav edge case:** if `Member::Navigation.items_for(user)` returns `[]` (all
surfaces disabled), the rail still renders wordmark + footer; the `<ul>` is empty — no
special empty-state needed (home is always reachable via the wordmark).

**Admin member-preview (GET-only):** admins opening a member page via
`allow_admin_member_preview!` get the same chrome — no UX difference; no role-specific
chrome is introduced.

---

## 5. Component reuse map

| Layout piece | Component | Status |
|---|---|---|
| Shell (rail + drawer + content column) | `Member::ShellComponent` | reworked |
| Sidebar rail/drawer | `Member::SidebarComponent` (props: `customer:`, `user:`, `items:`, `current_nav:`) | **new** |
| Sidebar footer account menu | `Member::UserMenuComponent` | reworked (upward panel) |
| Mobile top bar | inline in shell template (too small to extract) | new markup |
| Page titles | `Member::PageHeaderComponent` | class-only edit |
| Section cards | `Member::PageSectionComponent` / `.card-member-elevated` | class-only edit |
| Dashboard hero | `Member::HeroCardComponent` | class-only edit |
| Stat cards, tables, pagination, empty states, detail grids, auth shell | existing `Member::*` components | untouched — inherit tokens |
| Top navigation | `Member::TopNavComponent` | **deleted** |

---

## 6. Optional follow-through (nice-to-have, not blocking)

- `app/components/member/auth_shell_component.html.erb` line 30 `<h1>` may adopt
  `heading-member-display text-white ...` for serif parity on the auth gradient panel.
  Token re-tune alone already moves auth surfaces to violet/warm.

---

## 7. Design Decisions Table (authoritative)

| Decision | Value |
|---|---|
| Radius — cards | `--radius-lg` (0.625rem) on `.card-member-elevated`; page-43 `rounded-md` parity, slightly softened |
| Radius — hero | `--radius-xl` (0.75rem) — scales with surface size |
| Radius — controls/menus/flash | `--radius-md` (0.5rem) buttons/inputs/nav items; `rounded-lg` user-menu panel + flash + logo glyph |
| Shadow — cards | `--shadow-member-card` = warm inset highlight + `0 1px 2px` + `0 1px 3px` (shadow-sm class); hover `--shadow-md` |
| Card style | `bg-member-paper-elevated` (#fffdf9) + `border-member-border-warm` (#e9e3d6) + soft shadow |
| Accent ramp | violet-600 `#7c3aed` base; hover 700 `#6d28d9`; active 800 `#5b21b6`; subtle 50 `#f5f3ff`; soft 100 `#ede9fe`; muted 200 `#ddd6fe`; text 700; ink 900 `#4c1d95` |
| Heading font | `--font-family-serif` = Iowan Old Style → Palatino → Georgia → Cambria stack, semibold, `-0.01em` tracking, via `.heading-member-display` |
| Heading color | `--color-member-accent-ink` (violet-900); `text-white` override on gradient heroes |
| Body font | Inter (`--font-family-sans`) — unchanged; serif is display-only |
| Primary button | **Soft**: violet-100 bg / violet-900 ink / violet-200 hover / violet-300 pressed (`#c4b5fd`), `shadow-xs` |
| Nav item states | idle: transparent + text-secondary + normal weight → hover: violet-50 + ink → active: violet-100 + ink + medium + `aria-current="page"` |
| Focus ring | `0 0 0 2px <paper>` + `0 0 0 4px var(--color-member-accent)` (component classes); `ring-2 ring-member-accent` (utility surfaces) |
| Sidebar width | `w-64` (16rem), `bg-member-paper-elevated`, `border-r border-member-border-warm`, sticky `top-0 h-dvh` |
| Drawer breakpoint | `< lg` off-canvas drawer; `≥ lg` static rail (`lg:` prefix is the single switch) |
| Drawer mechanics | translate-x + scrim (`bg-member-accent-ink/30` + 2px blur), Esc/scrim/nav-click close, body scroll lock, `aria-expanded`/`aria-controls`, Turbo before-cache close — `member-sidebar` Stimulus controller |
| Motion | 220ms `--ease-member` drawer slide; 150ms color transitions; all behind `motion-safe:` / reduced-motion block |
| Spacing rhythm | content `py-8 lg:py-12`, gutters `px-4 sm:px-6 lg:px-10`, default column `max-w-6xl`, narrow `max-w-3xl`; rail padding `px-3 py-4`, item gap `space-y-1` |
| Contrast checks | white on violet-600 4.8:1 · violet-700 on cream 6.5:1 · ink on violet-100 9.3:1 · ink on violet-300 6.0:1 — all ≥ AA |
