# Member Portal Visual Refresh — Implementation Plan

> **For agentic workers:** This plan is executed via the AGENTS.md flowchart pipeline
> (anysys-frontend-developer + anysys-qa-engineer in parallel build, then
> release-engineer, then tech-lead + code-reviewer). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Restyle the whole member portal onto its existing member design system, bringing the
page-builder render wrapper into that language and unifying all member surfaces — presentation
layer only.

**Architecture:** No new components, no controller/model/route changes. All member surfaces route
through the canonical member tokens in `app/assets/tailwind/application.css`. One view is
structurally rewired (`member/pages/show.html.erb`); one component gains an icon switcher
(`EmptyStateComponent`); the rest are class-token substitutions enumerated in the UX spec.

**Tech Stack:** Rails 8, TailwindCSS (v4 `@theme`), ViewComponent, StimulusJS, RSpec.

**Authoritative specs:**
- Design: `docs/superpowers/specs/2026-06-12-member-portal-visual-refresh-design.md`
- UX (per-surface class tables S1–S17 + Design Decisions Table §6): `docs/superpowers/specs/2026-06-12-member-portal-visual-refresh-ux.md`

The UX spec's per-surface tables (§2) and Design Decisions Table (§6) are the authoritative list of
exact class changes. This plan does not repeat them (DRY); it groups them into parallel-safe build
units and defines the structural changes + verification.

---

## File Structure & Parallel Build Groups

Three groups partitioned by directory so there is **no file overlap** and they can be built in
parallel. Group B renders Group A's components by their existing public interface (stable contract),
so it does not need to wait on A.

- **Group CSS** (do as part of Group A; single shared file): `app/assets/tailwind/application.css`
  — add the member cyan focus ring to `btn-member` and `nav-item-member`; confirm `text-mono`,
  `text-label`, `text-heading` utilities exist (used by views).
- **Group A — Member ViewComponents** (`app/components/member/*.rb` + `*.html.erb`): empty_state
  (icon switcher), page_header, page_section, page_layout, detail_grid, index_table, pagination,
  status_card, hero_card, shell, top_nav, user_menu, surface_index, surface_detail, auth_shell.
- **Group B — Member views + layout** (`app/views/member/**/*.erb`, `app/views/layouts/member.html.erb`):
  pages/show (structural rewire), dashboards/show, profiles/show, profiles/edit, securities/show,
  mfa/setup, surfaces/index, surfaces/show.

---

## Task 1: CSS — member focus ring + utility confirmation (Group CSS)

**Files:**
- Modify: `app/assets/tailwind/application.css` (the `btn-member` and `nav-item-member` component classes)

- [ ] **Step 1:** Confirm utilities `text-mono`, `text-label`, `text-heading`, `card-member-elevated`,
  `hero-member`, `input-member`, `nav-item-member(-active)`, `btn-member` exist in the `@layer`
  blocks. If `text-mono` is absent, add it: `font-family: var(--font-family-mono); font-size: var(--text-xs); letter-spacing: 0;`.
- [ ] **Step 2:** Add the member cyan focus ring to `btn-member` and `nav-item-member` so member
  interactive elements override the global indigo `:focus-visible`. Add to each class body:

```css
&:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px var(--color-member-paper), 0 0 0 4px var(--color-member-accent);
}
```

  (Equivalent to `ring-2 ring-member-accent ring-offset-2` in the member paper context. Keep
  `input-member`'s existing focus box-shadow unchanged per UX §5.)
- [ ] **Step 3:** Verify the stylesheet still compiles: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails assets:precompile 2>&1 | tail -5` (or rely on dev-mode Tailwind). Expected: no errors.
- [ ] **Step 4:** Commit: `git commit -am "style(member): add member focus ring to btn/nav, confirm utilities"`

---

## Task 2: EmptyStateComponent icon switcher (Group A)

**Files:**
- Modify: `app/components/member/empty_state_component.rb` (+ `.html.erb`)
- Test: `spec/components/member/empty_state_component_spec.rb`

- [ ] **Step 1 (test first):** Add/extend the spec to assert that `icon: :document` renders the
  document SVG path and `icon: :plus` renders the plus path:

```ruby
it "renders the document icon variant" do
  render_inline(described_class.new(icon: :document, headline: "None", body: "x"))
  expect(page).to have_css("svg path[d*='M9 12h6']")
end

it "defaults to the plus icon" do
  render_inline(described_class.new(headline: "None", body: "x"))
  expect(page).to have_css("svg path[d='M12 4v16m8-8H4']")
end
```

- [ ] **Step 2:** Run: `bundle exec rspec spec/components/member/empty_state_component_spec.rb` — expect FAIL (document path hardcoded as plus).
- [ ] **Step 3:** In the component, add an `icon_path` helper using a `case icon` switcher with the
  four variants from UX §S11 (`:plus`, `:document`, `:search`, `:inbox`), defaulting to `:plus`.
  Render `icon_path` in the `<path d=...>` in the template. Keep all other classes unchanged.
- [ ] **Step 4:** Run the spec — expect PASS.
- [ ] **Step 5:** Commit: `git commit -am "feat(member): icon variants for EmptyStateComponent"`

---

## Task 3: Member ViewComponent token unification (Group A)

**Files (modify, per UX §2 tables):**
- `page_header_component.html.erb` (S5), `page_section_component.html.erb` (S6),
  `page_layout_component.html.erb` (S7), `detail_grid_component.html.erb` (S8 → `text-label`),
  `index_table_component.html.erb` (S9 → `overflow-x-auto` wrapper),
  `pagination_component.html.erb` (S10 → `aria-label="Pagination"` + hover transition),
  `status_card_component.html.erb` (S4), `hero_card_component.html.erb` (S4),
  `shell_component.html.erb` (S2 → flash `rounded-2xl`), `top_nav_component.html.erb` (S2 →
  `bg-member-paper-elevated/90`), `user_menu_component.html.erb` (S3 → `rounded-2xl` + transition + focus ring),
  `surface_index_component.html.erb` (S12), `surface_detail_component.html.erb` (S13 → mono values)
- Test: `spec/components/member/*_spec.rb` for each component whose rendered structure changes

- [ ] **Step 1 (tests):** For each component changing a structural/asserted class (index_table
  `overflow-x-auto`, pagination `aria-label`, user_menu `rounded-2xl`, top_nav background, detail_grid
  `text-label`), add/update a spec example asserting the new class/attribute. Follow the stale-test
  policy — rewrite existing assertions that referenced removed classes.
- [ ] **Step 2:** Run the member component specs — expect the new assertions to FAIL.
- [ ] **Step 3:** Apply the exact class substitutions from the UX §2 tables and the §5 token
  substitution rules to each component template. No interface/prop changes. No logic changes beyond
  the enumerated swaps.
- [ ] **Step 4:** Run `bundle exec rspec spec/components/member` — expect PASS.
- [ ] **Step 5:** Commit: `git commit -am "style(member): unify member ViewComponents on member tokens"`

---

## Task 4: Page render wrapper structural rewire (Group B, HEADLINE)

**Files:**
- Modify: `app/views/member/pages/show.html.erb`
- Test: `spec/requests/member/pages_spec.rb` (assert member chrome present, no generic/page-chrome classes)

- [ ] **Step 1 (test):** In the member pages request spec, assert the rendered page (a) does NOT
  contain `class="card ` or `border-border-subtle` or a `page_chrome_header_color` output, and (b)
  DOES contain `card-member-elevated` and the page name in a member header. For the blank-content
  case assert the member empty state copy renders.
- [ ] **Step 2:** Run `bundle exec rspec spec/requests/member/pages_spec.rb` — expect FAIL.
- [ ] **Step 3:** Rewrite the view per UX §S1:

```erb
<%# Rendered view of a built page for the member audience (member layout). %>
<% content_for :title, "#{@page.name} — Account" %>
<div class="space-y-6">
  <%= render Member::PageHeaderComponent.new(
        title:    @page.name,
        subtitle: @page.description.presence,
        eyebrow:  (defined?(@back_path) && @back_path.present? ? { label: "Back to #{@back_label}", path: @back_path } : nil)
      ) %>

  <% if @content.present? %>
    <%= render Member::PageSectionComponent.new(density: :flush) do %>
      <%= render inline: @content %>
    <% end %>
  <% else %>
    <%= render Member::EmptyStateComponent.new(
          icon:     :document,
          headline: "No content yet",
          body:     "This page has no content to render yet."
        ) %>
  <% end %>
</div>
```

  (Confirm `PageHeaderComponent`/`PageSectionComponent`/`EmptyStateComponent` accept these exact
  props; adjust prop names to the real signatures if they differ. The inner `@content` is rendered
  verbatim — its per-page theme is untouched.)
- [ ] **Step 4:** Run `bundle exec rspec spec/requests/member/pages_spec.rb` — expect PASS.
- [ ] **Step 5:** Commit: `git commit -am "feat(member): page render wrapper uses member design language"`

---

## Task 5: Member view token unification (Group B)

**Files (modify, per UX §2 tables):**
- `dashboards/show.html.erb` (S4 → avatar `rounded-full`), `profiles/show.html.erb` (S14 → avatar
  `rounded-full`), `profiles/edit.html.erb` (S14 → error container `rounded-2xl p-4`),
  `securities/show.html.erb` (S15), `mfa/setup.html.erb` (S16 → QR wrapper `card-member-elevated inline-block`),
  `surfaces/index.html.erb` (S12), `surfaces/show.html.erb` (S13), `layouts/member.html.erb` (verify)
- Test: existing request/system specs covering these views

- [ ] **Step 1:** Apply the enumerated class swaps from UX §S4/S14/S15/S16 to each view. No structural
  change beyond the avatar/error-container/QR-wrapper swaps.
- [ ] **Step 2:** Run the relevant request specs (`spec/requests/member/*`) — fix any assertions that
  referenced removed classes (stale-test policy).
- [ ] **Step 3:** Commit: `git commit -am "style(member): unify member views on member tokens"`

---

## Task 6: Stimulus — user-menu keyboard/aria (Group A, conditional)

**Files:**
- Modify: `app/javascript/controllers/user_menu_controller.js` (only if missing behaviors)

- [ ] **Step 1:** Read the existing `user-menu` controller. Confirm it handles click-outside
  dismissal, `Escape` close, and `aria-expanded` toggle (UX §5). If all present, skip this task.
- [ ] **Step 2:** If any is missing, add the minimal action/handler. Stimulus only, no new libs.
- [ ] **Step 3:** Commit (if changed): `git commit -am "fix(member): user-menu escape/aria-expanded"`

---

## Verification (release-engineer)

- [ ] `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` (background)
- [ ] Run touched specs: `bundle exec rspec spec/components/member spec/requests/member`
- [ ] Smoke-hit representative member URLs: dashboard, a built page render, profile show, surfaces index.
- [ ] Report PASS/FAIL with trimmed output.

## Review (parallel)

- [ ] anysys-tech-lead: AGENTS.md conventions (Tailwind-only, Stimulus-only, ViewComponent purity,
  no generic/page-chrome tokens leaking into member, member URL auth unchanged).
- [ ] anysys-code-reviewer: correctness (no broken renders, props match component signatures),
  no security/tenant regressions (this is presentation-only, confirm no auth/scoping touched).

---

## Self-Review

- **Spec coverage:** S1 → Task 4; S2/S3 + all components → Task 3; S11 → Task 2; CSS focus ring →
  Task 1; S4/S14/S15/S16 views → Task 5; Stimulus → Task 6. S5/S6/S7/S12/S13 → Task 3. All 17
  surfaces covered.
- **Placeholders:** none — structural code given for the two non-trivial changes (S1 view, S11
  switcher) and CSS; class-swap tables are delegated to the authoritative UX spec by reference (DRY).
- **Contract consistency:** Group B (Task 4) uses `PageHeaderComponent`/`PageSectionComponent`/
  `EmptyStateComponent` by existing interface; Task 4 Step 3 instructs verifying real prop names
  before finalizing, preventing signature mismatch.
- **Constraint:** no controller/model/route changes; `@back_path` eyebrow is optional and nil-safe.
