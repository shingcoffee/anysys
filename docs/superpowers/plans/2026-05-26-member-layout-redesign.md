# Plan: Member Pages Layout Redesign

**Date:** 2026-05-26
**Design:** `docs/superpowers/specs/2026-05-26-member-layout-redesign-design.md`
**Branch (worktree):** `worktree-refactor-member-layout-styling`

Presentation-layer-only. No models, migrations, controllers, routes, contracts, activities. Touched files exclusively under:

- `app/components/member/**`
- `app/views/member/**`
- `app/services/member/navigation.rb`
- `spec/components/member/**`
- `spec/services/member/**`

---

## Slice A — Foundation (sequential, must land first)

### A.1 Widen container

`app/components/member/shell_component.rb`:
```ruby
CONTAINER_CLASSES = {
  default: "max-w-screen-2xl mx-auto px-4 sm:px-6 lg:px-8",
  narrow:  "max-w-3xl mx-auto px-4 sm:px-6 lg:px-8",
  edge:    "w-full"
}.freeze
```

`app/components/member/top_nav_component.html.erb` line 4: `max-w-7xl` → `max-w-screen-2xl`.

`spec/components/member/shell_component_spec.rb`: `main.max-w-7xl` → `main.max-w-screen-2xl` (both occurrences).

### A.2 Filter Profile + Security from nav

`app/services/member/navigation.rb` — add a constant `HIDDEN_FROM_TOP_NAV = %i[builtin_profile builtin_security].freeze` and reject those keys after the existing visibility filter:

```ruby
def self.items_for(user)
  Member::Surfaces
    .for(customer: user.customer)
    .map { |effective| item_from_effective(effective) }
    .select { |item| item.visible_to?(user) }
    .reject { |item| HIDDEN_FROM_TOP_NAV.include?(item.key) }
end
```

Add a one-line comment explaining: "Hidden from the member top-nav because the user-menu dropdown already exposes them; they remain reachable via direct URL and via the dropdown."

`spec/services/member/navigation_spec.rb` — rewrite the first two examples per the design's spec-impact note.

`spec/components/member/top_nav_component_spec.rb` — change `current_nav: :builtin_profile` → `current_nav: :builtin_home` in the active-state example so it tests against an item that actually renders.

### A.3 New `Member::PageLayoutComponent`

`app/components/member/page_layout_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # 12-column primary/aside layout primitive used by every member
  # page. Hero (optional) renders full-bleed above the grid; primary
  # spans cols 1–8 (or 1–12 when no aside is given); aside spans cols 9–12.
  class PageLayoutComponent < ApplicationComponent
    renders_one :hero
    renders_one :primary
    renders_one :aside

    def primary_span_class
      aside? ? "lg:col-span-8" : "lg:col-span-12"
    end
  end
end
```

`app/components/member/page_layout_component.html.erb`:

```erb
<div data-component="member-page-layout" class="space-y-8">
  <% if hero? %>
    <%= hero %>
  <% end %>

  <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
    <div class="<%= primary_span_class %> space-y-6 min-w-0"><%= primary %></div>

    <% if aside? %>
      <aside class="lg:col-span-4 space-y-5 min-w-0"><%= aside %></aside>
    <% end %>
  </div>
</div>
```

New spec `spec/components/member/page_layout_component_spec.rb` — covers:
- Renders only primary when neither hero nor aside given (primary spans 12).
- Renders hero above grid when given.
- Aside slot renders into `<aside>` element with `lg:col-span-4`.
- Primary collapses to `lg:col-span-12` when aside omitted.

---

## Slice B — Page reflow: Home + Profile (parallel-safe after A)

### B.1 `app/views/member/dashboards/show.html.erb`

Wrap in `Member::PageLayoutComponent`:
- `with_hero` → existing `HeroCardComponent` call.
- `with_primary` → 3-up StatusCardGrid (existing markup, unchanged) + "Recent activity" PageSection.
- `with_aside` → "Quick links" `PageSectionComponent` listing **Update profile** / **Manage security** / **Sign out** (links use `link_to` to the existing paths) + small "Account" card showing initials chip + email.

### B.2 `app/views/member/profiles/show.html.erb`

Wrap in `Member::PageLayoutComponent`:
- `with_primary` → existing `PageHeaderComponent` + identity card (avatar/name/email block) + `DetailGridComponent` (already 3-col after the prior commit). Drop the inline "Sign out" — moves to the aside.
- `with_aside` → "Account actions" PageSection with **Edit profile** primary button and **Sign out** ghost button + "Security at a glance" PageSection showing the user's MFA status (mirror of `current_user.mfa_required?` — render the same icon+copy as `securities/show.html.erb` lines 22–37 but compressed) with a **Manage security** link.

### B.3 `app/views/member/profiles/edit.html.erb`

Wrap in `Member::PageLayoutComponent`:
- `with_primary` → existing `PageHeaderComponent` + form `PageSectionComponent`. Form structure unchanged; the existing 2-col `grid grid-cols-1 sm:grid-cols-2 gap-4` for first/last name remains.
- `with_aside` → small "Tip" PageSection with copy: *"Email changes require re-confirmation. We'll send a verification link to your new address before applying it."*

---

## Slice C — Page reflow: Security + MFA setup (parallel-safe after A)

### C.1 `app/views/member/securities/show.html.erb`

Wrap in `Member::PageLayoutComponent`:
- `with_primary` → existing `PageHeaderComponent` + the three stacked sections (Password / 2FA / Last sign-in) inside a `<div class="space-y-5">`. No structural change to the sections themselves.
- `with_aside` → "Account safety" PageSection with three short bulleted tips: *"Use a unique password for this account."* / *"Turn 2FA on if you haven't already."* / *"Sign out on shared devices."* + a "Need to update your profile?" link card → Profile.

### C.2 `app/views/member/mfa/setup.html.erb`

Wrap in `Member::PageLayoutComponent`:
- `with_primary` → existing `PageHeaderComponent` + Step 1 (QR) and Step 2 (verify) sections. No structural change.
- `with_aside` → "Need help?" PageSection with copy: *"Lost your authenticator? After setup, you can use the recovery link from the sign-in page to disable 2FA via email."* + a small "Authenticator apps" list: Google Authenticator, Authy, 1Password, Microsoft Authenticator.

---

## Slice D — Specs (sequential after B + C)

Run the full member spec set:
- `bundle exec rspec spec/components/member` — adjust any newly-failing assertion under stale-test policy (the dashboard/profile/security view changes will not break component specs since the components themselves are unchanged; only the **views** call them differently).
- `bundle exec rspec spec/system/member spec/requests/member` — should be green; the view-level stitching is the only delta.
- `bundle exec rspec spec/services/member` — covered by A.2 spec changes.

If any assertion drifts due to the new `PageLayoutComponent` wrapper changing markup ordering, update the spec, do not revert production.

---

## Slice E — Release-engineer smoke

1. `rm -f public/assets/.manifest.json && bundle exec rails tailwindcss:build`.
2. Boot dev server with the temporary member-aware `SKIP_AUTH=1` initializer (revert before commit).
3. Curl all five member URLs + verify top-nav HTML contains only "Home" + module surfaces (no Profile / Security text in the rendered nav).
4. Revert the SKIP_AUTH initializer.

---

## Slice F — Tech-lead + code-review

Two parallel diff-only audits:
- `anysys-tech-lead` — AGENTS.md conventions (ViewComponent purity, Tailwind/Stimulus only, four URL areas unchanged, multi-tenancy unaffected).
- `anysys-code-reviewer` — XSS/scoping/auth-guard/N+1; new public surface (`PageLayoutComponent` slots) has spec coverage.

---

## Parallelization map

```
A (foundation)
   ↓
B (Home + Profile)   ║   C (Security + MFA)
   ↓                     ↓
D (specs sweep)
   ↓
E (smoke)
   ↓
F (audits, parallel)
```

**READY FOR EXECUTION.**
