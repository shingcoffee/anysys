# Member Portal — Elegant Re-theme + Sidebar Shell (Design)

**Date:** 2026-06-12
**Status:** Approved
**Model for execution:** Fable 5 (all design/build/review agents)

## Goal

Make the whole member portal visually consistent with the **rendered page content of
`/81721200/member/pages/43`**, and redesign the shell into a **left sidebar** layout that is more
beautiful and attractive.

## Reference — page 43's content styling (the "elegant" preset)

Read from page 43's `configuration.theme`, resolved via `ThemeResolver`:

| Aspect | Theme value | Resolves to |
|---|---|---|
| primary/accent color | `violet` | `bg-violet-600` / `text-violet-600` / soft `bg-violet-100` / `ring-violet-500` |
| font | `serif` | `font-serif`; headers `text-violet-900 font-serif` |
| border_radius | `md` | `rounded-md` (0.5rem) |
| form_background | `warm` | `bg-amber-50/60` |
| form_shadow | `sm` | `shadow-sm` |
| form_border | `subtle` | `border border-gray-100` |
| field_spacing | `relaxed` | `space-y-8` |
| button_style | `soft` | violet-tinted soft button (`bg-violet-100` → `hover:bg-violet-200`) |
| input_style / size | `outline` / `md` | outline inputs, `px-3 py-2 text-sm` |

**Design language to adopt portal-wide:** warm, elegant, **violet accent + serif display headings**,
medium radius, soft buttons, subtle borders, gentle `shadow-sm`, relaxed spacing.

This **reverses** the earlier "portal-only polish / don't pull per-page theme" decision: page 43's
theme is now the canonical member design language.

## Approach

The prior refresh already routes every member surface through shared member tokens in
`app/assets/tailwind/application.css`. So we **re-tune those tokens** to page 43's language and the
whole portal inherits it; then we **redesign the shell** into a sidebar on top.

### 1. Re-tune member design tokens (`application.css` `@theme`)

| Token | Current (cyan) | New (elegant violet/warm) |
|---|---|---|
| `--color-member-accent` | `#0891b2` | `#7c3aed` (violet-600) |
| `--color-member-accent-hover` | `#0e7490` | `#6d28d9` (violet-700) |
| `--color-member-accent-active` | `#155e75` | `#5b21b6` (violet-800) |
| `--color-member-accent-subtle` | `#ecfeff` | `#f5f3ff` (violet-50) |
| `--color-member-accent-muted` | `#a5f3fc` | `#ddd6fe` (violet-200) |
| `--color-member-accent-text` | `#0e7490` | `#6d28d9` (violet-700) |
| `--color-member-accent-soft` | `#cffafe` | `#ede9fe` (violet-100) |
| `--color-member-accent-ink` | `#083344` | `#4c1d95` (violet-900) |
| `--color-member-paper` | `#fbfaf6` | `#fbf8f2` (warm cream) |
| `--color-member-paper-elevated` | `#ffffff` | `#fffdf9` (warm white) |
| `--color-member-border-warm` | `#ece8df` | `#e9e3d6` (warm subtle border) |

- `--gradient-member-hero` references `--color-member-accent*`, so it re-themes to violet automatically.
- **Radius:** introduce/lower the member card radius toward page 43's `rounded-md`. Cards move from
  `--radius-2xl` (1rem) to `--radius-lg` (0.625rem) for an elegant, slightly-softened match (the UX
  spec finalizes the exact value; target visual parity with the content's `rounded-md`).
- **Shadow:** soften `--shadow-member-card` toward a gentle `shadow-sm`-like elevation (subtle, not heavy).

### 2. Serif display headings

Member heading utilities (`text-heading`, the page/section header titles, hero title) adopt
`font-family: var(--font-family-serif)` and a violet-ink color, matching page 43's
`text-violet-900 font-serif`. Body text stays sans (Inter) for readability — serif is for display
headings only (the elegant convention). Add `--font-family-serif` if not already present.

### 3. Redesign shell → left sidebar

Replace the current top-nav shell with a **left sidebar**:

```
┌──────────┬─────────────────────────────────┐
│ ✦ Mark   │  Page Title (serif, violet-900) │
│ (serif)  │                                 │
│ ▸ Home   │  ┌───────────────────────────┐  │
│ ▸ Forms  │  │ content card (rounded,    │  │
│ ▸ Profile│  │ shadow-sm, warm)          │  │
│ ▸ Security  │                           │  │
│          │  └───────────────────────────┘  │
│ ──────── │                                 │
│ ◉ User   │            warm bg              │
└──────────┴─────────────────────────────────┘
```

- **Sidebar rail** (desktop ≥ lg): fixed/sticky left column (~`w-64`), warm elevated surface, violet
  serif wordmark at top, vertical nav items (active = violet soft bg + violet-ink text + serif),
  user menu pinned at the bottom.
- **Content area:** to the right, warm `member-paper` background, spacious centered column
  (`max-w-*`), per-page header (serif violet title) over content cards.
- **Responsive:** below `lg`, the sidebar collapses to an off-canvas **drawer** toggled by a
  hamburger in a slim top bar; backdrop overlay; Esc/scrim closes. Stimulus controller (e.g.
  `member-sidebar`) handles open/close + `aria-expanded` + focus management. Stimulus only.

### Components affected

- `Member::ShellComponent` (+ template) — becomes the sidebar+content layout.
- `Member::TopNavComponent` → replaced by a `Member::SidebarComponent` (new) for the rail; the old
  top-nav is removed or repurposed as the mobile top bar. `Member::UserMenuComponent` re-placed in
  the sidebar footer.
- `app/views/layouts/member.html.erb` — wires the new shell; container-width contract preserved or
  simplified.
- New/updated Stimulus: `member_sidebar_controller.js` (mobile drawer) — replaces/augments the
  `mobile-nav` behavior; remove now-unused top-nav mobile sheet logic.
- All other member components/views inherit the re-themed tokens automatically; spot-check
  hero/auth/status cards for the violet/serif/warm result.

## Non-Goals / Constraints

- **Inner page-builder content is untouched.** `member/pages/show.html.erb` still renders
  `@content` verbatim with its own per-page theme. We only re-theme the member **chrome**.
- Tailwind only, Stimulus only (AGENTS.md). Responsive across mobile/tablet/desktop.
- No controller/model/route/auth changes — presentation only. Member URL guards intact.
- ViewComponent encapsulation preserved.

## Testing

- Update component specs for the shell change (sidebar structure, mobile drawer, active states) and
  any spec asserting cyan tokens → assert the violet/serif/warm tokens (stale-test policy: rewrite,
  don't revert production).
- Run `spec/components/member` + `spec/requests/member`; confirm green on the `launched` schema.

## Execution Pipeline (all Fable 5)

anysys-ux-designer (token map + sidebar mockup) → anysys-frontend-developer (implement) →
anysys-qa-engineer (specs) → anysys-release-engineer (specs + assets) →
parallel anysys-tech-lead + anysys-code-reviewer.
