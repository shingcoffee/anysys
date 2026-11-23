# Plan: Member UI Visual Refactor

**Date:** 2026-05-26
**Brief:** `docs/superpowers/specs/2026-05-26-member-ui-refactor-po-brief.md`
**Design:** `docs/superpowers/specs/2026-05-26-member-ui-refactor-design.md`
**Branch (worktree):** `worktree-refactor-member-layout-styling`

This is a presentation-layer-only refactor. No models, no migrations, no controllers, no routes, no contracts, no activities, no mailers. Touched files live exclusively under:

- `app/assets/tailwind/application.css`
- `app/views/layouts/{auth,member}.html.erb`
- `app/components/member/**`
- `app/views/member/**`
- `app/views/authentication/**`
- `app/javascript/controllers/{mobile_nav,user_menu}_controller.js`
- `spec/components/member/**`

---

## Slice A — Tokens, layouts, Stimulus (parallel-safe)

**Goal:** Make every downstream change paint the right colors/animations on the first build. No view files reference any token that hasn't landed yet.

### A.1 `app/assets/tailwind/application.css` — additive token + utility extensions

In `@theme` block (after the existing member tokens at lines 90–101), append:

```css
--color-member-accent-soft: #ccfbf1;
--color-member-accent-ink:  #042f2e;

--color-member-paper:          #fbfaf6;
--color-member-paper-elevated: #ffffff;
--color-member-border-warm:    #ece8df;

--ease-member: cubic-bezier(0.22, 0.61, 0.36, 1);
--duration-fast:    150ms;
--duration-base:    220ms;
--duration-slow:    320ms;

--shadow-member-card:
  inset 0 1px 0 rgb(255 255 255 / 0.6),
  0 1px 2px rgb(15 23 42 / 0.04),
  0 8px 24px -8px rgb(15 23 42 / 0.08);
```

Replace the existing `--gradient-member-hero` with the refined radial form (see design §2.3).

In `@layer components` (after the existing `.hero-member` block at line 842):

- Refine `.hero-member` to `position: relative; overflow: hidden; padding: 2.25rem 2.5rem 2.5rem;` and add a `::after` pseudo-element with a subtle white→transparent linear overlay (`linear-gradient(180deg, rgb(255 255 255 / 0.04) 0%, rgb(255 255 255 / 0) 60%)`) sized `inset: 0`.
- Refine `.card-member-elevated` to use `border: 1px solid var(--color-member-border-warm); box-shadow: var(--shadow-member-card);` with `transition: transform var(--duration-base) var(--ease-member), box-shadow var(--duration-base) var(--ease-member), border-color var(--duration-base) var(--ease-member);`.
- Refine `.nav-item-member` hover wash to `var(--color-member-accent-soft)` and active state to `background: var(--color-member-accent-subtle); color: var(--color-member-accent-ink); position: relative;` with a 2px-tall accent underline drawn via `::after` for desktop only (visible at `md+` because mobile sheet uses left-strip indication).
- Add `.input-member` (mirrors `.input-field` but focuses with `--color-member-accent` ring instead of admin indigo). Form inputs in member surfaces will use this class going forward.
- Add `.input-otp` — for 6-digit verification codes: `text-align: center; letter-spacing: 0.6em; font-family: var(--font-family-mono); font-size: var(--text-2xl); padding: 0.875rem 1rem;` plus the same focus-ring treatment as `.input-member`.
- Add `@media (prefers-reduced-motion: reduce)` block at end of `@layer components` that sets `transition: none !important; animation: none !important;` on `.card-member-elevated`, `.btn-member`, `.nav-item-member`.

### A.2 `app/views/layouts/member.html.erb`

Change `<body class="bg-canvas antialiased">` → `<body class="bg-member-paper antialiased">`.

(`bg-member-paper` resolves to the new token via Tailwind v4 theme arbitrary-value lookup.)

### A.3 `app/views/layouts/auth.html.erb`

Same body class change.

### A.4 `app/javascript/controllers/mobile_nav_controller.js`

Whatever the current `toggle()` method does, additionally:
- Sync `this.element.querySelector('[data-action="click->mobile-nav#toggle"]')`'s `aria-expanded` to `"true"` / `"false"` based on whether the sheet is hidden.
- Add/remove an `is-open` class on the sheet target so CSS can drive the slide-in.

### A.5 `app/javascript/controllers/user_menu_controller.js`

In `toggle()`, sync the trigger button's `aria-expanded` to match the panel's open state. Same one-line addition.

---

## Slice B — Member ViewComponents (parallel-safe; all live in `app/components/member/`)

**Goal:** Apply design §4 to every component template. Ruby class signatures stay identical except for §B.7 (`EmptyStateComponent` gains optional `cta_label:` / `cta_path:`). Therefore call sites elsewhere don't break.

### B.1 `shell_component.html.erb`

- Increase main padding to `py-10 lg:py-14`.
- Wrap flash banners in `space-y-3` instead of `mb-3` per item.
- Switch flash success banner background to `bg-member-accent-subtle` + `text-member-accent-ink`.

### B.2 `top_nav_component.html.erb`

- Outer nav: `bg-surface/85 backdrop-blur-sm border-b border-member-border-warm sticky top-0 z-30`.
- Logo chip: replace `bg-gradient-to-br from-member-accent to-member-accent-hover` with `bg-member-accent ring-1 ring-member-accent-muted/60`.
- Mobile toggle: add `aria-controls="member-mobile-sheet"`, `aria-expanded="false"`, `data-mobile-nav-target="trigger"`.
- Mobile sheet: add `id="member-mobile-sheet"`, give it the slide-in transition classes per design §3.3, and use `divide-y divide-member-border-warm` between links. Each link has `min-h-[44px] flex items-center px-4 py-3` with active state `border-l-2 border-member-accent pl-[14px]`.

### B.3 `user_menu_component.html.erb`

- Trigger avatar circle: `bg-member-accent ring-1 ring-member-accent-muted/60` (was gradient).
- Trigger button: add `data-user-menu-target="trigger"` (already there) and `aria-expanded="false"`.
- Panel: `mt-3` instead of `mt-2`; add `data-transition-target` markers for `animate-fade-in` (utility already exists in `@layer utilities`).
- Item rows: `divide-y divide-member-border-warm` between sections.

### B.4 `page_header_component.html.erb` + `.rb`

- Title: `<h1 class="text-[1.875rem] sm:text-[2.125rem] font-semibold tracking-[-0.025em] text-text-primary">`.
- Subtitle: `mt-1.5 text-body-sm`.
- Eyebrow: render an inline SVG chevron (16×16, currentColor) before the label inside the link; replace the literal `←` character with the SVG. Update Ruby `eyebrow:` hash usage docs in the class header comment but keep the data shape (`{ label:, path: }`).
- Bottom margin: `mb-10`.

### B.5 `page_section_component.html.erb` + `.rb`

- Header block: `<header class="mb-5 pb-4 border-b border-member-border-warm">` when title present.
- DENSITY_CLASSES: `:compact` → `"p-5"` (was `"p-4"`). `:flush` and `:default` unchanged.

### B.6 `hero_card_component.html.erb`

- Outer: `<section class="hero-member relative overflow-hidden">`.
- Inner wrapper: `<div class="relative flex flex-col sm:flex-row sm:items-start sm:justify-between gap-6">`.
- Title: `<h1 class="text-[2.25rem] sm:text-[2.625rem] font-semibold leading-[1.05] tracking-[-0.025em] text-white">` (drop `text-display`).
- Body: `<p class="mt-2 text-base sm:text-lg text-white/90 max-w-prose">`.
- Status pill: keep current markup but on `<sm` it lays out beneath the heading naturally because of `flex-col`.
- Decorative glyph: render the 24-stroke checkmark inside a `pointer-events-none absolute right-4 top-4 hidden lg:block opacity-15 text-white` container scaled to `h-32 w-32`.

### B.7 `status_card_component.html.erb` + `.rb`

- Card: `card-member-elevated group flex flex-col gap-4 min-h-[180px]`.
- Icon chip: `bg-member-accent-subtle ring-1 ring-member-accent-muted/60 text-member-accent-ink` (40×40, `rounded-xl`).
- Value: `text-[1.625rem] font-semibold tracking-[-0.02em] [font-variant-numeric:tabular-nums]` plus `value_class` (existing tone branch).
- CTA: wrap label and arrow in a `group/cta inline-flex items-center gap-1.5 text-sm font-medium text-member-accent-text mt-auto`. Arrow: `transition-transform duration-[var(--duration-base)] ease-[var(--ease-member)] group-hover/cta:translate-x-0.5`.

### B.8 `detail_grid_component.html.erb`

- `<dt>` class: `text-[11px] uppercase tracking-[0.06em] font-semibold text-text-tertiary`.
- `<dd>` class: `mt-1.5 text-[15px] text-text-primary break-words`.
- When the row's format is `:mono`, `<dd>` becomes `font-mono text-[13px]` (the existing `Member::Formatters.format(..., :mono)` already wraps in a span — no Ruby change needed; the wrapping span carries the mono class).

### B.9 `index_table_component.html.erb` + `.rb`

- `<thead>` class: `bg-member-paper`.
- `<th>` class: `px-5 py-3 text-[11px] uppercase tracking-[0.06em] font-semibold text-text-tertiary` (replaces current `table-header` styling at the row level).
- `<tbody>` class: `divide-y divide-member-border-warm`.
- `<tr>` hover: `hover:bg-member-accent-subtle/40 transition-colors duration-[var(--duration-fast)]`.
- Cell padding stays `px-5 py-3`. Trailing-link cell: `px-5 py-3 text-right`. Link uses `inline-flex items-center gap-1 text-sm font-medium text-member-accent-text hover:underline group/row-link` with arrow that mirrors §B.7.

### B.10 `pagination_component.html.erb`

- Wrap in `mt-6 pt-5 border-t border-member-border-warm flex items-center justify-between text-sm`.
- "Showing" copy: `text-text-tertiary [font-variant-numeric:tabular-nums]`.
- Buttons: use plain markup `inline-flex h-9 px-3 rounded-md text-sm font-medium text-member-accent-text hover:bg-member-accent-soft transition-colors duration-[var(--duration-fast)]` (drop `btn btn-ghost`).

### B.11 `empty_state_component.html.erb` + `.rb`

- Add optional `cta_label:`, `cta_path:` to `initialize` (default `nil`). Render the CTA as `btn-member` only when both are present. **No call sites change**; existing usages keep working.
- Outer card: keep `card-member-elevated text-center py-14 px-6`.
- Halo: outer 64×64 ring `bg-member-accent-soft` with inner 48×48 chip `bg-member-accent-subtle text-member-accent-ink ring-1 ring-member-accent-muted`.
- Body wrapping: `<p class="mt-2 text-body-sm max-w-sm mx-auto">`.

### B.12 `auth_shell_component.html.erb`

- Outer: `<div data-shell="member-auth" class="min-h-screen flex flex-col lg:flex-row bg-member-accent">`. (Outer wrapper carries the accent so the brand pane can bleed.)
- Mobile collapsed strip (`<lg`): `<header class="lg:hidden flex items-center gap-3 px-5 h-12 text-white">` — single flex row of checkmark glyph + customer name.
- Brand pane (`lg+ only via lg:flex hidden lg:flex`): preserves current copy but switches the 3-tile grid to a single `flex divide-x divide-white/15` row of three icon+label items inside `<div class="mt-12 flex divide-x divide-white/15 rounded-xl ring-1 ring-white/15 backdrop-blur-sm bg-white/5">`. Each item: `flex-1 px-4 py-3 text-xs text-white/85 flex flex-col gap-1`.
- Form pane: `flex-1 lg:w-1/2 bg-member-paper-elevated lg:rounded-l-3xl p-6 lg:p-12 lg:shadow-[var(--shadow-member-card)] flex items-center justify-center`. Inner `max-w-md w-full`.
- Flash banners: keep current treatment but use `--color-member-accent-subtle` for notice and `--color-danger-subtle` for alert.

### B.13 `surface_index_component.html.erb` + `surface_detail_component.html.erb`

- No structural change — composition of B.4–B.11. The visual updates flow through automatically.

### B.14 `top_nav_component.rb` / `shell_component.rb`

No Ruby changes. (Class signatures unchanged.)

---

## Slice C — Views (parallel-safe per file)

### C.1 Member views

- `member/dashboards/show.html.erb`: switch the "Recent activity" empty card from raw `card-member-elevated text-center py-10` markup to `Member::EmptyStateComponent` — design alignment, same copy. Update the in-card list rendering to use `divide-y divide-member-border-warm`. Remove the standalone `<h2 class="section-header">` heading; replace with `Member::PageSectionComponent.new(title: "Recent activity")` so the heading is rendered consistently.
- `member/profiles/show.html.erb`: replace the inline avatar gradient with `bg-member-accent ring-1 ring-member-accent-muted/60` (matches updated user-menu/topnav direction).
- `member/profiles/edit.html.erb`: swap `class: "input-field"` → `class: "input-member"` on every form input.
- `member/securities/show.html.erb`:
  - Apply the new "Disable 2FA" treatment (design §4.14): label uses `form-label`; input uses `input-otp`; right-aligned `btn btn-danger`.
  - The MFA status icon chip uses the `bg-success-subtle text-success` / `bg-warning-subtle text-warning` branches but with `ring-1 ring-success/20` / `ring-1 ring-warning/20`.
- `member/mfa/setup.html.erb`:
  - Wrap each section header with a numbered step circle (`<span class="inline-flex h-7 w-7 items-center justify-center rounded-full bg-member-accent-subtle text-member-accent-ink text-sm font-semibold ring-1 ring-member-accent-muted/60">1</span>`) inline next to the section title via `Member::PageSectionComponent`'s title slot. (Title already accepts a string; we'll inline the numbered circle by *passing* the rendered HTML as `title:`. Since Ruby strings render as HTML in ERB without `html_escape`, we adjust the section template to support a `title_html:` arg — see §B.5 above. Simpler alternative: pre-render the QR/setup content with a `<header>` block above the `PageSectionComponent.new` containing the numbered circle. Use the simpler alternative.)
  - QR code wrapper: `bg-white p-6 rounded-2xl ring-1 ring-member-border-warm shadow-[var(--shadow-member-card)]` (design §4.13).
  - Manual secret pill: `inline-flex items-center gap-2 font-mono text-sm tracking-[0.08em] bg-member-paper px-3 py-2 rounded-md ring-1 ring-member-border-warm`.
  - Verification code input: `input-otp` class (replaces the bespoke utility soup).
- `member/surfaces/{index,show}.html.erb`: no edits — they delegate to `SurfaceIndex/DetailComponent` which carry the new design.

### C.2 Auth views

- `authentication/sessions/new.html.erb`: swap `class: "input-field"` → `class: "input-member"`. No structural change.
- `authentication/passwords/new.html.erb`: same input class swap.
- `authentication/passwords/edit.html.erb`: same input class swap.
- `authentication/registrations/new.html.erb`: same input class swap.
- `authentication/sessions/_unconfirmed.html.erb`: no change (already on the new tokens).
- `authentication/passwords/disabled.html.erb` / `registrations/disabled.html.erb`: no change.
- `authentication/registrations/edit.html.erb`: **rewrite** to render `Member::AuthShellComponent` (was using legacy `_auth_card` partial). Use `input-member` for inputs, `btn-member` for submit, `btn btn-ghost` for cancel. Preserve form field set + autocomplete attrs verbatim.
- `authentication/mfa_setups/show.html.erb`: **rewrite** to render `Member::AuthShellComponent`. QR frame + secret pill + numbered step matches §C.1 mfa setup. Verification input uses `input-otp`. Submit uses `btn-member w-full justify-center`.
- `authentication/mfa_sessions/show.html.erb`: **rewrite** to render `Member::AuthShellComponent`. Verification input uses `input-otp`. Submit `btn-member w-full justify-center`. Recovery / Sign-out links use `text-member-accent-text hover:underline` and `text-text-tertiary hover:underline` respectively.
- `authentication/mfa_recoveries/new.html.erb`: **rewrite** to render `Member::AuthShellComponent`. Use `input-member` for the email field, `btn-member w-full justify-center` for submit, accent-styled "Back to sign-in" link.
- `authentication/mfa_recoveries/create.html.erb`: **rewrite** to render `Member::AuthShellComponent` with a centered confirmation card. Body copy unchanged.

### C.3 Delete legacy partial

- `rm app/views/authentication/shared/_auth_card.html.erb` once all four rewrite views are migrated.
- Verify no other references via `grep -r "authentication/shared/auth_card" app/ spec/`.

---

## Slice D — Specs

### D.1 Component specs (parallel)

For each file in `spec/components/member/*`, audit assertions against new markup and rewrite the ones that no longer hold. Stale-test policy applies: when a spec fails because production HTML intentionally changed, **rewrite the spec**, do not revert production.

- `auth_shell_component_spec.rb` — assert presence of mobile collapsed strip (`lg:hidden`), brand pane (`lg:flex`), and form pane card.
- `detail_grid_component_spec.rb` — update `<dt>`/`<dd>` class assertions if any.
- `empty_state_component_spec.rb` — add coverage for new optional `cta_label:` / `cta_path:` (renders CTA when both present, omits otherwise).
- `hero_card_component_spec.rb` — assert headline classes; assert decorative glyph hidden at `<lg`.
- `index_table_component_spec.rb` — confirm row dividers and hover wash class.
- `page_header_component_spec.rb` — eyebrow chevron SVG present.
- `page_section_component_spec.rb` — `:compact` density now `p-5`; `:flush` unchanged.
- `pagination_component_spec.rb` — buttons no longer carry `btn-ghost` class.
- `shell_component_spec.rb` — main padding asserted at `py-10 lg:py-14`.
- `status_card_component_spec.rb` — value class scale; halo ring; hover translate disabled when `prefers-reduced-motion`.
- `surface_detail_component_spec.rb` / `surface_index_component_spec.rb` — composition unchanged; no edits unless an assertion drifts.
- `top_nav_component_spec.rb` — logo flat fill (no gradient class), `aria-controls`, `aria-expanded`.
- `user_menu_component_spec.rb` — flat avatar fill, `aria-expanded` on trigger.

### D.2 System / request specs

System and request specs in `spec/system/member`, `spec/system/admin/settings/members_spec.rb`, `spec/requests/member/**`, and `spec/requests/admin/settings/members_spec.rb` should not require changes — they assert on user-visible *content* (text, redirects, status codes), not on CSS classes. If any system spec checks raw class strings, rewrite to assert on visible behavior or unique data attributes.

---

## Validation

1. `npm run build` (or rails task that builds Tailwind) succeeds, producing `app/assets/builds/tailwind.css` with the new utility classes resolved.
2. `bundle exec rspec spec/components/member` — green.
3. `bundle exec rspec spec/system/member spec/requests/member` — green.
4. `bundle exec rspec spec/system/authentication spec/requests/authentication` — green (the four rewritten auth views are exercised by these suites).
5. Smoke test (release engineer): start dev server with `SKIP_AUTH=1`, hit:
   - `/81721200/member`
   - `/81721200/member/profile`
   - `/81721200/member/profile/edit`
   - `/81721200/member/security`
   - `/81721200/member/security/mfa/setup`
   - `/81721200/auth/sign_in`
   - `/81721200/auth/password/new`
   - `/81721200/auth/sign_up`
6. Verify no admin pages were affected by spot-checking `/81721200/admin` rendering.

---

## Parallelization plan

Three slices can run as concurrent agents because their file-sets are disjoint:

- **Agent 1 — tokens/layouts/Stimulus** (Slice A): `application.css`, two layout files, two Stimulus files.
- **Agent 2 — components** (Slice B): `app/components/member/*.{rb,html.erb}` (14 components).
- **Agent 3 — views** (Slice C): `app/views/{member,authentication}/**/*.html.erb` and partial deletion.

After all three complete, **Agent 4 — specs** (Slice D) runs sequentially since it depends on the final markup.

Then **Agent 5 — release engineer** (build + smoke).
Then **Agent 6 — code review + tech lead** (correctness + conventions).

---

**READY FOR EXECUTION.**
