# Audience Render Links Implementation Plan

> **For agentic workers:** Executed via the anysys-* SDLC agents (parallel build → QA → release → review), per project AGENTS.md. Steps use checkbox (`- [ ]`) syntax for tracking. No commits during build (master branch; user commits manually).

**Goal:** Replace the "Generated Template" card on the admin page detail view with a "Rendered Views" card linking to the page as rendered for admin, member, and public audiences, adding the two missing rendered-view routes.

**Architecture:** Two new thin controllers (admin + member) share a `PageRendering` concern that resolves `@form_action`/`@content` the same way `PublicPagesController` does; each renders the page's generated ERB inline under its audience layout (`dashboard` / `member`). The public audience reuses `/:cid/forms/:token`. A new `Pages::AudienceLinksCardComponent` renders the three link rows with published/visibility gating.

**Tech Stack:** Rails 8.1, ViewComponent, Tailwind, RSpec. No Stimulus needed (server-rendered links only). No migrations.

**Specs:** Design `docs/superpowers/specs/2026-06-11-audience-render-links-design.md`; UX `docs/superpowers/specs/2026-06-11-audience-render-links-ux.md`.

---

## Task 1: Routes + controllers + shared concern (anysys-security-engineer)

**Files:**
- Modify: `config/routes.rb` (admin pages block ~line 233; member namespace ~line 389)
- Create: `app/controllers/concerns/page_rendering.rb`
- Create: `app/controllers/admin/maintenance/page_renders_controller.rb`
- Create: `app/controllers/member/pages_controller.rb`

- [ ] **Step 1.1: Admin route.** Inside the existing `resources :pages, controller: "maintenance/pages" do ... end` block (next to `resource :preview`), add:

```ruby
resource :render, only: :show, controller: "maintenance/page_renders"
```

Helper: `admin_maintenance_page_render_path(cid, page)` → `GET /:cid/admin/maintenance/pages/:page_id/render`.

- [ ] **Step 1.2: Member route.** In `namespace :member`, add **BEFORE** `resources :surfaces` (whose `path: ":key"` is a catch-all that would otherwise swallow `/member/pages/:id`):

```ruby
resources :pages, only: :show
```

Helper: `member_page_path(cid, page)` → `GET /:cid/member/pages/:id`.

- [ ] **Step 1.3: Shared concern** `app/controllers/concerns/page_rendering.rb`:

```ruby
# frozen_string_literal: true

# Prepares @form_action and @content for rendering a built page's generated
# ERB under an audience-specific layout. Mirrors PublicPagesController's
# resolution so all three audience surfaces submit to the same endpoints.
module PageRendering
  extend ActiveSupport::Concern

  private

  def prepare_page_render(page)
    @form_action = resolve_page_form_action(page) ||
                   public_page_submit_path(customer_id: params[:customer_id], token: page.public_token)
    @content = page.generate_content
  end

  def resolve_page_form_action(page)
    flowchart_id = page.configuration_json&.dig("form_settings", "flowchart_id")
    return nil unless flowchart_id

    flowchart = Flowchart.accessible.find_by(id: flowchart_id)
    return nil unless flowchart&.uuid && flowchart&.entity&.name_slug

    "/#{params[:customer_id]}/#{flowchart.uuid}/#{flowchart.entity.name_slug}"
  end
end
```

- [ ] **Step 1.4: Admin controller** `app/controllers/admin/maintenance/page_renders_controller.rb`. Gets `dashboard` layout automatically via `ApplicationController#dashboard_layout`; admin/owner gate comes from `RouteAuthorization` on `/:cid/admin/*`. Re-checks published + visibility at request time (stale links → 404):

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    # Renders a built page exactly as the admin audience sees it
    # (dashboard layout). Linked from the page detail "Rendered Views" card.
    class PageRendersController < ApplicationController
      include PageRendering

      dashboard_menu_item :maintenance

      def show
        @page = Page.for_current_customer.find(params[:page_id])
        raise ActiveRecord::RecordNotFound unless @page.published? && @page.visible_to?(:admin)

        prepare_page_render(@page)
      end
    end
  end
end
```

- [ ] **Step 1.5: Member controller** `app/controllers/member/pages_controller.rb`. Member role gate via `RouteAuthorization` on `/:cid/member/*`; `member` layout via `Member::BaseController`:

```ruby
# frozen_string_literal: true

module Member
  # Renders a built page exactly as the member audience sees it
  # (member layout). Pages are tenant records, not member-owned, so the
  # gate is tenant scope + published + member visibility (no user_id check).
  class PagesController < BaseController
    include PageRendering

    def show
      @page = Page.for_current_customer.published.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @page.visible_to?(:member)

      prepare_page_render(@page)
    end
  end
end
```

- [ ] **Step 1.6: Verify routes resolve.** Run: `bin/rails runner 'puts Rails.application.routes.url_helpers.admin_maintenance_page_render_path(12345678, 1); puts Rails.application.routes.url_helpers.member_page_path(12345678, 1)'`
Expected: `/12345678/admin/maintenance/pages/1/render` and `/12345678/member/pages/1`. Also confirm `bin/rails routes -g "member/pages"` shows the pages route ABOVE the surfaces catch-all.

Do NOT create the two `show.html.erb` views (frontend task). Do NOT modify `PublicPagesController` or the existing preview controller.

---

## Task 2: Component + views + show-page swap (anysys-frontend-developer)

**Files:**
- Create: `app/components/pages/audience_links_card_component.rb`
- Create: `app/components/pages/audience_links_card_component.html.erb`
- Create: `app/views/admin/maintenance/page_renders/show.html.erb`
- Create: `app/views/member/pages/show.html.erb`
- Modify: `app/views/admin/maintenance/pages/show.html.erb` (delete lines 153–176 "Generated Content Card"; insert component render after line 98 Visibility card)
- Create: `spec/components/pages/audience_links_card_component_spec.rb`

Follow the UX spec `docs/superpowers/specs/2026-06-11-audience-render-links-ux.md` exactly (card shell, row structure, dot colors `bg-accent`/`bg-member-accent`/`bg-success`, `btn btn-ghost` Open link with arrow-top-right-on-square SVG, disabled muted span with x-circle/eye-slash icons, member caption with information-circle icon, responsive `flex-col gap-3 sm:flex-row` pivot).

- [ ] **Step 2.1: Component class** `app/components/pages/audience_links_card_component.rb`:

```ruby
# frozen_string_literal: true

module Pages
  # "Rendered Views" card on the admin page detail view: one row per
  # audience (admin / member / public) linking to the page as rendered
  # under that audience's themed layout. A row is enabled only when the
  # page is published AND visible to that audience.
  class AudienceLinksCardComponent < ViewComponent::Base
    Row = Struct.new(:key, :label, :description, :url, keyword_init: true)

    def initialize(page:, customer_id:)
      @page        = page
      @customer_id = customer_id
    end

    def rows
      [
        Row.new(key: "admin",  label: "Admin",  description: "Dashboard layout — admin chrome with sidebar navigation.",
                url: helpers.admin_maintenance_page_render_path(customer_id, page)),
        Row.new(key: "member", label: "Member", description: "Member layout — member portal.",
                url: helpers.member_page_path(customer_id, page)),
        Row.new(key: "public", label: "Public", description: "Public form page — anyone with the link, no sign-in required.",
                url: public_url)
      ]
    end

    def enabled?(key)
      page.published? && page.visible_to?(key)
    end

    # "Not published" takes precedence over visibility.
    def disabled_reason(key)
      return "Not published" unless page.published?

      "Not visible to #{key.capitalize}" unless page.visible_to?(key)
    end

    def dot_class(key)
      { "admin" => "bg-accent", "member" => "bg-member-accent", "public" => "bg-success" }.fetch(key)
    end

    private

    attr_reader :page, :customer_id

    def public_url
      return "#" unless page.public_token

      helpers.public_page_url(customer_id: customer_id, token: page.public_token)
    end
  end
end
```

- [ ] **Step 2.2: Component template** per the UX spec mockup: `.card.overflow-hidden` shell, header (`section-header` "Rendered Views" + subtitle "Open the page as each audience experiences it."), `divide-y divide-border-subtle` rows wrapper; each row `px-6 py-4` with the dot + label + description on the left, member caption ("Requires an active member session to open.") on the member row, and on the right either the `btn btn-ghost` Open link (`target="_blank" rel="noopener noreferrer"`) when `enabled?(row.key)` or the muted disabled span with `disabled_reason(row.key)` (x-circle icon for "Not published", eye-slash for "Not visible…"). Disabled state is a `<span>`, never an `<a>`.

- [ ] **Step 2.3: Swap into show view.** In `app/views/admin/maintenance/pages/show.html.erb`: delete the whole "Generated Content Card" block (lines 153–176, the card with `CodeBlockComponent`), and insert after the Visibility card (line 98):

```erb
<%# Rendered Views Card %>
<%= render Pages::AudienceLinksCardComponent.new(page: @page, customer_id: current_customer_id) %>
```

Do NOT delete `CodeBlockComponent` itself (used elsewhere). Keep the existing Preview button and Publishing card untouched.

- [ ] **Step 2.4: Render views.** Both mirror `app/views/admin/maintenance/pages/preview.html.erb`'s inline-render pattern.

`app/views/admin/maintenance/page_renders/show.html.erb`:

```erb
<%# Rendered view of a built page for the admin audience (dashboard layout). %>
<%= render BreadcrumbsComponent.new(crumbs: [
  { label: "Maintenance", path: admin_maintenance_path(current_customer_id) },
  { label: "Pages", path: admin_maintenance_pages_path(current_customer_id) },
  { label: @page.name, path: admin_maintenance_page_path(current_customer_id, @page) },
  { label: "Rendered View", path: nil }
]) %>

<div class="card overflow-x-auto">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h2 class="section-header"><%= @page.name %></h2>
    <% if @page.description.present? %>
      <p class="mt-1 text-body-sm"><%= @page.description %></p>
    <% end %>
  </div>
  <div class="p-6">
    <%= render inline: @content %>
  </div>
</div>
```

`app/views/member/pages/show.html.erb`:

```erb
<%# Rendered view of a built page for the member audience (member layout). %>
<div class="card overflow-x-auto">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h2 class="section-header"><%= @page.name %></h2>
    <% if @page.description.present? %>
      <p class="mt-1 text-body-sm"><%= @page.description %></p>
    <% end %>
  </div>
  <div class="p-6">
    <%= render inline: @content %>
  </div>
</div>
```

(Check the member layout/views for the canonical card classes used on member surfaces and match them if they differ.)

- [ ] **Step 2.5: Component spec** `spec/components/pages/audience_links_card_component_spec.rb` covering: all three rows render; enabled row renders an `<a>` with `target="_blank"` and `rel="noopener noreferrer"`; unpublished page → all rows disabled with "Not published" (no anchors to render paths); published but `visibility: {admin: true, member: false, public: false}` → member/public rows show "Not visible to Member"/"Not visible to Public" while admin row has a live link; member caption always present. Follow existing component spec conventions (see `spec/components/pages/`). Run: `bundle exec rspec spec/components/pages/audience_links_card_component_spec.rb` — expect PASS (requires Task 1's routes; if helpers are missing, coordinate, don't stub).

---

## Task 3: Request specs (anysys-qa-engineer)

**Files:**
- Create: `spec/requests/admin/maintenance/page_renders_spec.rb`
- Create: `spec/requests/member/pages_spec.rb`
- Check/Update: any existing spec asserting the "Generated Template" section (`grep -rn "Generated Template" spec/`)

Follow conventions in `spec/requests/public_pages_visibility_spec.rb` (factories: `create(:customer)`, `create(:user, :admin/:member, customer:)`, `create(:page, ...)` inside `Current.set(customer:)`, `ensure_platform_customer` / `find_or_create_platform_owner` helpers).

- [ ] **Step 3.1: Admin render route spec.** URL `/#{customer.id}/admin/maintenance/pages/#{page.id}/render`. Cases:
  - anonymous → redirect to `/#{customer.id}/auth/sign_in`
  - member of same customer → denied (CanCan redirect / not 200)
  - admin of same customer, page published + visible_to admin → 200, body includes generated content marker
  - admin, page unpublished → 404
  - admin, page published but `visibility: {"admin" => false, ...}` → 404
  - admin of ANOTHER customer hitting this customer's page id → tenant guard (redirect/403/404, follow cross_tenant pattern)
  - platform owner cross-tenant → 200
- [ ] **Step 3.2: Member render route spec.** URL `/#{customer.id}/member/pages/#{page.id}`. Cases:
  - anonymous → redirect to sign-in
  - admin of same customer → denied (member-only URL)
  - member of same customer, published + visible_to member → 200 with content
  - member, unpublished → 404
  - member, published but member visibility false → 404
  - member of another customer → tenant isolation (not 200 with content)
  - route precedence: `/member/pages/:id` resolves to `Member::PagesController`, not the surfaces catch-all (asserting 404/200 from pages controller behavior is sufficient)
- [ ] **Step 3.3:** Run: `bundle exec rspec spec/requests/admin/maintenance/page_renders_spec.rb spec/requests/member/pages_spec.rb` — expect PASS.

---

## Task 4: Release verification (anysys-release-engineer)

- [ ] Run scoped specs: the two new request specs, the component spec, plus `spec/requests/pages_spec.rb` and `spec/requests/member/` (regression on touched areas).
- [ ] `rm -f public/assets/.manifest.json`, rebuild assets, restart `SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`.
- [ ] Smoke: `GET /81721200/admin/maintenance/pages/43` returns 200 and contains "Rendered Views" and NOT "Generated Template".

---

## Task 5: Parallel review

- [ ] anysys-tech-lead: diff-only convention review.
- [ ] anysys-code-reviewer: diff-only correctness/security review.
