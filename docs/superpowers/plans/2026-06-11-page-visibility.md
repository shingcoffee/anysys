# Page-Level Visibility Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a page-level visibility setting (admin / member / public, independent toggles, default admin-only) enforced when serving the published page URL.

**Architecture:** Three boolean columns on `pages` (not in the versioned `configuration` blob). A Reform contract validates updates. A dedicated admin route + thin controller updates the toggles from a Visibility card on the page show view. `PublicPagesController` gates the form URL by audience, redirecting unauthorized anonymous visitors to sign-in and 404-ing signed-in users whose role isn't permitted.

**Tech Stack:** Rails 8, ViewComponent, Reform contract, Tailwind, RSpec.

---

## File Structure

- **Create** `db/migrate/<ts>_add_visibility_to_pages.rb` — three boolean columns.
- **Modify** `app/models/page.rb` — `VISIBILITY_AUDIENCES`, `visible_to?`, `visible_audiences`, at-least-one validation.
- **Create** `app/contracts/pages/visibility_contract.rb` — Reform contract.
- **Create** `app/controllers/admin/maintenance/page_visibilities_controller.rb` — `#update`.
- **Modify** `config/routes.rb` — `resource :visibility, only: :update` nested under `pages`.
- **Modify** `app/controllers/public_pages_controller.rb` — audience enforcement in `find_published_page`.
- **Create** `app/components/pages/visibility_card_component.rb` + `.html.erb` — the card UI.
- **Modify** `app/views/admin/maintenance/pages/show.html.erb` — render the card under Publishing.
- **Test** model / contract / request (public + visibilities) / component specs.

> Roles available on `current_user`: `admin?`, `owner?`, `member?`, `admin_or_owner?`, `platform_owner?`, `customer_id`. The visibilities route lives under `/:cid/admin/...` so `RouteAuthorization` auto-gates it to admin/owner — no per-controller auth filter.

---

## Task 1: Migration — visibility columns

**Files:**
- Create: `db/migrate/<ts>_add_visibility_to_pages.rb`

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class AddVisibilityToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :visible_to_admin,       :boolean, default: true,  null: false
    add_column :pages, :visible_to_member, :boolean, default: false, null: false
    add_column :pages, :visible_to_public,      :boolean, default: false, null: false
  end
end
```

- [ ] **Step 2: Run it**

Run: `bin/rails db:migrate`
Expected: `pages` gains the three columns; `db/schema.rb` updated.

- [ ] **Step 3: Commit** (skip on master — leave staged per repo policy)

---

## Task 2: Page model — visibility helpers + validation

**Files:**
- Modify: `app/models/page.rb`
- Test: `spec/models/page_spec.rb`

- [ ] **Step 1: Write failing model specs**

```ruby
describe "visibility" do
  it "defaults to admin only" do
    page = build(:page)
    expect(page.visible_to_admin).to be(true)
    expect(page.visible_to_member).to be(false)
    expect(page.visible_to_public).to be(false)
  end

  it "reports enabled audiences" do
    page = build(:page, visible_to_admin: true, visible_to_public: true, visible_to_member: false)
    expect(page.visible_to?(:admin)).to be(true)
    expect(page.visible_to?("public")).to be(true)
    expect(page.visible_to?(:member)).to be(false)
    expect(page.visible_audiences).to contain_exactly("admin", "public")
  end

  it "is invalid when no audience is enabled" do
    page = build(:page, visible_to_admin: false, visible_to_member: false, visible_to_public: false)
    expect(page).not_to be_valid
    expect(page.errors[:base].join).to match(/at least one audience/i)
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/models/page_spec.rb -e visibility`
Expected: FAIL (`visible_to?` undefined / validation absent).

- [ ] **Step 3: Implement in `app/models/page.rb`**

Add near the top (after includes):

```ruby
  VISIBILITY_AUDIENCES = %w[admin member public].freeze
```

Add a validation (with the other `validate` lines):

```ruby
  validate :at_least_one_visibility_audience
```

Add public methods:

```ruby
  def visible_to?(audience)
    return false unless VISIBILITY_AUDIENCES.include?(audience.to_s)
    public_send("visible_to_#{audience}")
  end

  def visible_audiences
    VISIBILITY_AUDIENCES.select { |a| public_send("visible_to_#{a}") }
  end
```

Add the validation helper (in the private section):

```ruby
  def at_least_one_visibility_audience
    return if visible_to_admin || visible_to_member || visible_to_public
    errors.add(:base, "must be visible to at least one audience")
  end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/models/page_spec.rb -e visibility`
Expected: PASS.

---

## Task 3: Reform contract — `Pages::VisibilityContract`

**Files:**
- Create: `app/contracts/pages/visibility_contract.rb`
- Test: `spec/contracts/pages/visibility_contract_spec.rb`

- [ ] **Step 1: Write failing contract spec**

```ruby
require "rails_helper"

RSpec.describe Pages::VisibilityContract do
  let(:page) { build(:page) }

  it "accepts at least one enabled audience" do
    contract = described_class.new(page)
    expect(contract.validate("visible_to_admin" => "1", "visible_to_member" => "0", "visible_to_public" => "0")).to be(true)
  end

  it "rejects when all audiences disabled" do
    contract = described_class.new(page)
    expect(contract.validate("visible_to_admin" => "0", "visible_to_member" => "0", "visible_to_public" => "0")).to be(false)
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/contracts/pages/visibility_contract_spec.rb`
Expected: FAIL (class missing).

- [ ] **Step 3: Implement contract**

```ruby
# frozen_string_literal: true

module Pages
  class VisibilityContract < Reform::Form
    property :visible_to_admin
    property :visible_to_member
    property :visible_to_public

    %i[visible_to_admin visible_to_member visible_to_public].each do |attr|
      validates attr, inclusion: { in: [true, false] }
    end

    validate :at_least_one_audience

    def deserialize!(params)
      %w[visible_to_admin visible_to_member visible_to_public].each do |k|
        params[k] = ActiveModel::Type::Boolean.new.cast(params[k]) if params.key?(k)
      end
      super
    end

    private

    def at_least_one_audience
      return if visible_to_admin || visible_to_member || visible_to_public
      errors.add(:base, "must be visible to at least one audience")
    end
  end
end
```

> Match the existing contract base/idiom in `app/contracts/` (e.g. `FeatureModuleHandoffContract`). If contracts there don't subclass `Reform::Form` or use a custom boolean-coercion helper, follow that local convention instead of the snippet above.

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/contracts/pages/visibility_contract_spec.rb`
Expected: PASS.

---

## Task 4: Route + `PageVisibilitiesController`

**Files:**
- Modify: `config/routes.rb` (under `resources :pages, controller: "maintenance/pages" do`)
- Create: `app/controllers/admin/maintenance/page_visibilities_controller.rb`
- Test: `spec/requests/maintenance/page_visibilities_spec.rb`

- [ ] **Step 1: Add the route**

Inside the `resources :pages ... do` block, next to `resource :restoration`:

```ruby
          resource :visibility, only: :update, controller: "maintenance/page_visibilities"
```

- [ ] **Step 2: Write failing request spec**

```ruby
require "rails_helper"

RSpec.describe "Admin::Maintenance::PageVisibilities", type: :request do
  let(:customer_id) { 12_345_678 }
  let(:admin)   { create(:user, :admin, customer_id: customer_id) }
  let(:page_rec) { create(:page, customer_id: customer_id) }

  def patch_visibility(params)
    patch "/#{customer_id}/admin/maintenance/pages/#{page_rec.id}/visibility",
          params: { page: params }
  end

  context "as admin" do
    before { sign_in admin } # use the suite's auth helper

    it "updates audiences" do
      patch_visibility(visible_to_admin: "1", visible_to_member: "1", visible_to_public: "0")
      expect(page_rec.reload.visible_audiences).to contain_exactly("admin", "member")
    end

    it "rejects all-off and keeps prior state" do
      patch_visibility(visible_to_admin: "0", visible_to_member: "0", visible_to_public: "0")
      expect(page_rec.reload.visible_to_admin).to be(true)
    end
  end

  it "forbids a member (admin route guard)" do
    member = create(:user, :member, customer_id: customer_id)
    sign_in member
    patch_visibility(visible_to_public: "1")
    expect(response).to have_http_status(:forbidden).or have_http_status(:found)
  end
end
```

> Use the project's real auth/sign-in test helper and factory traits — inspect `spec/requests/maintenance/pages_spec.rb` for the established pattern (likely `SKIP_AUTH` or a `login_as`/session helper) and mirror it exactly.

- [ ] **Step 3: Run, expect fail**

Run: `bundle exec rspec spec/requests/maintenance/page_visibilities_spec.rb`
Expected: FAIL (controller missing → routing/load error).

- [ ] **Step 4: Implement controller**

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class PageVisibilitiesController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_page

      def update
        contract = Pages::VisibilityContract.new(@page)
        if contract.validate(visibility_params)
          contract.save
          redirect_to admin_maintenance_page_path(current_customer_id, @page),
                      notice: "Visibility updated."
        else
          redirect_to admin_maintenance_page_path(current_customer_id, @page),
                      alert: "Couldn't update visibility: #{contract.errors.full_messages.join('; ')}"
        end
      end

      private

      def find_page
        @page = Page.for_current_customer.find(params[:page_id])
      end

      def visibility_params
        params.require(:page).permit(:visible_to_admin, :visible_to_member, :visible_to_public).to_h
      end
    end
  end
end
```

- [ ] **Step 5: Run, expect pass**

Run: `bundle exec rspec spec/requests/maintenance/page_visibilities_spec.rb`
Expected: PASS.

---

## Task 5: Enforcement in `PublicPagesController`

**Files:**
- Modify: `app/controllers/public_pages_controller.rb`
- Test: `spec/requests/public_pages_visibility_spec.rb`

- [ ] **Step 1: Write failing request spec (enforcement matrix)**

```ruby
require "rails_helper"

RSpec.describe "Public page visibility", type: :request do
  let(:customer_id) { 12_345_678 }
  let(:page_rec)    { create(:page, :published, customer_id: customer_id) }
  let(:url)         { "/#{customer_id}/forms/#{page_rec.public_token}" }

  context "public page" do
    before { page_rec.update!(visible_to_public: true) }
    it "renders for anonymous" do
      get url
      expect(response).to have_http_status(:ok)
    end
  end

  context "admin-only page (default)" do
    it "redirects anonymous to sign-in" do
      get url
      expect(response).to redirect_to("/#{customer_id}/auth/sign_in")
    end

    it "404s a signed-in member" do
      sign_in create(:user, :member, customer_id: customer_id)
      get url
      expect(response).to have_http_status(:not_found)
    end

    it "renders for a signed-in admin of the customer" do
      sign_in create(:user, :admin, customer_id: customer_id)
      get url
      expect(response).to have_http_status(:ok)
    end
  end

  context "member-only page" do
    before { page_rec.update!(visible_to_admin: false, visible_to_member: true) }

    it "renders for a member of the customer" do
      sign_in create(:user, :member, customer_id: customer_id)
      get url
      expect(response).to have_http_status(:ok)
    end

    it "404s a member of a different customer" do
      sign_in create(:user, :member, customer_id: 87_654_321)
      get url
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

> Mirror the existing `spec/requests/public_pages_submission_spec.rb` setup for factories, the `:published` trait, and the sign-in helper.

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/requests/public_pages_visibility_spec.rb`
Expected: FAIL (no gate today — anonymous gets 200).

- [ ] **Step 3: Implement enforcement**

Replace `find_published_page` and add helpers:

```ruby
  def find_published_page
    @page = Page.for_current_customer.published.find_by(public_token: params[:token])
    return render_page_not_found unless @page
    return if page_visible_to_current_viewer?(@page)

    if user_signed_in?
      render_page_not_found
    else
      store_location_for(:user, request.fullpath) if respond_to?(:store_location_for)
      session[:return_to] = request.fullpath
      redirect_to new_user_session_path(customer_id: params[:customer_id])
    end
  end

  def page_visible_to_current_viewer?(page)
    return true if page.visible_to_public
    return false unless user_signed_in?
    return false unless current_user.customer_id == current_customer_id || current_user.platform_owner?
    return true if page.visible_to_admin && current_user.admin_or_owner?
    return true if page.visible_to_member && current_user.member?
    false
  end

  def render_page_not_found
    render plain: "Page not found", status: :not_found
  end
```

> Verify the sign-in path helper name against `bin/rails routes` (`new_user_session_path` with `customer_id:`). Use the suite's actual `user_signed_in?`/`current_user` helpers (Devise-style, confirmed present via `RouteAuthorization`).

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/requests/public_pages_visibility_spec.rb`
Expected: PASS.

- [ ] **Step 5: Regression — existing public page specs still pass**

Run: `bundle exec rspec spec/requests/public_pages_submission_spec.rb spec/requests/public_pages_captcha_spec.rb`
Expected: PASS (update these specs to set `visible_to_public: true` on their pages if they now redirect/404 — this is the intended secure-by-default change, so fix the specs, not the production code).

---

## Task 6: `VisibilityCardComponent` + show view

**Files:**
- Create: `app/components/pages/visibility_card_component.rb`
- Create: `app/components/pages/visibility_card_component.html.erb`
- Modify: `app/views/admin/maintenance/pages/show.html.erb` (after the Publishing card, ~line 95)
- Test: `spec/components/pages/visibility_card_component_spec.rb`

- [ ] **Step 1: Write failing component spec**

```ruby
require "rails_helper"

RSpec.describe Pages::VisibilityCardComponent, type: :component do
  it "checks only the enabled audiences" do
    page = build_stubbed(:page, visible_to_admin: true, visible_to_member: false, visible_to_public: true)
    render_inline(described_class.new(page: page, customer_id: 12_345_678))
    expect(page_html_checkbox("visible_to_admin")).to be_checked
    expect(page_html_checkbox("visible_to_public")).to be_checked
    expect(page_html_checkbox("visible_to_member")).not_to be_checked
  end
end
```

> Use the assertion idiom from an existing component spec under `spec/components/pages/`; the helper names above are illustrative.

- [ ] **Step 2: Run, expect fail**

Run: `bundle exec rspec spec/components/pages/visibility_card_component_spec.rb`
Expected: FAIL (component missing).

- [ ] **Step 3: Implement component class**

```ruby
# frozen_string_literal: true

module Pages
  class VisibilityCardComponent < ViewComponent::Base
    AUDIENCES = [
      { key: "visible_to_admin",       label: "Admins",       hint: "Admins and owners of this customer" },
      { key: "visible_to_member", label: "Members", hint: "Signed-in members of this customer" },
      { key: "visible_to_public",      label: "Public",       hint: "Anyone with the link, including anonymous visitors" }
    ].freeze

    def initialize(page:, customer_id:)
      @page        = page
      @customer_id = customer_id
    end

    attr_reader :page, :customer_id

    def checked?(key) = page.public_send(key)
  end
end
```

- [ ] **Step 4: Implement template (Tailwind only, mirror the Publishing card)**

```erb
<div class="card overflow-hidden">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h3 class="section-header">Visibility</h3>
    <p class="text-body-sm text-text-muted mt-1">Who can open this page once published. Admins can always preview from this admin screen.</p>
  </div>
  <%= form_with url: admin_maintenance_page_visibility_path(customer_id, page), method: :patch, class: "px-6 py-5 space-y-4" do |f| %>
    <% Pages::VisibilityCardComponent::AUDIENCES.each do |aud| %>
      <label class="flex items-start gap-3">
        <input type="hidden" name="page[<%= aud[:key] %>]" value="0">
        <input type="checkbox" name="page[<%= aud[:key] %>]" value="1"
               <%= "checked" if checked?(aud[:key]) %>
               class="mt-1 h-4 w-4 rounded border-border text-accent focus:ring-accent">
        <span>
          <span class="form-label block"><%= aud[:label] %></span>
          <span class="text-body-sm text-text-muted"><%= aud[:hint] %></span>
        </span>
      </label>
    <% end %>
    <div class="pt-2">
      <%= f.submit "Save visibility", class: "btn btn-primary" %>
    </div>
  <% end %>
</div>
```

> The hidden `value="0"` before each checkbox makes unchecked boxes submit `0` (Rails idiom). Match the actual card / button / label Tailwind class names used elsewhere in `show.html.erb`.

- [ ] **Step 5: Render the card in the show view**

In `app/views/admin/maintenance/pages/show.html.erb`, immediately after the Publishing card's closing `</div>` (around line 95, still inside `<div class="space-y-6">`):

```erb
  <%# Visibility Card %>
  <%= render Pages::VisibilityCardComponent.new(page: @page, customer_id: current_customer_id) %>
```

- [ ] **Step 6: Run component spec, expect pass**

Run: `bundle exec rspec spec/components/pages/visibility_card_component_spec.rb`
Expected: PASS.

---

## Task 7: Full targeted run + asset rebuild + smoke

- [ ] **Step 1: Run all touched specs**

Run:
```bash
bundle exec rspec \
  spec/models/page_spec.rb \
  spec/contracts/pages/visibility_contract_spec.rb \
  spec/requests/maintenance/page_visibilities_spec.rb \
  spec/requests/public_pages_visibility_spec.rb \
  spec/requests/public_pages_submission_spec.rb \
  spec/requests/public_pages_captcha_spec.rb \
  spec/components/pages/visibility_card_component_spec.rb
```
Expected: all PASS.

- [ ] **Step 2: Rebuild assets + restart dev server**

Run: `rm -f public/assets/.manifest.json && bin/rails assets:precompile && (SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &)`

- [ ] **Step 3: Smoke test**

Visit `/81721200/admin/maintenance/pages/43` — confirm the Visibility card renders with Admin checked by default; toggle Public + Save; open the form URL anonymously and confirm it renders; uncheck Public, re-save, confirm anonymous now redirects to sign-in.

---

## Self-Review notes

- **Spec coverage:** data model (T1/T2), at-least-one validation (T2/T3), enforcement matrix incl. cross-tenant (T5), update auth via admin route guard (T4), UI card (T6). All spec sections mapped.
- **No-commit-on-master:** repo policy — leave changes staged, do not `git commit`.
- **Stale-test policy:** if `public_pages_submission_spec`/`captcha_spec` break because pages now default to admin-only, update those specs to set `visible_to_public: true` (T5 Step 5) — do not weaken production enforcement.
