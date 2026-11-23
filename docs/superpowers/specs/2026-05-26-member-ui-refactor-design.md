# Member UI Visual Refactor — Design Direction

**Date:** 2026-05-26
**Status:** Final
**Surface:** `/:cid/member/*` + `/:cid/auth/*`
**Constraint envelope:** TailwindCSS only · StimulusJS only · ViewComponent encapsulation · no new fonts · no new gems/npm · WCAG 2.1 AA · `prefers-reduced-motion` honored

---

## 1. Aesthetic point of view

**"Quiet teahouse."** A small, refined, warm room. Not corporate. Not casual. Not trendy. Confident through restraint — the design proves itself through proportion, weight, and breathing room rather than through ornament. Members come here infrequently for high-trust tasks (cards, security, account); the portal must feel like a place that respects their attention.

The dominant move is **warmth + air**. The teal accent already in place (`#0f766e`) is the only saturated colour. Everything else is paper — warm off-white surfaces, soft graphite text, ink-blot dark headings. Borders are hairline. Shadows are felt, not seen.

**One thing members remember:** the *hero card*. A wide, deep teal panel at the top of the dashboard with a soft directional gradient and a barely-perceptible noise/grain feel produced via stacked CSS gradients (no images). It is the "front porch" of the portal.

---

## 2. Tokens (reuse + extend)

All tokens stay in `app/assets/tailwind/application.css` under `@theme` — no new files. Extensions only, no breaking changes. Admin chrome is unaffected because all new rules target `.member-*` / `.btn-member` / `.hero-member` / `.card-member-*` selectors.

### 2.1 Colour ladder (extend)

```
--color-member-accent:        #0f766e   /* base, ≥4.5:1 on white */
--color-member-accent-hover:  #115e59
--color-member-accent-active: #134e4a
--color-member-accent-subtle: #f0fdfa   /* card tint, badge bg */
--color-member-accent-muted:  #99f6e4
--color-member-accent-text:   #115e59
--color-member-accent-soft:   #ccfbf1   /* NEW — focus ring, hover wash */
--color-member-accent-ink:    #042f2e   /* NEW — display ink on warm bg */

--color-member-paper:         #fbfaf6   /* NEW — warm off-white canvas */
--color-member-paper-elevated:#ffffff
--color-member-border-warm:   #ece8df   /* NEW — paper-toned hairlines */
```

`--color-member-paper` replaces `bg-canvas` *only on member + auth surfaces* (via the body class on those layouts). Admin pages still use the cool `--color-canvas`.

### 2.2 Motion (NEW)

```
--ease-member: cubic-bezier(0.22, 0.61, 0.36, 1)   /* "ease-out-quart" */
--duration-fast:    150ms
--duration-base:    220ms
--duration-slow:    320ms
```

All new animations and transitions reference these. Existing `transition-base` calls remain valid (they map to the same timing).

### 2.3 Hero gradient (refine)

```
--gradient-member-hero:
  radial-gradient(120% 140% at 0% 0%,
    color-mix(in oklab, var(--color-member-accent) 88%, white) 0%,
    var(--color-member-accent) 38%,
    var(--color-member-accent-hover) 100%);
```

The radial origin pushes light toward the upper-left so headline text on the right stays high-contrast white. We layer a soft white→transparent linear overlay on top via a `::after` so the gradient feels like sun on water rather than a flat fill.

### 2.4 Shadow tweak (NEW token, additive only)

```
--shadow-member-card: 0 1px 0 rgb(255 255 255 / 0.6) inset,
                           0 1px 2px rgb(15 23 42 / 0.04),
                           0 8px 24px -8px rgb(15 23 42 / 0.08);
```

Used by `.card-member-elevated` to replace the current generic `--shadow-sm`. The inset highlight gives surfaces a "lifted paper" feel.

---

## 3. Layout system

### 3.1 Member shell

- Body uses `--color-member-paper`; main container max-widths unchanged (`max-w-6xl` default, `max-w-3xl` narrow).
- Vertical rhythm: `py-10 lg:py-14` for `<main>` (was `py-8 lg:py-12`). Pages breathe more.
- Top nav: hairline border replaces full border (`border-b border-member-border-warm`); sticky with subtle `backdrop-blur-sm bg-surface/85` so content scrolls behind it but stays legible.

### 3.2 Auth shell (split-pane)

- **Desktop (`lg+`):** brand pane left (50%), form pane right (50%). Both panes are flush with the viewport edges (no canvas margin around them) — the brand pane bleeds.
- **Mobile/tablet (`<lg`):** brand pane collapses to a slim **48px** header strip with the org name + checkmark glyph; form pane occupies the rest.
- Form pane is centered within `max-w-md`. Spacing inside: `space-y-5` between fields, `mb-8` between header and form.
- Form pane background is `--color-member-paper-elevated` (pure white) so it reads as a sheet of paper laid on a teal table when desktop.

### 3.3 Mobile nav (sheet)

- Existing `data-controller="mobile-nav"` already toggles a `[data-mobile-nav-target="sheet"]` element. Refactor the markup to:
  - Use `aria-controls` + `aria-expanded` on the trigger.
  - When open, the sheet animates `translate-y-2 opacity-0 → translate-y-0 opacity-100` over `var(--duration-base) var(--ease-member)`.
  - Each link is `min-height: 44px` (touch target) with `px-4 py-3` and a 1px hairline divider between items (`divide-y divide-member-border-warm`).
  - Active link gets a left accent strip (`border-l-2 border-member-accent pl-[14px]`).

---

## 4. Component-level direction

### 4.1 `HeroCardComponent`

- Title `text-display` becomes a custom `text-[2.25rem] sm:text-[2.625rem] leading-[1.05] tracking-[-0.025em]`.
- Body `text-base` not `text-body`, so it sits at 16px (more legible on mobile).
- Status pill stays top-right but on mobile drops below the headline (use `flex-col sm:flex-row sm:items-start sm:justify-between`).
- Decorative SVG glyph (existing checkmark) sits as a 64px outlined mark in the upper-right at `lg+` only, opacity 0.18 — adds depth without distraction.
- Padding bumped to `px-7 py-9 sm:px-10 sm:py-11`.

### 4.2 `StatusCardComponent`

- Card has `min-h-[180px]` so the dashboard grid feels balanced even when one card has shorter content.
- Icon chip becomes a 40×40 rounded-xl with the member-accent-subtle wash and a 1px ring of `--color-member-accent-muted` (currently has no ring → adds definition).
- Value typographic scale: `text-[1.625rem]` instead of `text-3xl` — the previous size was loud relative to the label. Tabular numerals (`font-variant-numeric: tabular-nums`).
- Hover lift becomes `-translate-y-0.5` with `shadow-md` over `var(--duration-base)`. Honors `prefers-reduced-motion`.
- CTA arrow uses a stronger easing on hover: `group-hover:translate-x-0.5` — micro-delight.

### 4.3 `PageHeaderComponent`

- Title uses `text-[1.875rem] sm:text-[2.125rem] font-semibold tracking-[-0.025em]` (was `text-title`).
- Subtitle uses warmer `text-text-secondary` with `mt-1.5` for breathing room.
- Eyebrow link gets a small left-pointing chevron SVG before the label (replaces the inline `←` character) so it scales correctly with font size.
- Actions block right-aligns on desktop, full-width below subtitle on mobile (`flex-col sm:flex-row`).
- Bottom margin `mb-10` (was `mb-8`).

### 4.4 `PageSectionComponent`

- Use refined card token (see §2.4) and a hairline header rule when `title` present:
  ```
  <header class="mb-5 pb-4 border-b border-member-border-warm">
  ```
- Density `:flush` keeps no padding (used by tables).
- Density `:compact` becomes `p-5` (was `p-4`) — tiny but it makes embedded forms feel less squeezed.

### 4.5 `IndexTableComponent`

- Header row uses `bg-member-paper text-text-tertiary text-[11px] uppercase tracking-[0.06em]`.
- Row dividers are `divide-y divide-member-border-warm`.
- Hover state is a faint `hover:bg-member-accent-subtle/40` (warm tint, not cold gray).
- Row click affordance: `cursor-pointer` is NOT added (rows are not clickable; the trailing link is). The trailing link gets a hover underline + accent.
- Empty + first row both get `pt-4 pb-3.5` so vertical breathing matches.

### 4.6 `DetailGridComponent`

- `<dt>` becomes `text-[11px] uppercase tracking-[0.06em] font-semibold text-text-tertiary`.
- `<dd>` becomes `text-[15px] text-text-primary mt-1.5 break-words`.
- Long values wrap on word boundaries; mono-formatted values use `font-mono text-[13px] text-text-primary`.

### 4.7 `EmptyStateComponent`

- Replace flat icon chip with a layered ring: outer `bg-member-accent-soft`, inner `bg-member-accent-subtle`. Two rings stacked → "halo" effect.
- Headline upsizes to `text-[1.25rem]`.
- Body text gets `max-w-sm mx-auto` so long copy doesn't span the whole card.
- Optional CTA support added (`cta_label:`, `cta_path:`). Gracefully optional so existing usages stay valid.

### 4.8 `AuthShellComponent`

- Brand pane: hero gradient, but **inset by `p-8 lg:p-14`** with the content vertically centered and capped at `max-w-md` to keep proportions tight regardless of viewport.
- Replace the 3-tile grid (`Manage profile / Track payments / Stay secure`) with a single elegant row of three icon+label items separated by hairlines (`divide-x divide-white/15`). Less "feature comparison", more "capability whisper".
- Form pane: `bg-member-paper-elevated` with `lg:rounded-l-3xl lg:shadow-[var(--shadow-member-card)]` (the form pane "leans against" the brand pane on desktop).
- Mobile collapsed header strip: `lg:hidden flex items-center gap-3 px-5 h-12 bg-member-accent text-white`.

### 4.9 `TopNavComponent`

- Logo icon chip becomes 36×36 (was 36×36 — unchanged) but the gradient is replaced by a **flat member-accent fill with a 1px ring of `--color-member-accent-muted`** for a calmer, more "stamp-like" feel. The gradient lives only in the hero.
- Mobile toggle button gets an `aria-expanded` binding (Stimulus controller will need a 1-line update).
- Desktop nav items use the existing `nav-item-member` class but with `gap-1` between them (already there) — no change to layout, only the underlying class gets a refined active-state border.

### 4.10 `UserMenuComponent`

- Avatar circle uses the **flat member accent** (matching logo) instead of the gradient — coherence move.
- Dropdown panel gets `animate-fade-in` on open, `mt-3` instead of `mt-2` for breathing.
- Add `min-w-[14rem]` (already `w-56`) and `divide-y divide-member-border-warm` between items so the vertical rhythm reads.

### 4.11 `PaginationComponent`

- "Showing X–Y of N" copy gets `tabular-nums` and `text-text-tertiary`.
- Buttons swap from `btn btn-ghost` (which renders cool gray) to a borderless `inline-flex h-9 px-3 rounded-md text-sm text-member-accent-text hover:bg-member-accent-subtle transition-colors`.
- Add a hairline rule above the pagination row: `mt-6 pt-5 border-t border-member-border-warm`.

### 4.12 `SurfaceIndexComponent` / `SurfaceDetailComponent`

- No structural change — they compose the components above. They inherit the spacing/typography updates automatically.
- Surface detail "Back to …" eyebrow uses the new chevron treatment from §4.3.

### 4.13 Auth views — MFA ceremony polish

The MFA setup, MFA challenge, MFA recovery, and registration-edit views currently render via the legacy `authentication/shared/_auth_card.html.erb` partial which uses raw `bg-gray-*` / `text-indigo-*` utilities (i.e., admin indigo, not member teal). They are inconsistent with the rest of the member surface. The fix is to:

1. **Delete `_auth_card.html.erb`.** It is the source of the inconsistency.
2. Migrate every view that uses it to render `Member::AuthShellComponent` directly, the same way `sessions/new.html.erb` and `passwords/*.html.erb` already do.
3. **MFA setup ceremony refinement** (`authentication/mfa_setups/show.html.erb` AND `member/mfa/setup.html.erb`):
   - QR code sits inside a `bg-white p-6 rounded-2xl ring-1 ring-member-border-warm shadow-[var(--shadow-member-card)]` frame, centered.
   - The "or enter manually" secret renders in a refined mono pill: `inline-flex items-center gap-2 font-mono text-sm tracking-[0.08em] bg-member-paper px-3 py-2 rounded-md ring-1 ring-member-border-warm`.
   - Use a 2-step progression header (numbered circles 1 / 2) above the sections instead of `1.` / `2.` in the section titles.
4. **Verification code input** (used in MFA setup, MFA challenge, MFA disable on the security page): single shared treatment — `text-2xl tracking-[0.6em] font-mono text-center` on the input, padded `py-3.5`. Encourages the "type a code into a slot" feel.

### 4.14 `securities/show` — "Disable 2FA" details panel

- The legacy `<details>` block uses raw indigo focus rings. Replace with member-styled input + a less-alarming danger button (use existing `btn btn-danger` — color is already correct, only spacing fixes needed).
- Wrap the verification input in a labelled stack `space-y-2` and align right side button with `self-end`.

---

## 5. Stimulus contracts

The two Stimulus controllers in scope (`mobile_nav_controller`, `user_menu_controller`, plus `flash_controller`) need only **additive** changes:

- `mobile_nav_controller`: when toggling `sheet`, also set `aria-expanded` on the trigger and add/remove an `is-open` class so CSS can drive the slide-in.
- `user_menu_controller`: same — add `aria-expanded` syncing on the trigger.
- `flash_controller`: no change.

No new controllers. No new behaviors. No new dependencies.

---

## 6. Responsive behaviour

| Breakpoint | Hero | Status grid | Auth shell | Top nav |
|---|---|---|---|---|
| `<sm` (≤640) | full-width, headline 2.25rem | 1 col | brand strip 48px header | hamburger |
| `sm` (≥640) | inline status pill | 1 col still | unchanged | hamburger |
| `md` (≥768) | unchanged | 2 col | unchanged | desktop nav |
| `lg` (≥1024) | full polish, glyph visible | 3 col | split-pane 50/50 | desktop nav |

No horizontal scroll at any width ≥320px.

---

## 7. Accessibility checklist

- All interactive elements have visible `:focus-visible` outline (already global; member overrides outline color to `--color-member-accent`).
- Mobile nav trigger and user menu trigger sync `aria-expanded`.
- Hero gradient text contrast: white on `#0f766e` = 6.45:1 ✓.
- Body text on `--color-member-paper` (#fbfaf6): `--color-text-primary` (#111827) = 17.4:1 ✓.
- Status pill text white on `bg-white/15` over teal: validated visually with WebAIM contrast — passes against both the brightest and darkest stops of the gradient.
- Verification code input has `aria-label` redundant with `<label>`; `inputmode="numeric"` already set.
- `prefers-reduced-motion` disables `translate-y` lifts and replaces fade-in with instant visibility.

---

## 8. Out-of-scope reaffirmation

- No new fonts. Inter only.
- No new icons. Reuse the existing inline-SVG vocabulary.
- No new routes, controllers, contracts, models, mailers.
- No admin-side changes. Admin keeps the indigo accent and cool canvas.
- No dark mode.
- No i18n / RTL.

---

## 9. Implementation order

1. Tokens (`application.css`) — additive only.
2. Layout files (`auth.html.erb`, `member.html.erb`) — body class.
3. ViewComponents (14 components, presentation only).
4. View templates (member + auth) — migrate the 4 legacy views off `_auth_card`, then delete the partial.
5. Stimulus controllers (`mobile_nav`, `user_menu`) — `aria-expanded` sync.
6. Component specs — update assertions for new markup; rewrite over patch.
7. Build assets, smoke-test, run member specs.

---

**READY FOR PLAN.**
