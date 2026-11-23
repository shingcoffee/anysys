# Member Page Template — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every member page render its content at exactly the same width as the member home page by funnelling every view through one unified `Member::PageLayoutComponent` and pinning its grid to a fixed 8/4 primary/aside split (with a placeholder when aside is empty).

**Architecture:** Single mandatory ViewComponent (`Member::PageLayoutComponent`) with slots `with_hero` (optional, full-bleed), `with_primary` (required, always `lg:col-span-8`), `with_aside` (optional). When `with_aside` is not provided, an invisible `hidden lg:block lg:col-span-4` placeholder reserves the column so primary width never changes. Two outlier views (`surfaces/index`, `surfaces/show`) are reflowed onto the template. A template-compliance spec walks the member view tree and asserts every routed view uses the template.

**Tech Stack:** Rails 8.1, ViewComponent, TailwindCSS, RSpec, Capybara matchers.

**Spec:** `docs/superpowers/specs/2026-05-27-member-page-template-design.md`

**Branch:** `worktree-refactor-member-page-ui`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `app/components/member/page_layout_component.rb` | Modify | Drop the `primary_span_class` helper — primary is always 8. |
| `app/components/member/page_layout_component.html.erb` | Modify | Always `lg:col-span-8` primary; always-reserved aside slot (placeholder when no content). |
| `app/views/member/surfaces/index.html.erb` | Modify | Wrap inner `SurfaceIndexComponent` in `PageLayoutComponent`. |
| `app/views/member/surfaces/show.html.erb` | Modify | Wrap inner `SurfaceDetailComponent` in `PageLayoutComponent`. |
| `spec/components/member/page_layout_component_spec.rb` | Modify | Replace the "expands to col-span-12" assertion with always-8 + placeholder-present assertions. |
| `spec/views/member/template_compliance_spec.rb` | Create | Walk non-partial member views; assert each references `Member::PageLayoutComponent`. |

No model, migration, controller, route, or JS changes. Tailwind classes only.

---

## UX Pre-Step (parallel with Task 1)

**Owner:** anysys-ux-designer (via frontend-design plugin)

- [ ] **Step 1: Mock the unified layout at three breakpoints**

Produce mockups (`docs/superpowers/specs/2026-05-27-member-page-template-mockups.md` or images committed to `docs/superpowers/specs/assets/`) showing:
  - `lg`+ (≥1024px): hero (full) + primary (8 cols) + aside (4 cols) AND primary (8 cols) + empty-placeholder aside (4 cols).
  - `md` (768–1023px): stacked single column. Hero → primary → aside (when present); placeholder hidden.
  - `sm` (<768px): same stacked behaviour with tighter padding.

- [ ] **Step 2: Commit mockups**

```bash
git add docs/superpowers/specs/2026-05-27-member-page-template-mockups.md
git commit -m "docs(member-ui): mockups for unified page template (8/4 grid)"
```

This step does not block the code tasks below — they can proceed in parallel.

---

## Task 1: Template Compliance Spec (red)

**Owner:** anysys-qa-engineer

**Files:**
- Create: `spec/views/member/template_compliance_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member views template compliance" do
  views_root = Rails.root.join("app/views/member")

  # Non-partial .html.erb files (skip filenames starting with _).
  view_files = Dir.glob(views_root.join("**/*.html.erb")).reject do |path|
    File.basename(path).start_with?("_")
  end

  it "discovers at least one member view" do
    expect(view_files).not_to be_empty
  end

  view_files.each do |path|
    rel = Pathname.new(path).relative_path_from(Rails.root).to_s

    it "#{rel} renders through Member::PageLayoutComponent" do
      contents = File.read(path)
      expect(contents).to include("Member::PageLayoutComponent"),
        "Expected #{rel} to render through Member::PageLayoutComponent (unified page template). " \
        "Found content:\n#{contents[0, 300]}"
    end
  end
end
```

- [ ] **Step 2: Run the spec, confirm two failures**

Run: `bundle exec rspec spec/views/member/template_compliance_spec.rb`

Expected: 2 failures — `app/views/member/surfaces/index.html.erb` and `app/views/member/surfaces/show.html.erb` do not reference `Member::PageLayoutComponent`.

- [ ] **Step 3: Commit**

```bash
git add spec/views/member/template_compliance_spec.rb
git commit -m "test(member-ui): add template compliance spec (failing for surfaces)"
```

---

## Task 2: Wrap `surfaces/index` in PageLayoutComponent

**Owner:** anysys-frontend-developer

**Files:**
- Modify: `app/views/member/surfaces/index.html.erb`

- [ ] **Step 1: Replace file contents**

Current:

```erb
<% content_for :title, "#{@surface.label} — Anysys" %>
<% content_for :member_nav, @surface.key %>

<%= render Member::SurfaceIndexComponent.new(
      surface:   @surface,
      records:   @records,
      page_meta: @page_meta,
      customer:  current_customer
    ) %>
```

Replace with:

```erb
<% content_for :title, "#{@surface.label} — Anysys" %>
<% content_for :member_nav, @surface.key %>

<%= render Member::PageLayoutComponent.new do |c| %>
  <% c.with_primary do %>
    <%= render Member::SurfaceIndexComponent.new(
          surface:   @surface,
          records:   @records,
          page_meta: @page_meta,
          customer:  current_customer
        ) %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Run compliance spec for this file**

Run: `bundle exec rspec spec/views/member/template_compliance_spec.rb -e "surfaces/index"`

Expected: PASS.

- [ ] **Step 3: Run the surface index component spec (regression check)**

Run: `bundle exec rspec spec/components/member/surface_index_component_spec.rb`

Expected: PASS (component internals unchanged).

- [ ] **Step 4: Commit**

```bash
git add app/views/member/surfaces/index.html.erb
git commit -m "refactor(member-ui): route surfaces/index through page template"
```

---

## Task 3: Wrap `surfaces/show` in PageLayoutComponent

**Owner:** anysys-frontend-developer

**Files:**
- Modify: `app/views/member/surfaces/show.html.erb`

- [ ] **Step 1: Replace file contents**

Current:

```erb
<% content_for :title, "#{@surface.label} — Anysys" %>
<% content_for :member_nav, @surface.key %>

<%= render Member::SurfaceDetailComponent.new(
      surface:  @surface,
      record:   @record,
      customer: current_customer
    ) %>
```

Replace with:

```erb
<% content_for :title, "#{@surface.label} — Anysys" %>
<% content_for :member_nav, @surface.key %>

<%= render Member::PageLayoutComponent.new do |c| %>
  <% c.with_primary do %>
    <%= render Member::SurfaceDetailComponent.new(
          surface:  @surface,
          record:   @record,
          customer: current_customer
        ) %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Run the full compliance spec**

Run: `bundle exec rspec spec/views/member/template_compliance_spec.rb`

Expected: all examples PASS (every member view now references the template).

- [ ] **Step 3: Run the surface detail component spec (regression check)**

Run: `bundle exec rspec spec/components/member/surface_detail_component_spec.rb`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/views/member/surfaces/show.html.erb
git commit -m "refactor(member-ui): route surfaces/show through page template"
```

---

## Task 4: Update PageLayoutComponent Spec for New Contract (red)

**Owner:** anysys-qa-engineer

**Files:**
- Modify: `spec/components/member/page_layout_component_spec.rb`

- [ ] **Step 1: Replace file contents**

Replace the entire current file with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageLayoutComponent, type: :component do
  it "renders the primary slot inside the layout wrapper" do
    render_inline(described_class.new) do |c|
      c.with_primary { "primary content" }
    end

    expect(page).to have_text("primary content")
    expect(page).to have_css("[data-component='member-page-layout']")
  end

  it "keeps primary at lg:col-span-8 even when aside is omitted" do
    render_inline(described_class.new) do |c|
      c.with_primary { "primary" }
    end

    expect(page).to have_css(".lg\\:col-span-8", text: "primary")
    expect(page).not_to have_css(".lg\\:col-span-12", text: "primary")
  end

  it "renders an invisible aside placeholder when no aside slot is given" do
    render_inline(described_class.new) do |c|
      c.with_primary { "primary" }
    end

    placeholder = page.find("div.hidden.lg\\:block.lg\\:col-span-4", visible: :all)
    expect(placeholder["aria-hidden"]).to eq("true")
    expect(placeholder.text).to eq("")
    expect(page).not_to have_css("aside")
  end

  it "renders the hero slot before the grid when given" do
    render_inline(described_class.new) do |c|
      c.with_hero { '<div data-test="hero-content">hero</div>'.html_safe }
      c.with_primary { "primary" }
    end

    hero_index    = page.native.to_s.index("hero-content")
    primary_index = page.native.to_s.index("primary")
    expect(hero_index).to be < primary_index
  end

  it "renders the aside slot inside an <aside> with lg:col-span-4 when given" do
    render_inline(described_class.new) do |c|
      c.with_primary { "primary" }
      c.with_aside { "aside content" }
    end

    expect(page).to have_css("aside.lg\\:col-span-4", text: "aside content")
    expect(page).not_to have_css("div.hidden.lg\\:block.lg\\:col-span-4", visible: :all)
  end

  it "keeps primary at lg:col-span-8 when aside is given" do
    render_inline(described_class.new) do |c|
      c.with_primary { "primary" }
      c.with_aside { "aside" }
    end

    expect(page).to have_css(".lg\\:col-span-8", text: "primary")
  end

  it "uses a responsive grid: grid-cols-1 below lg, lg:grid-cols-12 above" do
    render_inline(described_class.new) do |c|
      c.with_primary { "primary" }
    end

    expect(page).to have_css(".grid.grid-cols-1.lg\\:grid-cols-12")
  end
end
```

- [ ] **Step 2: Run the spec, confirm failures**

Run: `bundle exec rspec spec/components/member/page_layout_component_spec.rb`

Expected: at least two failures — "keeps primary at lg:col-span-8 even when aside is omitted" and "renders an invisible aside placeholder when no aside slot is given" — because the current template uses `lg:col-span-12` when aside is absent and does not render a placeholder.

- [ ] **Step 3: Commit**

```bash
git add spec/components/member/page_layout_component_spec.rb
git commit -m "test(member-ui): pin page template to fixed 8/4 grid + aside placeholder"
```

---

## Task 5: Implement Always-8 Primary + Reserved Aside Placeholder (green)

**Owner:** anysys-frontend-developer

**Files:**
- Modify: `app/components/member/page_layout_component.rb`
- Modify: `app/components/member/page_layout_component.html.erb`

- [ ] **Step 1: Drop the `primary_span_class` helper**

Replace `app/components/member/page_layout_component.rb` with:

```ruby
# frozen_string_literal: true

module Member
  # The unified member page template. Every member-facing
  # view must render through this component so that content width
  # is identical across the member surface area. Primary is
  # always lg:col-span-8; the aside column is always reserved
  # (filled or with an invisible placeholder) so single-word pages
  # render at exactly the same width as the home page.
  class PageLayoutComponent < ApplicationComponent
    renders_one :hero
    renders_one :primary
    renders_one :aside
  end
end
```

- [ ] **Step 2: Update the template to always-8 primary + placeholder aside**

Replace `app/components/member/page_layout_component.html.erb` with:

```erb
<div data-component="member-page-layout" class="space-y-8">
  <% if hero? %>
    <%= hero %>
  <% end %>

  <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
    <div class="lg:col-span-8 space-y-6 min-w-0"><%= primary %></div>

    <% if aside? %>
      <aside class="lg:col-span-4 space-y-5 min-w-0"><%= aside %></aside>
    <% else %>
      <div class="hidden lg:block lg:col-span-4" aria-hidden="true"></div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Run the component spec**

Run: `bundle exec rspec spec/components/member/page_layout_component_spec.rb`

Expected: all examples PASS.

- [ ] **Step 4: Run the full member component spec suite for regressions**

Run: `bundle exec rspec spec/components/member`

Expected: all examples PASS. (No other component depends on `primary_span_class`.)

- [ ] **Step 5: Run the template compliance spec**

Run: `bundle exec rspec spec/views/member/template_compliance_spec.rb`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/components/member/page_layout_component.rb \
        app/components/member/page_layout_component.html.erb
git commit -m "feat(member-ui): pin primary to col-span-8 + reserve aside slot

Every member page now renders at the home page's content width.
Primary column stays at lg:col-span-8 regardless of aside presence;
an invisible lg:col-span-4 placeholder reserves the right column
when no aside content is provided, so single-word pages match home."
```

---

## Task 6: Smoke Test (release engineer)

**Owner:** anysys-release-engineer

- [ ] **Step 1: Run the full RSpec touch-scope**

Run:
```bash
bundle exec rspec \
  spec/components/member/page_layout_component_spec.rb \
  spec/components/member/surface_index_component_spec.rb \
  spec/components/member/surface_detail_component_spec.rb \
  spec/views/member/template_compliance_spec.rb
```

Expected: 0 failures.

- [ ] **Step 2: Rebuild assets + start dev server with SKIP_AUTH**

Run:
```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

Wait for "Listening on tcp://0.0.0.0:3000".

- [ ] **Step 3: Smoke-hit member pages**

Pick a customer id (e.g. `81721200` — the platform owner customer) and curl:

```bash
for path in \
  "/81721200/member" \
  "/81721200/member/profile" \
  "/81721200/member/profile/edit" \
  "/81721200/member/security"; do
  echo "== $path =="
  curl -s -o /tmp/page.html -w "%{http_code}\n" "http://localhost:3000$path"
  grep -c 'data-component="member-page-layout"' /tmp/page.html || echo "0"
  grep -c 'lg:col-span-8' /tmp/page.html || echo "0"
done
```

Expected for each path: status 200, at least one occurrence of `data-component="member-page-layout"`, at least one occurrence of `lg:col-span-8`.

- [ ] **Step 4: Report PASS/FAIL and shut down dev server**

```bash
kill %1 2>/dev/null
```

---

## Task 7: Tech Lead + Code Review

**Owner:** anysys-tech-lead + anysys-code-reviewer (parallel)

- [ ] **Step 1: Tech-lead diff audit**

Dispatch anysys-tech-lead with prompt:
> "Diff-only review against AGENTS.md conventions for the worktree-refactor-member-page-ui branch. Focus on: (1) ViewComponent purity (no inline custom CSS / JS), (2) Tailwind-only styling, (3) no admin/member URL added without auth guard (none expected — this is UI-only), (4) responsive Tailwind utilities used (the new lg:col-span-* + hidden lg:block placeholder must follow the project's mobile-first pattern)."

- [ ] **Step 2: Code-review correctness/security pass**

Dispatch anysys-code-reviewer with prompt:
> "Diff-only correctness review for the worktree-refactor-member-page-ui branch. Focus on: missing test cases (responsive behaviour, aside placeholder accessibility), XSS risk in the new template (none expected — only Tailwind classes added), and whether the empty-aside placeholder has correct ARIA semantics (aria-hidden=true, no focus target)."

- [ ] **Step 3: Address findings**

Apply any required changes inline; re-run Task 6 smoke and the relevant specs.

- [ ] **Step 4: Final commit (if any review findings addressed)**

```bash
git add <files>
git commit -m "fix(member-ui): address review feedback"
```

---

## Self-Review (run after all tasks)

- [ ] **Spec coverage:** Every section of the spec maps to a task:
  - Always-8 primary → Task 4 (spec) + Task 5 (impl)
  - Always-reserved aside placeholder → Task 4 (spec) + Task 5 (impl)
  - Surface outliers reflowed → Tasks 2 + 3
  - Enforcement (compliance spec) → Task 1
  - Responsive behaviour → Task 4 spec asserts `grid-cols-1 lg:grid-cols-12`; placeholder uses `hidden lg:block`
  - Smoke + review → Tasks 6 + 7
- [ ] **No placeholders:** No TBD / TODO / "similar to" patterns.
- [ ] **Naming consistency:** `Member::PageLayoutComponent`, slots `with_hero` / `with_primary` / `with_aside` used consistently across tasks.
