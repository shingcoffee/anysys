# Member Pages Skeleton — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the member (member) section of the application — a beautiful, easy-to-use individual portal living at `/:cid/member/*`, plus a reskin of the auth surfaces that lead into it.

**Architecture:** Two parallel Rails-conventional shells under one monolith. Member gets its own controller namespace (`Member::*`) with a per-category base controller, its own layout (`layouts/member.html.erb`), its own ViewComponent shell (`Member::ShellComponent` — TopNav + main, no sidebar), its own teal accent palette in CSS tokens, and a navigation-as-data registry so future surfaces only need to register a nav item rather than edit the shell. Authorization is enforced at three layers: URL gate (`require_member!`), tenant gate (`enforce_tenant_match!`), and record gate (`authorize_owned!`). Auth views (sign-in / sign-up / password reset) live under `/:cid/auth/*` and are reskinned via a new `Member::AuthShellComponent` consumed by the existing `layouts/auth.html.erb`.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Devise (registerable, recoverable, lockable, trackable), TailwindCSS (via the existing `@theme` token system in `app/assets/tailwind/application.css`), StimulusJS, ViewComponent, Trailblazer Reform (for the profile-update contract), RSpec + FactoryBot + Capybara.

**Spec:** `docs/superpowers/specs/2026-05-15-member-skeleton-design.md`

**Phases (each independently mergeable):**

1. **Foundation** — tokens, base controller, layout, shell components, navigation registry, route block, authorization contract specs.
2. **Auth reskin** — `Member::AuthShellComponent`, reskinned sign-in/sign-up/password views, `member` role assignment + redirect-after-sign-up fix, system specs.
3. **Authenticated pages** — Home, Profile show/edit, Security, plus the Reform profile-update contract and supporting components (`HeroCardComponent`, `StatusCardComponent`).
4. **Payments** — `user_id` migration on `payments`, `Member::PaymentsController` index/show, module-disabled guard, system specs.

**Pre-flight context (read before starting):**

- `app/controllers/concerns/tenant_context.rb` auto-extracts `Current.customer` from the `/:cid/...` URL prefix on every request — no controller needs to opt in. The member base controller benefits from this for free.
- `app/controllers/application_controller.rb` runs `before_action :enforce_mfa!`, applies `layout :dashboard_layout` (which falls through to `"application"` when `Current.customer` is set in admin contexts but is overridden by `layout "member"` in our base controller below), and invokes the global RouteAuthorization concern. Member controllers inherit this baseline.
- `Authentication::User#member?` returns true only when an explicit `member` role row exists in `users_roles`. The user factory at `spec/factories/users.rb` deliberately leaves members without a row (`when :member then nil`). To avoid divergence between factory and production, this plan **does** create a `member` role row on sign-up (Phase 2, Task 2.6) and `require_member!` rejects on `current_user.admin_or_owner?` rather than `!member?` — so anonymous-pattern factory users (no role row) are still treated as members in tests.
- `Role` records are per-customer (`Role#customer_id`). Each customer must have its own `system: true, key: "member"` role row. `find_or_create_by!` patterns (used by the factory) already handle this idempotently.
- The `payments` table has **no `user_id` column today**. Phase 4, Task 4.1 adds it via migration.
- Stimulus controllers under `app/javascript/controllers/` use kebab-case filenames (e.g. `mobile_nav_controller.js`) registered automatically by `controllers/index.js`. The data-controller attribute uses dash form (`data-controller="mobile-nav"`).
- The existing `RegistrationsController#check_registration_allowed` defaults `allow_registration` to false; tenants must opt in. Tests must seed `allow_registration: true` on the customer before exercising the sign-up view.

---

## File Structure

### New files

```
app/controllers/member/
  base_controller.rb
  dashboards_controller.rb
  profiles_controller.rb
  securities_controller.rb
  payments_controller.rb

app/services/member/
  navigation.rb
  navigation/item.rb

app/contracts/member/profiles/
  update_contract.rb

app/components/member/
  shell_component.rb / shell_component.html.erb
  top_nav_component.rb / top_nav_component.html.erb
  user_menu_component.rb / user_menu_component.html.erb
  hero_card_component.rb / hero_card_component.html.erb
  status_card_component.rb / status_card_component.html.erb
  auth_shell_component.rb / auth_shell_component.html.erb

app/views/layouts/member.html.erb

app/views/member/
  dashboards/show.html.erb
  profiles/show.html.erb
  profiles/edit.html.erb
  securities/show.html.erb
  payments/index.html.erb
  payments/show.html.erb

app/javascript/controllers/
  mobile_nav_controller.js
  user_menu_controller.js

db/migrate/<TIMESTAMP>_add_user_id_to_payments.rb

spec/services/member/navigation_spec.rb
spec/contracts/member/profiles/update_contract_spec.rb

spec/components/member/
  shell_component_spec.rb
  top_nav_component_spec.rb
  user_menu_component_spec.rb
  hero_card_component_spec.rb
  status_card_component_spec.rb
  auth_shell_component_spec.rb

spec/requests/member/
  base_authorization_spec.rb
  dashboards_spec.rb
  profiles_spec.rb
  securities_spec.rb
  payments_spec.rb

spec/system/member/
  sign_up_spec.rb
  sign_in_spec.rb
  password_reset_spec.rb
  home_spec.rb
  profile_spec.rb
  security_spec.rb
  payments_spec.rb
```

### Modified files

```
app/assets/tailwind/application.css           # add member tokens + utilities
app/views/layouts/auth.html.erb               # delegate body to AuthShellComponent
app/views/authentication/sessions/new.html.erb         # reskin
app/views/authentication/registrations/new.html.erb    # reskin
app/views/authentication/passwords/new.html.erb        # reskin
app/views/authentication/passwords/edit.html.erb       # reskin
app/controllers/authentication/registrations_controller.rb  # assign member role + redirect to member
app/models/payments/payment.rb                # add user_id association
config/routes.rb                              # fill in 2c. MEMBER block
spec/factories/payments.rb (if exists; create if not)  # add user trait
```

Each task below specifies exact file paths, full code to write, the exact command to run, and the expected output.

---

## Phase 1 — Foundation

### Task 1.1: Add member CSS tokens and utilities

**Files:**
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Add member tokens to the `@theme` block**

In `app/assets/tailwind/application.css`, find the closing `}` of the `@theme { ... }` block (currently around line 80, just before `@layer base`) and insert the following **inside** the block, immediately before the closing `}`:

```css
  /* ==========================================================================
     Member surface tokens
     --------------------------------------------------------------------------
     A distinct second accent for /:cid/member/* pages and for the auth
     surfaces that lead into them. Lives alongside --color-accent-* (admin
     indigo); admin chrome continues to reference --color-accent-*. Selected
     hue: teal-600 base for warmth + visible separation from admin indigo.
     ========================================================================== */
  --color-member-accent:        #0d9488;
  --color-member-accent-hover:  #0f766e;
  --color-member-accent-active: #115e59;
  --color-member-accent-subtle: #f0fdfa;
  --color-member-accent-muted:  #99f6e4;
  --color-member-accent-text:   #115e59;

  --gradient-member-hero: linear-gradient(135deg,
    var(--color-member-accent) 0%,
    var(--color-member-accent-hover) 100%);
```

- [ ] **Step 2: Add member component utilities to the `@layer components` block**

In the same file, find the `@layer components { ... }` block. Append the following utilities **at the end of that block**, immediately before the closing `}` of `@layer components`:

```css
  /* Member surface utilities — used by Member::* components only.
     These do not replace .btn-primary etc.; admin shells continue to use
     the indigo accent utilities. */

  .btn-member {
    background: var(--color-member-accent);
    color: white;
    border: 1px solid var(--color-member-accent);
    box-shadow: var(--shadow-button);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.375rem;
    font-weight: var(--font-medium);
    font-size: var(--text-sm);
    line-height: var(--leading-tight);
    padding: 0.5rem 0.875rem;
    border-radius: var(--radius-md);
    transition: all 150ms cubic-bezier(0.4, 0, 0.2, 1);
    cursor: pointer;
    white-space: nowrap;
  }

  .btn-member:hover:not(:disabled) {
    background: var(--color-member-accent-hover);
    border-color: var(--color-member-accent-hover);
    box-shadow: var(--shadow-button-hover);
  }

  .btn-member:active:not(:disabled) {
    background: var(--color-member-accent-active);
    box-shadow: var(--shadow-inset);
  }

  .nav-item-member {
    display: inline-flex;
    align-items: center;
    padding: 0.5rem 0.875rem;
    font-size: var(--text-sm);
    font-weight: var(--font-medium);
    color: var(--color-text-secondary);
    border-radius: var(--radius-md);
    transition: all 150ms cubic-bezier(0.4, 0, 0.2, 1);
  }

  .nav-item-member:hover {
    color: var(--color-text-primary);
    background: var(--color-member-accent-subtle);
  }

  .nav-item-member-active {
    color: var(--color-member-accent-text);
    background: var(--color-member-accent-subtle);
  }

  .card-member-elevated {
    background: var(--color-surface);
    border: 1px solid var(--color-border-subtle);
    border-radius: var(--radius-2xl);
    padding: 1.5rem;
    box-shadow: var(--shadow-sm);
    transition: all 200ms cubic-bezier(0.4, 0, 0.2, 1);
  }

  .card-member-elevated:hover {
    border-color: var(--color-member-accent-muted);
    box-shadow: var(--shadow-md);
    transform: translateY(-1px);
  }

  .hero-member {
    background: var(--gradient-member-hero);
    color: white;
    border-radius: var(--radius-2xl);
    padding: 2rem 2.5rem;
    box-shadow: var(--shadow-lg);
  }
```

- [ ] **Step 3: Rebuild the Tailwind asset and remove the manifest**

Run:

```bash
rm -f public/assets/.manifest.json && bin/rails tailwindcss:build
```

Expected output: a successful build message (no errors). The new utilities are now in `app/assets/builds/tailwind.css`.

- [ ] **Step 4: Verify the tokens compiled**

Run:

```bash
grep -c "color-member-accent" app/assets/builds/tailwind.css
```

Expected output: a number ≥ 6 (six token references plus utility usages).

- [ ] **Step 5: Commit**

```bash
git add app/assets/tailwind/application.css app/assets/builds/tailwind.css
git commit -m "feat(member): add teal accent tokens and surface utilities"
```

---

### Task 1.2: Create the Member::Navigation registry

**Files:**
- Create: `app/services/member/navigation/item.rb`
- Create: `app/services/member/navigation.rb`
- Test: `spec/services/member/navigation_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/services/member/navigation_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Navigation do
  let(:customer)        { create(:customer) }
  let(:payments_module) { create(:feature_module, key: "payments") }
  let(:user)            { create(:user, customer: customer) }

  describe ".items_for" do
    it "always returns home, profile, and security items" do
      keys = described_class.items_for(user).map(&:key)
      expect(keys).to include(:home, :profile, :security)
    end

    it "includes the payments item when the customer has the payments module enabled" do
      FeatureModules::CustomerAssignment.create!(
        customer: customer, feature_module: payments_module, status: :active
      )
      keys = described_class.items_for(user).map(&:key)
      expect(keys).to include(:payments)
    end

    it "excludes the payments item when the customer does not have the payments module enabled" do
      keys = described_class.items_for(user).map(&:key)
      expect(keys).not_to include(:payments)
    end

    it "returns Item objects with label, path, and icon populated" do
      home = described_class.items_for(user).find { |i| i.key == :home }
      expect(home.label).to eq("Home")
      expect(home.path_for(customer)).to eq("/#{customer.id}/member")
      expect(home.icon).to eq(:home)
    end
  end
end
```

- [ ] **Step 2: Run the spec — expect a missing-constant failure**

Run:

```bash
bundle exec rspec spec/services/member/navigation_spec.rb -fd
```

Expected: failure with `NameError: uninitialized constant Member::Navigation` or similar.

- [ ] **Step 3: Create the Item value object**

Create `app/services/member/navigation/item.rb`:

```ruby
# frozen_string_literal: true

module Member
  module Navigation
    # Value object describing a single member nav item.
    #
    # @!attribute [r] key       Symbol — used by the shell to mark active state.
    # @!attribute [r] label     String — display text.
    # @!attribute [r] icon      Symbol — Heroicons identifier (rendered by views).
    # @!attribute [r] path      Proc  — callable taking a Customer, returning a URL string.
    # @!attribute [r] visible   Proc  — callable taking a User, returning a Boolean.
    Item = Struct.new(:key, :label, :icon, :path, :visible, keyword_init: true) do
      def path_for(customer)
        path.call(customer)
      end

      def visible_to?(user)
        visible.call(user)
      end
    end
  end
end
```

- [ ] **Step 4: Create the Navigation registry**

Create `app/services/member/navigation.rb`:

```ruby
# frozen_string_literal: true

require_relative "navigation/item"

module Member
  # Registry of member navigation items. Adding a new member
  # surface is a one-line entry here — the shell never needs to be edited.
  #
  # Each item declares its own visibility predicate, so module-gated items
  # (e.g. Payments) are filtered out automatically when the customer has
  # not enabled the corresponding feature module.
  module Navigation
    ITEMS = [
      Item.new(
        key:     :home,
        label:   "Home",
        icon:    :home,
        path:    ->(customer) { "/#{customer.id}/member" },
        visible: ->(_user) { true }
      ),
      Item.new(
        key:     :profile,
        label:   "Profile",
        icon:    :user,
        path:    ->(customer) { "/#{customer.id}/member/profile" },
        visible: ->(_user) { true }
      ),
      Item.new(
        key:     :payments,
        label:   "Payments",
        icon:    :credit_card,
        path:    ->(customer) { "/#{customer.id}/member/payments" },
        visible: ->(user) {
          FeatureModules::Module.enabled?(key: "payments", customer_id: user.customer_id)
        }
      ),
      Item.new(
        key:     :security,
        label:   "Security",
        icon:    :shield_check,
        path:    ->(customer) { "/#{customer.id}/member/security" },
        visible: ->(_user) { true }
      )
    ].freeze

    def self.items_for(user)
      ITEMS.select { |item| item.visible_to?(user) }
    end
  end
end
```

- [ ] **Step 5: Run the spec — expect green**

Run:

```bash
bundle exec rspec spec/services/member/navigation_spec.rb -fd
```

Expected: 4 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/member/ spec/services/member/
git commit -m "feat(member): add navigation registry with module-gated visibility"
```

---

### Task 1.3: Create Member::BaseController with the three-gate authorization contract

**Files:**
- Create: `app/controllers/member/base_controller.rb`
- Create: `app/controllers/member/dashboards_controller.rb` (stub that just renders text — fleshed out in Phase 3)
- Modify: `config/routes.rb`
- Test: `spec/requests/member/base_authorization_spec.rb`

- [ ] **Step 1: Add the route block**

In `config/routes.rb`, find the `# 2c. MEMBER` placeholder block (currently three comment lines around line 286). Replace the placeholder block with:

```ruby
    # ========================================================================
    # 2c. MEMBER — /:cid/member/...   (member role required)
    # ========================================================================
    namespace :member do
      resource  :dashboard, only: :show, controller: "dashboards", path: ""
      resource  :profile,   only: %i[show edit update]
      resource  :security,  only: :show, controller: "securities"
      resources :payments,  only: %i[index show]
    end
```

- [ ] **Step 2: Verify routes compiled without breaking the rest**

Run:

```bash
bin/rails routes -g member
```

Expected: 7 lines listing the member routes (`member_dashboard`, `member_profile`, `edit_member_profile`, `member_security`, `member_payments`, `member_payment`).

- [ ] **Step 3: Write the failing authorization request spec**

Create `spec/requests/member/base_authorization_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member base authorization", type: :request do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:member_user)    { create(:user, :member, customer: customer) }
  let(:admin_user)     { create(:user, :admin, customer: customer) }
  let(:dashboard_url)  { "/#{customer.id}/member" }

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    [customer, other_customer].each do |c|
      FeatureModules::CustomerAssignment.find_or_create_by!(
        customer: c, feature_module: auth_module
      ) { |a| a.status = :active }
    end
  end

  context "anonymous user" do
    it "is redirected to the customer sign-in page" do
      get dashboard_url
      expect(response).to redirect_to("/#{customer.id}/auth/sign_in")
    end
  end

  context "admin user visiting a member URL in their own tenant" do
    before { sign_in admin_user }

    it "is rejected by the role gate with the standard tenant-aware redirect" do
      get dashboard_url
      expect(response).to redirect_to("/#{customer.id}")
      expect(flash[:alert]).to match(/member/i)
    end
  end

  context "owner user visiting a member URL in their own tenant" do
    let(:owner_user) { find_or_create_platform_owner }

    before do
      auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
      FeatureModules::CustomerAssignment.find_or_create_by!(
        customer: owner_user.customer, feature_module: auth_module
      ) { |a| a.status = :active }
      sign_in owner_user
    end

    it "is rejected by the role gate (owners are not members)" do
      get "/#{owner_user.customer_id}/member"
      expect(response).to redirect_to("/#{owner_user.customer_id}")
      expect(flash[:alert]).to match(/member/i)
    end
  end

  context "member of customer A visiting customer B's URL" do
    before { sign_in member_user }

    it "is rejected by the tenant gate with the cross-tenant redirect" do
      get "/#{other_customer.id}/member"
      expect(response).to redirect_to("/#{member_user.customer_id}/admin/dashboard")
      expect(flash[:alert]).to match(/access denied/i)
    end
  end

  context "member visiting their own member URL" do
    before { sign_in member_user }

    it "succeeds" do
      get dashboard_url
      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 4: Run the spec — expect failures**

Run:

```bash
bundle exec rspec spec/requests/member/base_authorization_spec.rb -fd
```

Expected: failures because `Member::DashboardsController` does not yet exist (likely a routing/controller-not-found error or 500).

- [ ] **Step 5: Create the BaseController**

The URL+role gate and the tenant gate are NOT installed here — they're inherited from the global `RouteAuthorization` and `TenantContext` concerns that `ApplicationController` already includes. `BaseController` only owns the layout, helpers, and the record-level `authorize_owned!`.

Create `app/controllers/member/base_controller.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Base controller for /:cid/member/* — the member-facing portal.
  #
  # Authorization is composed from three layers:
  #
  #   1. URL gate     — inherited from app/controllers/concerns/route_authorization.rb,
  #                     which gates /:cid/member/* on current_user.member?
  #                     and rejects with CanCan::AccessDenied otherwise.
  #   2. Tenant gate  — inherited from app/controllers/concerns/tenant_context.rb,
  #                     which redirects cross-tenant access to the user's own
  #                     /:cid/admin/dashboard.
  #   3. Record gate  — authorize_owned!(record), defined here. Controllers
  #                     call this before rendering or mutating a specific
  #                     record; mismatches raise ActiveRecord::RecordNotFound.
  #
  # See docs/superpowers/specs/2026-05-15-member-skeleton-design.md §7
  # for the full contract and the test cases that lock it in.
  class BaseController < ApplicationController
    layout "member"

    helper_method :current_member, :member_nav_items

    private

    def current_member
      current_user
    end

    def member_nav_items
      Member::Navigation.items_for(current_user)
    end

    # Record gate. Raises ActiveRecord::RecordNotFound (404) when:
    #   - the record is missing,
    #   - the record belongs to a different tenant, or
    #   - the record has a user_id and it doesn't match current_user.id.
    # Tenant mismatch should already have been caught by TenantContext, so the
    # tenant check here is a defense-in-depth assertion.
    def authorize_owned!(record)
      raise ActiveRecord::RecordNotFound unless record &&
        record.customer_id == current_user.customer_id &&
        (!record.respond_to?(:user_id) || record.user_id == current_user.id)
    end
  end
end
```

After creating the controller, also extend `app/models/ability.rb` so members can pass the global `authorize_route!` filter for member paths. Find the `if user.has_reserved_role?(:admin)` block and append a parallel block immediately after it:

```ruby
    if user.has_reserved_role?(:member)
      # Tenant member — implicit access to every member route within
      # their own customer. Member routes don't carry per-action
      # role_permission rows; the URL-prefix gate (RouteAuthorization)
      # plus per-record ownership checks (Member::BaseController#
      # authorize_owned!) provide the actual security. This rule lets the
      # CanCan layer pass for any /:cid/member/* request.
      can :manage, member_route_subjects
    end
```

And add the helper method alongside `platform_owner_subjects`:

```ruby
  # CanCan route subjects for /:cid/member/* paths. Adding a new
  # member controller means adding its symbol here so the member
  # role can pass the global authorize_route! filter; the actual
  # member-specific security lives in the URL-prefix gate and the
  # per-record ownership check.
  def member_route_subjects
    [
      :route_member_dashboards,
      :route_member_profiles,
      :route_member_securities,
      :route_member_payments
    ]
  end
```

Also update `spec/factories/users.rb` so the `:member` trait creates a real `users_roles` row (the `member?` predicate requires a role-row, even though the previous factory comment said "members don't need a role row"). Replace the case branch:

```ruby
                 when :member then "member"
```

(was `nil`). And add a parallel trait alongside `:admin`:

```ruby
    trait :member do
      role { :member }
    end
```

- [ ] **Step 6: Create the stub DashboardsController**

Create `app/controllers/member/dashboards_controller.rb`:

```ruby
# frozen_string_literal: true

module Member
  # The member home page. Filled out in Phase 3 — for now this just
  # renders an empty page so the authorization contract specs can pass.
  class DashboardsController < BaseController
    def show
      render plain: "member dashboard ok"
    end
  end
end
```

- [ ] **Step 7: Add the spec helper for Devise sign-in**

If `spec/support/devise.rb` does not exist, create it:

```ruby
# frozen_string_literal: true

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
end
```

If it already exists, ensure both `:request` and `:system` are configured.

- [ ] **Step 8: Run the spec — expect green**

Run:

```bash
bundle exec rspec spec/requests/member/base_authorization_spec.rb -fd
```

Expected: 4 examples, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/member/ config/routes.rb spec/requests/member/ spec/support/devise.rb
git commit -m "feat(member): add base controller, route block, three-gate authz contract"
```

---

### Task 1.4: Create the member layout and ShellComponent

**Files:**
- Create: `app/views/layouts/member.html.erb`
- Create: `app/components/member/shell_component.rb`
- Create: `app/components/member/shell_component.html.erb`
- Test: `spec/components/member/shell_component_spec.rb`

- [ ] **Step 1: Write the failing component spec**

Create `spec/components/member/shell_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::ShellComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }

  it "renders the top nav, the flash region, and the wrapped content" do
    render_inline(described_class.new(
      customer: customer, user: user, current_nav: :home
    )) { "page body" }

    expect(page).to have_css("[data-shell='member']")
    expect(page).to have_css("nav[data-component='member-top-nav']")
    expect(page).to have_text("page body")
  end

  it "applies the default container width when none given" do
    render_inline(described_class.new(
      customer: customer, user: user, current_nav: :home
    )) { "x" }

    expect(page).to have_css("main.max-w-6xl")
  end

  it "renders content edge-to-edge when container_width is :edge" do
    render_inline(described_class.new(
      customer: customer, user: user, current_nav: :home, container_width: :edge
    )) { "x" }

    expect(page).not_to have_css("main.max-w-6xl")
    expect(page).to have_css("main.w-full")
  end
end
```

- [ ] **Step 2: Run the spec — expect failure**

Run:

```bash
bundle exec rspec spec/components/member/shell_component_spec.rb -fd
```

Expected: failure because the component does not exist.

- [ ] **Step 3: Create the ShellComponent class**

Create `app/components/member/shell_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Shell for /:cid/member/* pages. Top-nav + main; no sidebar, no
  # menu-bar, no drawer — member surfaces are deliberately lighter
  # than the admin chrome.
  class ShellComponent < ApplicationComponent
    CONTAINER_CLASSES = {
      default: "max-w-6xl mx-auto px-4 sm:px-6 lg:px-8",
      narrow:  "max-w-3xl mx-auto px-4 sm:px-6 lg:px-8",
      edge:    "w-full"
    }.freeze

    def initialize(customer:, user:, current_nav:, container_width: :default)
      @customer        = customer
      @user            = user
      @current_nav     = current_nav
      @container_width = container_width
    end

    attr_reader :customer, :user, :current_nav, :container_width

    def container_classes
      CONTAINER_CLASSES.fetch(container_width, CONTAINER_CLASSES[:default])
    end

    def nav_items
      Member::Navigation.items_for(user)
    end
  end
end
```

- [ ] **Step 4: Create the ShellComponent template**

Create `app/components/member/shell_component.html.erb`:

```erb
<div data-shell="member" class="min-h-screen flex flex-col bg-canvas">
  <%= render Member::TopNavComponent.new(
        customer: customer,
        user: user,
        items: nav_items,
        current_nav: current_nav
      ) %>

  <% if helpers.flash.any? %>
    <div class="<%= container_classes %> pt-4">
      <% helpers.flash.each do |type, message| %>
        <div class="rounded-lg p-4 mb-3 text-sm <%= type.to_s == 'alert' ? 'bg-danger-subtle text-danger' : 'bg-member-accent-subtle text-member-accent-text' %>"
             role="alert" data-controller="flash" data-flash-auto-dismiss-value="<%= type.to_s != 'alert' %>">
          <%= message %>
        </div>
      <% end %>
    </div>
  <% end %>

  <main class="flex-1 <%= container_classes %> py-8 lg:py-12">
    <%= content %>
  </main>
</div>
```

- [ ] **Step 5: Create the layout**

Create `app/views/layouts/member.html.erb`:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Account — Anysys" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= yield :head %>
    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">
    <link rel="preconnect" href="https://rsms.me/">
    <link rel="stylesheet" href="https://rsms.me/inter/inter.css">
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-canvas antialiased">
    <%= render Member::ShellComponent.new(
          customer: current_customer,
          user: current_user,
          current_nav: (defined?(member_nav) ? member_nav : :home),
          container_width: (defined?(member_container_width) ? member_container_width : :default)
        ) do %>
      <%= yield %>
    <% end %>
  </body>
</html>
```

- [ ] **Step 6: The spec depends on TopNavComponent — defer the run**

The component spec calls `render_inline` which will invoke the template, which renders `Member::TopNavComponent`. We build that in the next task. Skip the run for now and proceed to Task 1.5.

---

### Task 1.5: Create TopNavComponent and UserMenuComponent

**Files:**
- Create: `app/components/member/top_nav_component.rb`
- Create: `app/components/member/top_nav_component.html.erb`
- Create: `app/components/member/user_menu_component.rb`
- Create: `app/components/member/user_menu_component.html.erb`
- Create: `app/javascript/controllers/mobile_nav_controller.js`
- Create: `app/javascript/controllers/user_menu_controller.js`
- Test: `spec/components/member/top_nav_component_spec.rb`
- Test: `spec/components/member/user_menu_component_spec.rb`

- [ ] **Step 1: Write failing TopNav spec**

Create `spec/components/member/top_nav_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::TopNavComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, first_name: "Lin", last_name: "Vega") }
  let(:items)    { Member::Navigation.items_for(user) }

  it "renders a link for each visible nav item" do
    render_inline(described_class.new(customer: customer, user: user, items: items, current_nav: :home))

    expect(page).to have_link("Home",     href: "/#{customer.id}/member")
    expect(page).to have_link("Profile",  href: "/#{customer.id}/member/profile")
    expect(page).to have_link("Security", href: "/#{customer.id}/member/security")
  end

  it "applies the active class to the current nav item" do
    render_inline(described_class.new(customer: customer, user: user, items: items, current_nav: :profile))

    profile_link = page.find_link("Profile")
    expect(profile_link[:class]).to include("nav-item-member-active")
  end

  it "renders a logo link to the member home" do
    render_inline(described_class.new(customer: customer, user: user, items: items, current_nav: :home))

    expect(page).to have_css("a[href='/#{customer.id}/member'] [data-logo='member']")
  end

  it "renders the user menu with the user's initials" do
    render_inline(described_class.new(customer: customer, user: user, items: items, current_nav: :home))

    expect(page).to have_css("[data-component='member-user-menu']")
    expect(page).to have_text("LV")
  end

  it "renders a mobile menu toggle button on small screens" do
    render_inline(described_class.new(customer: customer, user: user, items: items, current_nav: :home))

    expect(page).to have_css("button[data-action*='mobile-nav#toggle']")
  end
end
```

- [ ] **Step 2: Write failing UserMenu spec**

Create `spec/components/member/user_menu_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::UserMenuComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, first_name: "Lin", last_name: "Vega") }

  it "renders the user's initials inside the avatar trigger" do
    render_inline(described_class.new(customer: customer, user: user))

    expect(page).to have_css("[data-component='member-user-menu']")
    expect(page).to have_text("LV")
  end

  it "links to profile, security, and the sign-out destroy path" do
    render_inline(described_class.new(customer: customer, user: user))

    expect(page).to have_link("Your profile", href: "/#{customer.id}/member/profile")
    expect(page).to have_link("Security",     href: "/#{customer.id}/member/security")
    expect(page).to have_css(
      "a[data-turbo-method='delete'][href='/#{customer.id}/auth/sign_out']",
      text: "Sign out"
    )
  end
end
```

- [ ] **Step 3: Run both specs — expect failure**

Run:

```bash
bundle exec rspec spec/components/member/top_nav_component_spec.rb spec/components/member/user_menu_component_spec.rb
```

Expected: failures because neither component exists.

- [ ] **Step 4: Create UserMenuComponent class**

Create `app/components/member/user_menu_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  class UserMenuComponent < ApplicationComponent
    def initialize(customer:, user:)
      @customer = customer
      @user     = user
    end

    attr_reader :customer, :user

    def initials
      "#{user.first_name.to_s[0]}#{user.last_name.to_s[0]}".upcase
    end

    def profile_path
      "/#{customer.id}/member/profile"
    end

    def security_path
      "/#{customer.id}/member/security"
    end

    def sign_out_path
      "/#{customer.id}/auth/sign_out"
    end
  end
end
```

- [ ] **Step 5: Create UserMenuComponent template**

Create `app/components/member/user_menu_component.html.erb`:

```erb
<div class="relative" data-component="member-user-menu" data-controller="user-menu">
  <button type="button"
          class="inline-flex items-center gap-2 rounded-full bg-member-accent-subtle px-2 py-1.5 text-sm font-medium text-member-accent-text hover:bg-member-accent-muted/40 transition-base"
          aria-haspopup="menu"
          aria-expanded="false"
          data-action="click->user-menu#toggle"
          data-user-menu-target="trigger">
    <span class="inline-flex h-7 w-7 items-center justify-center rounded-full bg-member-accent text-white text-xs font-semibold tracking-wide">
      <%= initials %>
    </span>
    <span class="hidden sm:inline"><%= user.display_name %></span>
    <svg class="h-4 w-4 text-member-accent-text/70" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.06l3.71-3.83a.75.75 0 111.08 1.04l-4.25 4.39a.75.75 0 01-1.08 0L5.21 8.27a.75.75 0 01.02-1.06z" clip-rule="evenodd"/></svg>
  </button>

  <div class="absolute right-0 mt-2 w-56 origin-top-right rounded-xl bg-surface py-2 shadow-float ring-1 ring-border-subtle hidden"
       role="menu"
       data-user-menu-target="panel">
    <div class="px-4 py-2 border-b border-border-subtle">
      <p class="text-sm font-semibold text-text-primary truncate"><%= user.display_name %></p>
      <p class="text-xs text-text-tertiary truncate"><%= user.email %></p>
    </div>
    <%= link_to "Your profile", profile_path,
          class: "block px-4 py-2 text-sm text-text-secondary hover:bg-surface-hover hover:text-text-primary",
          role: "menuitem" %>
    <%= link_to "Security", security_path,
          class: "block px-4 py-2 text-sm text-text-secondary hover:bg-surface-hover hover:text-text-primary",
          role: "menuitem" %>
    <div class="my-1 border-t border-border-subtle"></div>
    <%= link_to "Sign out", sign_out_path,
          data: { turbo_method: :delete },
          class: "block px-4 py-2 text-sm text-text-secondary hover:bg-danger-subtle hover:text-danger",
          role: "menuitem" %>
  </div>
</div>
```

- [ ] **Step 6: Create TopNavComponent class**

Create `app/components/member/top_nav_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Top navigation bar for the member shell. Stateless — receives the
  # nav items array from the shell, which sources it from
  # Member::Navigation.
  class TopNavComponent < ApplicationComponent
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
  end
end
```

- [ ] **Step 7: Create TopNavComponent template**

Create `app/components/member/top_nav_component.html.erb`:

```erb
<nav class="bg-surface border-b border-border-subtle sticky top-0 z-30"
     data-component="member-top-nav"
     data-controller="mobile-nav">
  <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
    <div class="flex items-center justify-between h-16">

      <%# logo + mobile toggle %>
      <div class="flex items-center gap-3">
        <button type="button"
                class="md:hidden inline-flex h-10 w-10 items-center justify-center rounded-lg text-text-secondary hover:bg-surface-hover transition-base"
                aria-label="Open menu"
                data-action="click->mobile-nav#toggle">
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16"/>
          </svg>
        </button>

        <%= link_to home_path, class: "inline-flex items-center gap-2.5 group" do %>
          <span data-logo="member"
                class="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-member-accent to-member-accent-hover text-white shadow-sm">
            <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 12l2-2 4 4 8-8 4 4"/>
            </svg>
          </span>
          <span class="text-base font-semibold tracking-tight text-text-primary"><%= customer.name %></span>
        <% end %>
      </div>

      <%# desktop nav items %>
      <div class="hidden md:flex items-center gap-1">
        <% items.each do |item| %>
          <%= link_to item.label, item.path_for(customer), class: nav_link_class(item) %>
        <% end %>
      </div>

      <%# user menu %>
      <div class="flex items-center gap-2">
        <%= render Member::UserMenuComponent.new(customer: customer, user: user) %>
      </div>
    </div>

    <%# mobile sheet — hidden by default; toggled by mobile-nav controller %>
    <div class="md:hidden hidden border-t border-border-subtle py-3"
         data-mobile-nav-target="sheet">
      <div class="flex flex-col gap-1">
        <% items.each do |item| %>
          <%= link_to item.label, item.path_for(customer),
                      class: "block px-3 py-2 rounded-lg #{nav_link_class(item)}" %>
        <% end %>
      </div>
    </div>
  </div>
</nav>
```

- [ ] **Step 8: Create the mobile-nav Stimulus controller**

Create `app/javascript/controllers/mobile_nav_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Toggles the mobile member nav sheet. The sheet starts hidden; the
// hamburger button data-actions click->mobile-nav#toggle.
export default class extends Controller {
  static targets = ["sheet"]

  toggle() {
    if (!this.hasSheetTarget) return
    this.sheetTarget.classList.toggle("hidden")
  }
}
```

- [ ] **Step 9: Create the user-menu Stimulus controller**

Create `app/javascript/controllers/user_menu_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Toggles the member user-menu dropdown panel.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
  }

  toggle(event) {
    event.stopPropagation()
    const open = !this.panelTarget.classList.contains("hidden")
    this.panelTarget.classList.toggle("hidden", open)
    this.triggerTarget.setAttribute("aria-expanded", String(!open))
  }

  handleOutsideClick(event) {
    if (this.element.contains(event.target)) return
    this.panelTarget.classList.add("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }
}
```

- [ ] **Step 10: Run all component specs — expect green**

Run:

```bash
bundle exec rspec spec/components/member/
```

Expected: all examples passing across `shell_component_spec.rb`, `top_nav_component_spec.rb`, `user_menu_component_spec.rb`.

- [ ] **Step 11: Smoke-test the layout via the dashboard stub**

Run:

```bash
bundle exec rspec spec/requests/member/base_authorization_spec.rb -fd
```

Expected: still 4 examples, 0 failures.

- [ ] **Step 12: Commit**

```bash
git add app/views/layouts/member.html.erb app/components/member/ app/javascript/controllers/ spec/components/member/
git commit -m "feat(member): add layout, ShellComponent, TopNav, UserMenu, mobile-nav controller"
```

---

### Task 1.6: Update DashboardsController to render the layout instead of plain text

**Files:**
- Modify: `app/controllers/member/dashboards_controller.rb`
- Create: `app/views/member/dashboards/show.html.erb`
- Modify: `spec/requests/member/base_authorization_spec.rb` (assertion update)

- [ ] **Step 1: Replace the plain-text stub with a rendered template**

Replace the entire body of `app/controllers/member/dashboards_controller.rb` with:

```ruby
# frozen_string_literal: true

module Member
  class DashboardsController < BaseController
    def show
      # Phase 3 fills this in with hero + status cards + recent activity.
    end
  end
end
```

- [ ] **Step 2: Create a placeholder view that exercises the layout**

Create `app/views/member/dashboards/show.html.erb`:

```erb
<% content_for :title, "Home — Anysys" %>
<% content_for :member_nav, "home" %>
<div class="card-member-elevated">
  <h1 class="text-title mb-2">Welcome.</h1>
  <p class="text-body-sm">Your dashboard is being prepared.</p>
</div>
```

- [ ] **Step 3: Update the authz spec's success assertion**

In `spec/requests/member/base_authorization_spec.rb`, find the `"member visiting their own member URL"` block. Replace its body with:

```ruby
    it "succeeds and renders the dashboard layout" do
      get dashboard_url
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-shell=\"member\"")
    end
```

- [ ] **Step 4: Run the spec — expect green**

Run:

```bash
bundle exec rspec spec/requests/member/base_authorization_spec.rb -fd
```

Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/member/dashboards_controller.rb app/views/member/ spec/requests/member/base_authorization_spec.rb
git commit -m "feat(member): render real layout from dashboards#show stub"
```

---

**Phase 1 checkpoint.** Foundation complete. The `/:cid/member` URL renders a styled shell. Authorization contract is locked in by `base_authorization_spec.rb`. Subsequent phases add real pages on top of this chassis without touching the shell.

---

## Phase 2 — Auth reskin

### Task 2.1: Create Member::AuthShellComponent

**Files:**
- Create: `app/components/member/auth_shell_component.rb`
- Create: `app/components/member/auth_shell_component.html.erb`
- Test: `spec/components/member/auth_shell_component_spec.rb`

- [ ] **Step 1: Write the failing component spec**

Create `spec/components/member/auth_shell_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::AuthShellComponent, type: :component do
  let(:customer) { create(:customer, name: "Acme") }

  it "renders the brand panel with the customer name and the gradient hero class" do
    render_inline(described_class.new(
      customer: customer, title: "Welcome back", subtitle: "Sign in to your account"
    )) { "<form>x</form>".html_safe }

    expect(page).to have_css("[data-shell='member-auth']")
    expect(page).to have_css(".hero-member")
    expect(page).to have_text("Acme")
    expect(page).to have_text("Welcome back")
    expect(page).to have_text("Sign in to your account")
  end

  it "renders the form content slot on the right pane" do
    render_inline(described_class.new(
      customer: customer, title: "x", subtitle: "y"
    )) { "<form data-slot='form'></form>".html_safe }

    expect(page).to have_css("[data-pane='form'] form[data-slot='form']")
  end
end
```

- [ ] **Step 2: Run the spec — expect failure**

Run:

```bash
bundle exec rspec spec/components/member/auth_shell_component_spec.rb
```

Expected: failure, component does not exist.

- [ ] **Step 3: Create the AuthShellComponent class**

Create `app/components/member/auth_shell_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Split-pane shell for /:cid/auth/* surfaces (sign-in, sign-up, password
  # recovery). Brand/marketing panel on the left, form on the right.
  # Mobile collapses to single-column with the brand panel as a slim header.
  class AuthShellComponent < ApplicationComponent
    def initialize(customer:, title:, subtitle:)
      @customer = customer
      @title    = title
      @subtitle = subtitle
    end

    attr_reader :customer, :title, :subtitle
  end
end
```

- [ ] **Step 4: Create the AuthShellComponent template**

Create `app/components/member/auth_shell_component.html.erb`:

```erb
<div data-shell="member-auth" class="min-h-screen flex flex-col lg:flex-row bg-canvas">
  <%# brand pane %>
  <aside class="lg:w-1/2 lg:min-h-screen flex items-center justify-center p-6 lg:p-12">
    <div class="hero-member w-full max-w-lg">
      <div class="flex items-center gap-3 mb-8">
        <span class="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-white/15 backdrop-blur ring-1 ring-white/20">
          <svg class="h-5 w-5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 12l2-2 4 4 8-8 4 4"/>
          </svg>
        </span>
        <span class="text-base font-semibold tracking-tight text-white"><%= customer&.name || "Member portal" %></span>
      </div>

      <h1 class="text-display text-white mb-3"><%= title %></h1>
      <p class="text-body text-white/85"><%= subtitle %></p>

      <div class="mt-12 grid grid-cols-3 gap-4">
        <div class="rounded-lg bg-white/10 backdrop-blur ring-1 ring-white/15 p-3 text-white/90 text-xs">Manage your profile</div>
        <div class="rounded-lg bg-white/10 backdrop-blur ring-1 ring-white/15 p-3 text-white/90 text-xs">Track payments</div>
        <div class="rounded-lg bg-white/10 backdrop-blur ring-1 ring-white/15 p-3 text-white/90 text-xs">Stay secure</div>
      </div>
    </div>
  </aside>

  <%# form pane %>
  <section data-pane="form" class="lg:w-1/2 flex items-center justify-center p-6 lg:p-12">
    <div class="w-full max-w-md">
      <%= content %>
    </div>
  </section>
</div>
```

- [ ] **Step 5: Run the spec — expect green**

Run:

```bash
bundle exec rspec spec/components/member/auth_shell_component_spec.rb
```

Expected: 2 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/components/member/auth_shell_component.rb app/components/member/auth_shell_component.html.erb spec/components/member/auth_shell_component_spec.rb
git commit -m "feat(member): add AuthShellComponent split-pane wrapper"
```

---

### Task 2.2: Reskin layouts/auth.html.erb to consume AuthShellComponent

**Files:**
- Modify: `app/views/layouts/auth.html.erb`

- [ ] **Step 1: Replace the entire file**

Replace `app/views/layouts/auth.html.erb` with:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Sign in — Anysys" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= yield :head %>
    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">
    <link rel="preconnect" href="https://rsms.me/">
    <link rel="stylesheet" href="https://rsms.me/inter/inter.css">
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-canvas antialiased">
    <%= yield %>
  </body>
</html>
```

The body of each individual auth view (next tasks) will render the `AuthShellComponent` directly so each view chooses its own title/subtitle copy.

- [ ] **Step 2: Sanity-build the asset pipeline**

Run:

```bash
rm -f public/assets/.manifest.json && bin/rails tailwindcss:build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/auth.html.erb app/assets/builds/tailwind.css
git commit -m "refactor(auth): simplify auth layout to plain shell, views own AuthShell"
```

---

### Task 2.3: Reskin the sign-in view

**Files:**
- Modify: `app/views/authentication/sessions/new.html.erb`

- [ ] **Step 1: Replace the entire file**

Replace `app/views/authentication/sessions/new.html.erb` with:

```erb
<%= render Member::AuthShellComponent.new(
      customer: current_customer,
      title:    "Welcome back.",
      subtitle: "Sign in to manage your profile, payments, and security."
    ) do %>

  <div class="mb-8">
    <h2 class="text-subtitle mb-1">Sign in</h2>
    <p class="text-body-sm">Use the email and password you registered with.</p>
  </div>

  <% form_url = current_customer_id.present? ? user_session_path(customer_id: current_customer_id) : customer_sign_in_path %>
  <%= form_for(resource, as: resource_name, url: form_url, html: { class: "space-y-5" }) do |f| %>

    <% if resource.errors.any? %>
      <div class="rounded-lg bg-danger-subtle border border-danger/20 p-3">
        <p class="text-sm text-danger"><%= resource.errors.full_messages.first %></p>
      </div>
    <% end %>

    <div>
      <label class="form-label">Customer number</label>
      <%= text_field_tag :customer_number, params[:customer_number] || current_customer_id,
            autocomplete: "off",
            placeholder: "00000000",
            maxlength: 8,
            pattern: "[0-9]{8}",
            inputmode: "numeric",
            autofocus: current_customer_id.blank?,
            readonly: current_customer_id.present?,
            class: "input-field font-mono tracking-wider #{'bg-surface-active' if current_customer_id.present?}" %>
    </div>

    <div>
      <%= f.label :email, class: "form-label" %>
      <%= f.email_field :email, autofocus: current_customer_id.present?, autocomplete: "email",
            placeholder: "you@example.com", class: "input-field" %>
    </div>

    <div>
      <%= f.label :password, class: "form-label" %>
      <%= f.password_field :password, autocomplete: "current-password",
            placeholder: "Your password", class: "input-field" %>
    </div>

    <div class="flex items-center justify-between">
      <label class="inline-flex items-center text-sm text-text-secondary">
        <%= f.check_box :remember_me, class: "h-4 w-4 mr-2 rounded border-border" %>
        Remember me
      </label>

      <% if current_customer_id.present? %>
        <%= link_to "Forgot password?",
              new_user_password_path(customer_id: current_customer_id),
              class: "text-sm font-medium text-member-accent-text hover:underline" %>
      <% end %>
    </div>

    <%= f.submit "Sign in", class: "btn-member w-full justify-center" %>
  <% end %>

  <% if current_customer_id.present? %>
    <p class="mt-6 text-center text-sm text-text-tertiary">
      New here?
      <%= link_to "Create an account",
            new_user_registration_path(customer_id: current_customer_id),
            class: "font-medium text-member-accent-text hover:underline" %>
    </p>
  <% end %>
<% end %>
```

- [ ] **Step 2: Manually verify by booting the test environment**

Run:

```bash
bundle exec rspec spec/system/ -fd 2>/dev/null | tail -20
```

Expected: existing system specs unaffected (or surface a known failure unrelated to this change).

- [ ] **Step 3: Commit**

```bash
git add app/views/authentication/sessions/new.html.erb
git commit -m "design(auth): reskin sign-in to AuthShell + design tokens"
```

---

### Task 2.4: Reskin the sign-up view

**Files:**
- Modify: `app/views/authentication/registrations/new.html.erb`

- [ ] **Step 1: Replace the file**

Replace `app/views/authentication/registrations/new.html.erb` with:

```erb
<%= render Member::AuthShellComponent.new(
      customer: current_customer,
      title:    "Create your account.",
      subtitle: "Join your organization's portal in under a minute."
    ) do %>

  <div class="mb-8">
    <h2 class="text-subtitle mb-1">Sign up</h2>
    <p class="text-body-sm">Already have an account?
      <%= link_to "Sign in", new_user_session_path(customer_id: current_customer_id),
            class: "font-medium text-member-accent-text hover:underline" %>.</p>
  </div>

  <%= form_for(resource, as: resource_name,
        url: user_registration_path(customer_id: current_customer_id),
        html: { class: "space-y-5" }) do |f| %>

    <% if resource.errors.any? %>
      <div class="rounded-lg bg-danger-subtle border border-danger/20 p-3">
        <ul class="text-sm text-danger list-disc pl-5 space-y-1">
          <% resource.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="grid grid-cols-2 gap-4">
      <div>
        <%= f.label :first_name, class: "form-label form-label-required" %>
        <%= f.text_field :first_name, autocomplete: "given-name", class: "input-field" %>
      </div>
      <div>
        <%= f.label :last_name, class: "form-label form-label-required" %>
        <%= f.text_field :last_name, autocomplete: "family-name", class: "input-field" %>
      </div>
    </div>

    <div>
      <%= f.label :email, class: "form-label form-label-required" %>
      <%= f.email_field :email, autocomplete: "email", placeholder: "you@example.com", class: "input-field" %>
    </div>

    <div>
      <%= f.label :password, class: "form-label form-label-required" %>
      <%= f.password_field :password, autocomplete: "new-password",
            placeholder: "At least #{@minimum_password_length || 8} characters",
            class: "input-field" %>
    </div>

    <div>
      <%= f.label :password_confirmation, "Confirm password", class: "form-label form-label-required" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password", class: "input-field" %>
    </div>

    <%= f.submit "Create account", class: "btn-member w-full justify-center" %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/authentication/registrations/new.html.erb
git commit -m "design(auth): reskin sign-up to AuthShell + design tokens"
```

---

### Task 2.5: Reskin password recovery views

**Files:**
- Modify: `app/views/authentication/passwords/new.html.erb`
- Modify: `app/views/authentication/passwords/edit.html.erb`

- [ ] **Step 1: Replace the new password view**

Replace `app/views/authentication/passwords/new.html.erb` with:

```erb
<%= render Member::AuthShellComponent.new(
      customer: current_customer,
      title:    "Reset your password.",
      subtitle: "We'll email you a link to set a new one."
    ) do %>

  <div class="mb-8">
    <h2 class="text-subtitle mb-1">Forgot password</h2>
    <p class="text-body-sm">Enter the email you registered with.</p>
  </div>

  <%= form_for(resource, as: resource_name,
        url: user_password_path(customer_id: current_customer_id),
        html: { class: "space-y-5" }) do |f| %>

    <% if resource.errors.any? %>
      <div class="rounded-lg bg-danger-subtle border border-danger/20 p-3">
        <p class="text-sm text-danger"><%= resource.errors.full_messages.first %></p>
      </div>
    <% end %>

    <div>
      <%= f.label :email, class: "form-label form-label-required" %>
      <%= f.email_field :email, autocomplete: "email", placeholder: "you@example.com", class: "input-field" %>
    </div>

    <%= f.submit "Send reset link", class: "btn-member w-full justify-center" %>
  <% end %>

  <p class="mt-6 text-center text-sm text-text-tertiary">
    Remembered it?
    <%= link_to "Back to sign in", new_user_session_path(customer_id: current_customer_id),
          class: "font-medium text-member-accent-text hover:underline" %>
  </p>
<% end %>
```

- [ ] **Step 2: Replace the edit password view**

Replace `app/views/authentication/passwords/edit.html.erb` with:

```erb
<%= render Member::AuthShellComponent.new(
      customer: current_customer,
      title:    "Set a new password.",
      subtitle: "Choose something memorable but hard to guess."
    ) do %>

  <div class="mb-8">
    <h2 class="text-subtitle mb-1">New password</h2>
    <p class="text-body-sm">This will replace your existing password.</p>
  </div>

  <%= form_for(resource, as: resource_name,
        url: user_password_path(customer_id: current_customer_id),
        html: { method: :put, class: "space-y-5" }) do |f| %>

    <%= f.hidden_field :reset_password_token %>

    <% if resource.errors.any? %>
      <div class="rounded-lg bg-danger-subtle border border-danger/20 p-3">
        <p class="text-sm text-danger"><%= resource.errors.full_messages.first %></p>
      </div>
    <% end %>

    <div>
      <%= f.label :password, "New password", class: "form-label form-label-required" %>
      <%= f.password_field :password, autocomplete: "new-password",
            placeholder: "At least #{@minimum_password_length || 8} characters",
            class: "input-field" %>
    </div>

    <div>
      <%= f.label :password_confirmation, "Confirm password", class: "form-label form-label-required" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password", class: "input-field" %>
    </div>

    <%= f.submit "Set new password", class: "btn-member w-full justify-center" %>
  <% end %>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/views/authentication/passwords/new.html.erb app/views/authentication/passwords/edit.html.erb
git commit -m "design(auth): reskin password recovery views to AuthShell"
```

---

### Task 2.6: Update RegistrationsController — assign member role + redirect to member

**Files:**
- Modify: `app/controllers/authentication/registrations_controller.rb`

- [ ] **Step 1: Locate the create action and the after_sign_up_path_for method**

Read lines 19–34 (the `create` action) and lines 67–73 (`after_sign_up_path_for`) of `app/controllers/authentication/registrations_controller.rb`.

- [ ] **Step 2: Modify the create action to assign the member role on success**

Replace the `create` method (lines 19–34) with:

```ruby
    # POST /:customer_id/auth/sign_up
    def create
      build_resource(sign_up_params)
      resource.customer_id = current_customer_id

      resource.save
      if resource.persisted?
        assign_member_role!(resource)
        set_flash_message!(:notice, :signed_up)
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        clean_up_passwords resource
        set_minimum_password_length
        render :new, status: :unprocessable_entity
      end
    end
```

- [ ] **Step 3: Replace the after_sign_up_path_for method**

Replace `after_sign_up_path_for` (currently `def after_sign_up_path_for(_resource); admin_dashboard_path(current_customer_id); end`) with:

```ruby
    def after_sign_up_path_for(_resource)
      "/#{current_customer_id}/member"
    end
```

`after_update_path_for` continues to point at the admin dashboard — that path is reserved for admin profile-update flows. Member profile updates go through `Member::ProfilesController` (Phase 3).

- [ ] **Step 4: Add the assign_member_role! private helper**

Add this method to the `private` section at the bottom of the controller:

```ruby
    # On self-sign-up, attach the per-customer `member` reserved role so the
    # downstream `Authentication::User#member?` predicate returns true and
    # the user can pass the member base controller's `require_member!`.
    # See AGENTS.md "Reserved Roles & Access Rules".
    def assign_member_role!(user)
      role = user.customer.roles.find_or_create_by!(key: "member") do |r|
        r.name = "Member"
        r.system = true
        r.locked_grants = true
      end
      user.users_roles.find_or_create_by!(role: role)
    end
```

- [ ] **Step 5: Verify the change compiles**

Run:

```bash
bin/rails runner "puts Authentication::RegistrationsController.instance_method(:assign_member_role!).source_location.first"
```

Expected: prints the absolute path to the controller file.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/authentication/registrations_controller.rb
git commit -m "feat(auth): assign member role on signup and route to member home"
```

---

### Task 2.7: System specs for auth flows

**Files:**
- Create: `spec/system/member/sign_up_spec.rb`
- Create: `spec/system/member/sign_in_spec.rb`
- Create: `spec/system/member/password_reset_spec.rb`

- [ ] **Step 1: Write the sign-up system spec**

Create `spec/system/member/sign_up_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member sign up", type: :system do
  let(:customer) { create(:customer) }

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: auth_module) { |a| a.status = :active }

    # Opt this customer into self-registration.
    config = FeatureModules::CustomerAssignment.find_by(customer: customer, feature_module: auth_module)
    config.update!(configuration: (config.configuration || {}).merge("allow_registration" => true))
  end

  it "lets a new user register and lands them on the member dashboard" do
    visit "/#{customer.id}/auth/sign_up"

    expect(page).to have_css("[data-shell='member-auth']")
    expect(page).to have_text("Create your account.")

    fill_in "First name", with: "Lin"
    fill_in "Last name",  with: "Vega"
    fill_in "Email",      with: "lin@example.com"
    fill_in "Password",   with: "supersecret123"
    fill_in "Confirm password", with: "supersecret123"
    click_button "Create account"

    expect(page).to have_current_path("/#{customer.id}/member")
    expect(page).to have_text("Welcome.")

    user = Authentication::User.find_by(email: "lin@example.com", customer_id: customer.id)
    expect(user).to be_present
    expect(user.member?).to be true
  end
end
```

- [ ] **Step 2: Write the sign-in system spec**

Create `spec/system/member/sign_in_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member sign in", type: :system do
  let(:customer) { create(:customer) }
  let!(:member)  { create(:user, customer: customer, email: "lin@example.com", password: "supersecret123") }

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: auth_module) { |a| a.status = :active }
  end

  it "renders the member auth shell and signs the user in" do
    visit "/#{customer.id}/auth/sign_in"

    expect(page).to have_css("[data-shell='member-auth']")
    expect(page).to have_text("Welcome back.")

    fill_in "Email",    with: "lin@example.com"
    fill_in "Password", with: "supersecret123"
    click_button "Sign in"

    expect(page).to have_current_path(%r{/#{customer.id}/(admin|member)})
  end

  it "shows an inline error when credentials are wrong" do
    visit "/#{customer.id}/auth/sign_in"
    fill_in "Email",    with: "lin@example.com"
    fill_in "Password", with: "wrong"
    click_button "Sign in"
    expect(page).to have_text(/invalid/i)
  end
end
```

- [ ] **Step 3: Write the password-reset system spec**

Create `spec/system/member/password_reset_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member password reset", type: :system do
  let(:customer) { create(:customer) }
  let!(:member)  { create(:user, customer: customer, email: "lin@example.com") }

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: auth_module) { |a| a.status = :active }
  end

  it "renders the reset request form on the member auth shell" do
    visit "/#{customer.id}/auth/password/new"

    expect(page).to have_css("[data-shell='member-auth']")
    expect(page).to have_text("Forgot password")
    expect(page).to have_button("Send reset link")
  end

  it "accepts a known email and shows the standard Devise notice" do
    visit "/#{customer.id}/auth/password/new"
    fill_in "Email", with: "lin@example.com"
    click_button "Send reset link"

    # Devise's default flash message — we don't intercept it.
    expect(page).to have_text(/email/i)
  end
end
```

- [ ] **Step 4: Run all auth system specs — expect green**

Run:

```bash
bundle exec rspec spec/system/member/sign_up_spec.rb spec/system/member/sign_in_spec.rb spec/system/member/password_reset_spec.rb -fd
```

Expected: 5 examples, 0 failures. If the sign-up spec fails on `allow_registration`, inspect `FeatureModules::Authentication::Registration.config_for` and adjust the `before` block to seed the configuration the same shape that real code reads.

- [ ] **Step 5: Commit**

```bash
git add spec/system/member/
git commit -m "test(member): system coverage for sign-in/sign-up/password-reset on auth shell"
```

---

**Phase 2 checkpoint.** Auth surfaces share the member personality. New users are landed correctly on `/:cid/member` after sign-up, with a `member` role row, and the authorization contract still holds.

---

## Phase 3 — Authenticated pages

### Task 3.1: Create HeroCardComponent and StatusCardComponent

**Files:**
- Create: `app/components/member/hero_card_component.rb`
- Create: `app/components/member/hero_card_component.html.erb`
- Create: `app/components/member/status_card_component.rb`
- Create: `app/components/member/status_card_component.html.erb`
- Test: `spec/components/member/hero_card_component_spec.rb`
- Test: `spec/components/member/status_card_component_spec.rb`

- [ ] **Step 1: Write failing HeroCard spec**

Create `spec/components/member/hero_card_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::HeroCardComponent, type: :component do
  it "renders the greeting, name, and subhead" do
    render_inline(described_class.new(
      greeting: "Good morning", name: "Lin", subhead: "Your membership is active."
    ))

    expect(page).to have_css(".hero-member")
    expect(page).to have_text("Good morning, Lin")
    expect(page).to have_text("Your membership is active.")
  end

  it "renders an optional status badge" do
    render_inline(described_class.new(
      greeting: "Hi", name: "Lin", subhead: "x",
      status: { label: "Active", tone: :success }
    ))

    expect(page).to have_text("Active")
  end
end
```

- [ ] **Step 2: Write failing StatusCard spec**

Create `spec/components/member/status_card_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::StatusCardComponent, type: :component do
  it "renders the label, value, and CTA link" do
    render_inline(described_class.new(
      label: "Profile", value: "Complete", icon: :user,
      cta_label: "Update profile", cta_path: "/123/member/profile"
    ))

    expect(page).to have_text("Profile")
    expect(page).to have_text("Complete")
    expect(page).to have_link("Update profile", href: "/123/member/profile")
  end

  it "renders an icon for the given symbol" do
    render_inline(described_class.new(
      label: "Security", value: "On", icon: :shield_check,
      cta_label: "Manage", cta_path: "/x"
    ))

    expect(page).to have_css("[data-icon='shield_check']")
  end
end
```

- [ ] **Step 3: Run both specs — expect failure**

Run:

```bash
bundle exec rspec spec/components/member/hero_card_component_spec.rb spec/components/member/status_card_component_spec.rb
```

Expected: failures, components don't exist.

- [ ] **Step 4: Create HeroCardComponent class + template**

Create `app/components/member/hero_card_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  class HeroCardComponent < ApplicationComponent
    def initialize(greeting:, name:, subhead:, status: nil)
      @greeting = greeting
      @name     = name
      @subhead  = subhead
      @status   = status
    end

    attr_reader :greeting, :name, :subhead, :status
  end
end
```

Create `app/components/member/hero_card_component.html.erb`:

```erb
<section class="hero-member">
  <div class="flex items-start justify-between gap-6 flex-wrap">
    <div>
      <h1 class="text-display text-white mb-2"><%= greeting %>, <%= name %>.</h1>
      <p class="text-body text-white/85"><%= subhead %></p>
    </div>

    <% if status %>
      <span class="inline-flex items-center gap-1.5 rounded-full bg-white/15 backdrop-blur ring-1 ring-white/20 px-3 py-1 text-xs font-medium text-white">
        <span class="h-2 w-2 rounded-full bg-white"></span>
        <%= status[:label] %>
      </span>
    <% end %>
  </div>
</section>
```

- [ ] **Step 5: Create StatusCardComponent class + template**

Create `app/components/member/status_card_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  class StatusCardComponent < ApplicationComponent
    def initialize(label:, value:, icon:, cta_label:, cta_path:, tone: :default)
      @label     = label
      @value     = value
      @icon      = icon
      @cta_label = cta_label
      @cta_path  = cta_path
      @tone      = tone
    end

    attr_reader :label, :value, :icon, :cta_label, :cta_path, :tone

    def value_class
      case tone
      when :success then "text-success"
      when :warning then "text-warning"
      else               "text-text-primary"
      end
    end
  end
end
```

Create `app/components/member/status_card_component.html.erb`:

```erb
<article class="card-member-elevated flex flex-col gap-4">
  <div class="flex items-center gap-3">
    <span class="inline-flex h-9 w-9 items-center justify-center rounded-lg bg-member-accent-subtle text-member-accent-text" data-icon="<%= icon %>">
      <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <% case icon %>
        <% when :user %>
          <path stroke-linecap="round" stroke-linejoin="round" d="M16 14a4 4 0 10-8 0M12 11a3 3 0 100-6 3 3 0 000 6zM4 21a8 8 0 0116 0"/>
        <% when :credit_card %>
          <path stroke-linecap="round" stroke-linejoin="round" d="M2 8h20M2 12h20M5 6h14a3 3 0 013 3v6a3 3 0 01-3 3H5a3 3 0 01-3-3V9a3 3 0 013-3z"/>
        <% when :shield_check %>
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3zM9 12l2 2 4-4"/>
        <% else %>
          <circle cx="12" cy="12" r="9"/>
        <% end %>
      </svg>
    </span>
    <span class="text-label"><%= label %></span>
  </div>

  <p class="text-3xl font-semibold tracking-tight <%= value_class %>"><%= value %></p>

  <%= link_to cta_path, class: "inline-flex items-center gap-1 text-sm font-medium text-member-accent-text hover:underline mt-auto" do %>
    <%= cta_label %>
    <svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M3 10a.75.75 0 01.75-.75h10.638L10.23 5.29a.75.75 0 111.04-1.08l5.5 5.25a.75.75 0 010 1.08l-5.5 5.25a.75.75 0 11-1.04-1.08l4.158-3.96H3.75A.75.75 0 013 10z" clip-rule="evenodd"/></svg>
  <% end %>
</article>
```

- [ ] **Step 6: Run both specs — expect green**

Run:

```bash
bundle exec rspec spec/components/member/hero_card_component_spec.rb spec/components/member/status_card_component_spec.rb
```

Expected: 4 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/components/member/hero_card_component.rb app/components/member/hero_card_component.html.erb app/components/member/status_card_component.rb app/components/member/status_card_component.html.erb spec/components/member/hero_card_component_spec.rb spec/components/member/status_card_component_spec.rb
git commit -m "feat(member): add HeroCard and StatusCard components"
```

---

### Task 3.2: Build the Home page

**Files:**
- Modify: `app/controllers/member/dashboards_controller.rb`
- Modify: `app/views/member/dashboards/show.html.erb`
- Create: `spec/system/member/home_spec.rb`

- [ ] **Step 1: Replace the controller**

Replace the entire body of `app/controllers/member/dashboards_controller.rb` with:

```ruby
# frozen_string_literal: true

module Member
  class DashboardsController < BaseController
    def show
      @greeting       = greeting_for(Time.zone.now)
      @recent_signins = recent_signins
      @payments_enabled = FeatureModules::Module.enabled?(
        key: "payments", customer_id: current_user.customer_id
      )
    end

    private

    def greeting_for(time)
      case time.hour
      when 5..11  then "Good morning"
      when 12..17 then "Good afternoon"
      else             "Good evening"
      end
    end

    def recent_signins
      [
        { at: current_user.last_sign_in_at, ip: current_user.last_sign_in_ip },
        { at: current_user.current_sign_in_at, ip: current_user.current_sign_in_ip }
      ].select { |row| row[:at].present? }.uniq.first(5)
    end
  end
end
```

- [ ] **Step 2: Replace the view**

Replace `app/views/member/dashboards/show.html.erb` with:

```erb
<% content_for :title, "Home — Anysys" %>
<% content_for :member_nav, "home" %>

<%= render Member::HeroCardComponent.new(
      greeting: @greeting,
      name:     current_user.first_name,
      subhead:  "Manage your account, payments, and security from one place.",
      status:   { label: "Active", tone: :success }
    ) %>

<section class="grid grid-cols-1 md:grid-cols-3 gap-4 mt-6">
  <%= render Member::StatusCardComponent.new(
        label: "Profile",
        value: "Complete",
        icon:  :user,
        cta_label: "Update profile",
        cta_path:  "/#{current_user.customer_id}/member/profile",
        tone: :success
      ) %>

  <% if @payments_enabled %>
    <%= render Member::StatusCardComponent.new(
          label: "Payments",
          value: "View activity",
          icon:  :credit_card,
          cta_label: "View all",
          cta_path:  "/#{current_user.customer_id}/member/payments"
        ) %>
  <% end %>

  <%= render Member::StatusCardComponent.new(
        label: "Security",
        value: current_user.mfa_required? ? "2FA on" : "2FA off",
        icon:  :shield_check,
        cta_label: "Manage security",
        cta_path:  "/#{current_user.customer_id}/member/security",
        tone: current_user.mfa_required? ? :success : :warning
      ) %>
</section>

<section class="mt-8">
  <h2 class="section-header mb-3">Recent activity</h2>

  <% if @recent_signins.empty? %>
    <div class="card-member-elevated text-center py-10">
      <p class="text-body-sm">Welcome — your activity will show up here as you use the portal.</p>
    </div>
  <% else %>
    <ul class="card-member-elevated divide-y divide-border-subtle p-0 overflow-hidden">
      <% @recent_signins.each do |row| %>
        <li class="flex items-center justify-between px-5 py-3">
          <div>
            <p class="text-sm font-medium text-text-primary">Signed in</p>
            <p class="text-xs text-text-tertiary"><%= time_ago_in_words(row[:at]) %> ago — <%= row[:ip] %></p>
          </div>
          <span class="badge badge-success">success</span>
        </li>
      <% end %>
    </ul>
  <% end %>
</section>
```

- [ ] **Step 3: Write the home system spec**

Create `spec/system/member/home_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member home", type: :system do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, first_name: "Lin", last_name: "Vega") }

  before { sign_in user }

  it "renders the hero, status cards, and recent activity for a member" do
    visit "/#{customer.id}/member"

    expect(page).to have_css(".hero-member")
    expect(page).to have_text("Lin.")
    expect(page).to have_text("Profile")
    expect(page).to have_text("Security")
  end

  it "hides the Payments status card when the module is disabled" do
    visit "/#{customer.id}/member"
    expect(page).not_to have_link("View all", href: %r{/payments\z})
  end

  it "shows the Payments status card when the module is enabled" do
    payments_module = FeatureModules::Module.find_or_create_by!(key: "payments") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: payments_module) { |a| a.status = :active }

    visit "/#{customer.id}/member"
    expect(page).to have_link("View all", href: "/#{customer.id}/member/payments")
  end
end
```

- [ ] **Step 4: Run the home spec — expect green**

Run:

```bash
bundle exec rspec spec/system/member/home_spec.rb -fd
```

Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/member/dashboards_controller.rb app/views/member/dashboards/show.html.erb spec/system/member/home_spec.rb
git commit -m "feat(member): build Home page with hero, status row, recent activity"
```

---

### Task 3.3: Build the Profile show + edit pages with a Reform contract

**Files:**
- Create: `app/controllers/member/profiles_controller.rb`
- Create: `app/contracts/member/profiles/update_contract.rb`
- Create: `app/views/member/profiles/show.html.erb`
- Create: `app/views/member/profiles/edit.html.erb`
- Test: `spec/contracts/member/profiles/update_contract_spec.rb`
- Test: `spec/system/member/profile_spec.rb`

- [ ] **Step 1: Write the failing contract spec**

Create `spec/contracts/member/profiles/update_contract_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Profiles::UpdateContract do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }

  it "validates first_name presence and length" do
    contract = described_class.new(user)
    expect(contract.validate(first_name: "", last_name: user.last_name, email: user.email)).to be false
    expect(contract.errors[:first_name]).to include(/blank/i)

    contract = described_class.new(user)
    expect(contract.validate(first_name: "x" * 51, last_name: user.last_name, email: user.email)).to be false
    expect(contract.errors[:first_name]).to include(/too long/i)
  end

  it "validates email format and uniqueness scoped to the customer" do
    create(:user, customer: customer, email: "taken@example.com")
    contract = described_class.new(user)
    expect(contract.validate(first_name: "Lin", last_name: "Vega", email: "taken@example.com")).to be false
    expect(contract.errors[:email]).to be_present
  end

  it "accepts a valid payload and saves" do
    contract = described_class.new(user)
    expect(contract.validate(first_name: "Lin", last_name: "Vega", email: "lin@example.com")).to be true
    contract.save
    expect(user.reload.email).to eq("lin@example.com")
  end
end
```

- [ ] **Step 2: Run the spec — expect failure**

Run:

```bash
bundle exec rspec spec/contracts/member/profiles/update_contract_spec.rb
```

Expected: failure, contract does not exist.

- [ ] **Step 3: Create the Reform contract**

Create `app/contracts/member/profiles/update_contract.rb`:

```ruby
# frozen_string_literal: true

require "reform/form"

module Member
  module Profiles
    # Reform contract for member self-service profile updates. Mirrors
    # Authentication::User's validations so behavior is consistent whether
    # the user updates via Devise or this contract.
    class UpdateContract < Reform::Form
      property :first_name
      property :last_name
      property :email

      validates :first_name, presence: true, length: { maximum: 50 }
      validates :last_name,  presence: true, length: { maximum: 50 }
      validates :email,      presence: true,
                             format: { with: URI::MailTo::EMAIL_REGEXP }

      validate :email_unique_within_customer

      private

      def email_unique_within_customer
        return if email.blank?

        scope = ::Authentication::User
                  .where(customer_id: model.customer_id)
                  .where("LOWER(email) = ?", email.to_s.downcase.strip)
        scope = scope.where.not(id: model.id) if model.persisted?
        errors.add(:email, "is already taken") if scope.exists?
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec — expect green**

Run:

```bash
bundle exec rspec spec/contracts/member/profiles/update_contract_spec.rb
```

Expected: 3 examples, 0 failures.

- [ ] **Step 5: Create the controller**

Create `app/controllers/member/profiles_controller.rb`:

```ruby
# frozen_string_literal: true

module Member
  class ProfilesController < BaseController
    def show
    end

    def edit
      @contract = Member::Profiles::UpdateContract.new(current_user)
    end

    def update
      @contract = Member::Profiles::UpdateContract.new(current_user)

      if @contract.validate(profile_params) && @contract.save
        redirect_to "/#{current_user.customer_id}/member/profile",
                    notice: "Profile updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:member_profiles_update_contract)
            .permit(:first_name, :last_name, :email)
    end
  end
end
```

- [ ] **Step 6: Create the show view**

Create `app/views/member/profiles/show.html.erb`:

```erb
<% content_for :title, "Profile — Anysys" %>
<% content_for :member_nav, "profile" %>

<header class="mb-8">
  <h1 class="text-title">Profile</h1>
  <p class="text-body-sm">Your account information.</p>
</header>

<section class="card-member-elevated">
  <div class="flex items-center gap-5 mb-8">
    <span class="inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-member-accent to-member-accent-hover text-white text-xl font-semibold">
      <%= "#{current_user.first_name[0]}#{current_user.last_name[0]}".upcase %>
    </span>
    <div>
      <h2 class="text-heading"><%= current_user.display_name %></h2>
      <p class="text-body-sm"><%= current_user.email %></p>
    </div>
  </div>

  <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-5">
    <div>
      <dt class="text-label">First name</dt>
      <dd class="text-body mt-1"><%= current_user.first_name %></dd>
    </div>
    <div>
      <dt class="text-label">Last name</dt>
      <dd class="text-body mt-1"><%= current_user.last_name %></dd>
    </div>
    <div>
      <dt class="text-label">Email</dt>
      <dd class="text-body mt-1"><%= current_user.email %></dd>
    </div>
    <div>
      <dt class="text-label">Member since</dt>
      <dd class="text-body mt-1"><%= l(current_user.created_at.to_date, format: :long) %></dd>
    </div>
  </dl>

  <div class="mt-8 flex items-center gap-3">
    <%= link_to "Edit profile", "/#{current_user.customer_id}/member/profile/edit",
          class: "btn-member" %>
    <%= link_to "Sign out", "/#{current_user.customer_id}/auth/sign_out",
          data: { turbo_method: :delete },
          class: "btn btn-ghost" %>
  </div>
</section>
```

- [ ] **Step 7: Create the edit view**

Create `app/views/member/profiles/edit.html.erb`:

```erb
<% content_for :title, "Edit profile — Anysys" %>
<% content_for :member_nav, "profile" %>

<header class="mb-8">
  <h1 class="text-title">Edit profile</h1>
  <p class="text-body-sm">Update your name or email.</p>
</header>

<section class="card-member-elevated">
  <%= form_with model: @contract,
        url:    "/#{current_user.customer_id}/member/profile",
        scope:  :member_profiles_update_contract,
        method: :patch,
        class:  "space-y-5" do |f| %>

    <% if @contract.errors.any? %>
      <div class="rounded-lg bg-danger-subtle border border-danger/20 p-3">
        <ul class="text-sm text-danger list-disc pl-5 space-y-1">
          <% @contract.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <div>
        <%= f.label :first_name, class: "form-label form-label-required" %>
        <%= f.text_field :first_name, value: current_user.first_name, class: "input-field" %>
      </div>
      <div>
        <%= f.label :last_name, class: "form-label form-label-required" %>
        <%= f.text_field :last_name, value: current_user.last_name, class: "input-field" %>
      </div>
    </div>

    <div>
      <%= f.label :email, class: "form-label form-label-required" %>
      <%= f.email_field :email, value: current_user.email, class: "input-field" %>
    </div>

    <div class="flex items-center gap-3 pt-2">
      <%= f.submit "Save changes", class: "btn-member" %>
      <%= link_to "Cancel", "/#{current_user.customer_id}/member/profile",
            class: "btn btn-ghost" %>
    </div>
  <% end %>
</section>
```

- [ ] **Step 8: Write the profile system spec**

Create `spec/system/member/profile_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member profile", type: :system do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, first_name: "Lin", last_name: "Vega") }

  before { sign_in user }

  it "renders the show page with the user's data" do
    visit "/#{customer.id}/member/profile"
    expect(page).to have_text("Lin Vega")
    expect(page).to have_text(user.email)
    expect(page).to have_link("Edit profile")
  end

  it "updates first and last name from the edit form" do
    visit "/#{customer.id}/member/profile/edit"
    fill_in "First name", with: "Linnea"
    click_button "Save changes"

    expect(page).to have_current_path("/#{customer.id}/member/profile")
    expect(page).to have_text("Profile updated.")
    expect(page).to have_text("Linnea Vega")
  end

  it "shows validation errors when fields are blank" do
    visit "/#{customer.id}/member/profile/edit"
    fill_in "First name", with: ""
    click_button "Save changes"

    expect(page).to have_text(/can't be blank/i)
  end
end
```

- [ ] **Step 9: Run the spec — expect green**

Run:

```bash
bundle exec rspec spec/system/member/profile_spec.rb spec/contracts/member/profiles/update_contract_spec.rb -fd
```

Expected: 6 examples, 0 failures.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/member/profiles_controller.rb app/contracts/member/ app/views/member/profiles/ spec/contracts/member/ spec/system/member/profile_spec.rb
git commit -m "feat(member): profile show + edit with Reform update contract"
```

---

### Task 3.4: Build the Security page

**Files:**
- Create: `app/controllers/member/securities_controller.rb`
- Create: `app/views/member/securities/show.html.erb`
- Create: `spec/system/member/security_spec.rb`

- [ ] **Step 1: Create the controller**

Create `app/controllers/member/securities_controller.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Security center. A composition page over existing auth surfaces — does
  # not introduce new endpoints. Links out to Devise password reset and
  # the existing /:cid/auth/mfa/* MFA flows.
  class SecuritiesController < BaseController
    def show
      @mfa_enabled = current_user.mfa_required?
      @last_signin = {
        at: current_user.last_sign_in_at,
        ip: current_user.last_sign_in_ip
      }
    end
  end
end
```

- [ ] **Step 2: Create the view**

Create `app/views/member/securities/show.html.erb`:

```erb
<% content_for :title, "Security — Anysys" %>
<% content_for :member_nav, "security" %>

<header class="mb-8">
  <h1 class="text-title">Security</h1>
  <p class="text-body-sm">Manage your password and two-factor authentication.</p>
</header>

<div class="space-y-4">

  <section class="card-member-elevated">
    <div class="flex items-start justify-between gap-6 flex-wrap">
      <div>
        <h2 class="text-heading mb-1">Password</h2>
        <p class="text-body-sm">Replace your password with a new one. We'll email you a reset link.</p>
      </div>
      <%= link_to "Change password",
            new_user_password_path(customer_id: current_user.customer_id),
            class: "btn-member" %>
    </div>
  </section>

  <section class="card-member-elevated">
    <div class="flex items-start justify-between gap-6 flex-wrap">
      <div class="flex items-start gap-4">
        <span class="inline-flex h-9 w-9 items-center justify-center rounded-lg <%= @mfa_enabled ? 'bg-success-subtle text-success' : 'bg-warning-subtle text-warning' %>">
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z"/>
          </svg>
        </span>
        <div>
          <h2 class="text-heading mb-1">Two-factor authentication</h2>
          <p class="text-body-sm">
            <% if @mfa_enabled %>
              2FA is on. You'll be prompted for a code on every sign-in.
            <% else %>
              2FA is off. We strongly recommend turning it on.
            <% end %>
          </p>
        </div>
      </div>

      <% if @mfa_enabled %>
        <%= button_to "Disable 2FA",
              "/#{current_user.customer_id}/auth/mfa",
              method: :delete,
              class: "btn btn-ghost text-danger",
              data: { confirm: "Disable two-factor authentication for your account?" } %>
      <% else %>
        <%= link_to "Set up 2FA",
              "/#{current_user.customer_id}/auth/mfa/setup",
              class: "btn-member" %>
      <% end %>
    </div>
  </section>

  <section class="card-member-elevated">
    <h2 class="text-heading mb-3">Last sign-in</h2>
    <% if @last_signin[:at] %>
      <dl class="grid grid-cols-2 gap-y-2 max-w-md">
        <dt class="text-label">When</dt>
        <dd class="text-body-sm"><%= l(@last_signin[:at], format: :long) %></dd>
        <dt class="text-label">From IP</dt>
        <dd class="text-body-sm font-mono"><%= @last_signin[:ip] || "unknown" %></dd>
      </dl>
    <% else %>
      <p class="text-body-sm">No sign-in history yet.</p>
    <% end %>
  </section>
</div>
```

- [ ] **Step 3: Write the security system spec**

Create `spec/system/member/security_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member security", type: :system do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }

  before { sign_in user }

  it "renders the password section linking to the password reset flow" do
    visit "/#{customer.id}/member/security"
    expect(page).to have_text("Password")
    expect(page).to have_link("Change password",
      href: new_user_password_path(customer_id: customer.id))
  end

  it "shows the 2FA off state and a setup CTA when MFA is disabled" do
    visit "/#{customer.id}/member/security"
    expect(page).to have_text("2FA is off")
    expect(page).to have_link("Set up 2FA", href: "/#{customer.id}/auth/mfa/setup")
  end

  it "shows the 2FA on state and a disable button when MFA is enabled" do
    user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    visit "/#{customer.id}/member/security"
    expect(page).to have_text("2FA is on")
    expect(page).to have_button("Disable 2FA")
  end
end
```

- [ ] **Step 4: Run the spec — expect green**

Run:

```bash
bundle exec rspec spec/system/member/security_spec.rb -fd
```

Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/member/securities_controller.rb app/views/member/securities/ spec/system/member/security_spec.rb
git commit -m "feat(member): build Security page composing existing auth/MFA surfaces"
```

---

**Phase 3 checkpoint.** Authenticated members have a real Home, Profile show/edit, and Security page. Profile edits flow through a Reform contract per project convention.

---

## Phase 4 — Payments

### Task 4.1: Add user_id to payments

**Files:**
- Create: `db/migrate/<TIMESTAMP>_add_user_id_to_payments.rb`
- Modify: `app/models/payments/payment.rb`

- [ ] **Step 1: Generate the migration**

Run:

```bash
bin/rails generate migration AddUserIdToPayments user:references
```

Expected: a new file under `db/migrate/` named `<TIMESTAMP>_add_user_id_to_payments.rb`.

- [ ] **Step 2: Open the generated migration and replace its contents**

Replace the migration body with:

```ruby
# frozen_string_literal: true

class AddUserIdToPayments < ActiveRecord::Migration[8.1]
  def change
    add_reference :payments, :user, null: true, index: true, foreign_key: { to_table: :users }
  end
end
```

The column is nullable because existing payment rows have no associated user (vendor webhooks, system flows). Going forward, payments initiated by a member through the member portal will populate `user_id`.

- [ ] **Step 3: Run the migration**

Run:

```bash
bin/rails db:migrate
```

Expected: `add_reference(:payments, :user, ...)` runs cleanly. `db/schema.rb` now lists `t.bigint "user_id"` and an index.

- [ ] **Step 4: Update the Payment model**

In `app/models/payments/payment.rb`, find the `belongs_to :payment_order` line (currently lines 12–13) and append a new line below it:

```ruby
    belongs_to :user, optional: true,
                      class_name: "Authentication::User",
                      foreign_key: :user_id
```

The full top of the model now reads:

```ruby
module Payments
  class Payment < ApplicationRecord
    self.table_name = "payments"

    include TenantScoped

    FLOWS    = %w[qr h5 jsapi].freeze
    STATUSES = %w[created pending succeeded failed closed].freeze

    belongs_to :payment_order, class_name: "Payments::Order",
                               foreign_key: :payment_order_id
    belongs_to :user, optional: true,
                      class_name: "Authentication::User",
                      foreign_key: :user_id
    has_many :payment_refunds, dependent: :destroy,
                               class_name: "Payments::Refund",
                               foreign_key: :payment_id
    # ... rest unchanged
```

- [ ] **Step 5: Run the model loading sanity check**

Run:

```bash
bin/rails runner 'p Payments::Payment.reflect_on_association(:user).options'
```

Expected: a hash including `optional: true, class_name: "Authentication::User"`.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/schema.rb app/models/payments/payment.rb
git commit -m "feat(payments): add user_id to payments for member ownership"
```

---

### Task 4.2: Build the Payments index and show pages

**Files:**
- Create: `app/controllers/member/payments_controller.rb`
- Create: `app/views/member/payments/index.html.erb`
- Create: `app/views/member/payments/show.html.erb`
- Test: `spec/requests/member/payments_spec.rb`
- Test: `spec/system/member/payments_spec.rb`

- [ ] **Step 1: Create the controller**

Create `app/controllers/member/payments_controller.rb`:

```ruby
# frozen_string_literal: true

module Member
  class PaymentsController < BaseController
    PER_PAGE = 20

    before_action :require_payments_module!

    def index
      page    = [params[:page].to_i, 1].max
      offset  = (page - 1) * PER_PAGE
      scope   = Payments::Payment.where(
                  customer_id: current_user.customer_id,
                  user_id:     current_user.id
                ).order(created_at: :desc)

      @payments    = scope.limit(PER_PAGE).offset(offset).to_a
      @total_count = scope.count
      @page        = page
      @per_page    = PER_PAGE
    end

    def show
      @payment = Payments::Payment.find_by(id: params[:id])
      authorize_owned!(@payment)
    end

    private

    def require_payments_module!
      return if FeatureModules::Module.enabled?(
        key: "payments", customer_id: current_user.customer_id
      )

      raise ActiveRecord::RecordNotFound
    end
  end
end
```

- [ ] **Step 2: Create the index view**

Create `app/views/member/payments/index.html.erb`:

```erb
<% content_for :title, "Payments — Anysys" %>
<% content_for :member_nav, "payments" %>

<header class="mb-8 flex items-end justify-between flex-wrap gap-4">
  <div>
    <h1 class="text-title">Payments</h1>
    <p class="text-body-sm">A history of payments tied to your account.</p>
  </div>
  <% if @total_count.positive? %>
    <span class="badge badge-default"><%= @total_count %> total</span>
  <% end %>
</header>

<% if @payments.empty? %>
  <section class="card-member-elevated text-center py-14">
    <span class="inline-flex h-12 w-12 items-center justify-center rounded-full bg-member-accent-subtle text-member-accent-text mb-3">
      <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M2 8h20M2 12h20M5 6h14a3 3 0 013 3v6a3 3 0 01-3 3H5a3 3 0 01-3-3V9a3 3 0 013-3z"/>
      </svg>
    </span>
    <h2 class="text-heading mb-1">No payments yet</h2>
    <p class="text-body-sm">Your payment history will appear here.</p>
  </section>
<% else %>
  <section class="card-member-elevated p-0 overflow-hidden">
    <table class="min-w-full divide-y divide-border-subtle">
      <thead class="table-header">
        <tr>
          <th class="px-5 py-3 text-left">Date</th>
          <th class="px-5 py-3 text-left">Vendor</th>
          <th class="px-5 py-3 text-right">Amount</th>
          <th class="px-5 py-3 text-left">Status</th>
          <th class="px-5 py-3"></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-border-subtle">
        <% @payments.each do |payment| %>
          <tr class="table-row">
            <td class="px-5 py-3 text-body-sm"><%= l(payment.created_at.to_date, format: :long) %></td>
            <td class="px-5 py-3 text-body-sm"><%= payment.provider.titleize %></td>
            <td class="px-5 py-3 text-right text-body-sm font-mono"><%= number_to_currency(payment.amount_cents / 100.0) %></td>
            <td class="px-5 py-3"><span class="badge badge-<%= payment.status == 'succeeded' ? 'success' : 'default' %>"><%= payment.status %></span></td>
            <td class="px-5 py-3 text-right">
              <%= link_to "View →",
                    "/#{current_user.customer_id}/member/payments/#{payment.id}",
                    class: "text-sm font-medium text-member-accent-text hover:underline" %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>

  <% if @total_count > @per_page %>
    <nav class="mt-5 flex items-center justify-between text-sm text-text-secondary">
      <span>
        Showing <%= ((@page - 1) * @per_page) + 1 %>–<%= [@page * @per_page, @total_count].min %> of <%= @total_count %>
      </span>
      <div class="flex items-center gap-2">
        <% if @page > 1 %>
          <%= link_to "← Previous",
                url_for(page: @page - 1),
                class: "btn btn-ghost" %>
        <% end %>
        <% if @page * @per_page < @total_count %>
          <%= link_to "Next →",
                url_for(page: @page + 1),
                class: "btn btn-ghost" %>
        <% end %>
      </div>
    </nav>
  <% end %>
<% end %>
```

- [ ] **Step 3: Create the show view**

Create `app/views/member/payments/show.html.erb`:

```erb
<% content_for :title, "Payment — Anysys" %>
<% content_for :member_nav, "payments" %>

<nav class="mb-6">
  <%= link_to "← Back to payments",
        "/#{current_user.customer_id}/member/payments",
        class: "text-sm font-medium text-member-accent-text hover:underline" %>
</nav>

<header class="mb-8 flex items-end justify-between flex-wrap gap-4">
  <div>
    <h1 class="text-title">Payment <span class="font-mono text-text-tertiary"><%= @payment.out_trade_no %></span></h1>
    <p class="text-body-sm">Created <%= l(@payment.created_at, format: :long) %></p>
  </div>
  <span class="badge badge-<%= @payment.status == 'succeeded' ? 'success' : 'default' %> text-base px-3 py-1.5"><%= @payment.status %></span>
</header>

<section class="card-member-elevated">
  <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-6">
    <div>
      <dt class="text-label">Amount</dt>
      <dd class="text-3xl font-semibold mt-1 font-mono"><%= number_to_currency(@payment.amount_cents / 100.0) %></dd>
    </div>
    <div>
      <dt class="text-label">Vendor</dt>
      <dd class="text-body mt-1"><%= @payment.provider.titleize %></dd>
    </div>
    <div>
      <dt class="text-label">Flow</dt>
      <dd class="text-body mt-1"><%= @payment.flow.upcase %></dd>
    </div>
    <% if @payment.paid_at %>
      <div>
        <dt class="text-label">Paid at</dt>
        <dd class="text-body mt-1"><%= l(@payment.paid_at, format: :long) %></dd>
      </div>
    <% end %>
    <% if @payment.psp_transaction_id %>
      <div class="sm:col-span-2">
        <dt class="text-label">PSP transaction id</dt>
        <dd class="text-body mt-1 font-mono break-all"><%= @payment.psp_transaction_id %></dd>
      </div>
    <% end %>
  </dl>

  <% if @payment.payment_refunds.any? %>
    <div class="mt-8 pt-8 border-t border-border-subtle">
      <h2 class="section-header mb-3">Refunds</h2>
      <ul class="divide-y divide-border-subtle">
        <% @payment.payment_refunds.each do |refund| %>
          <li class="py-3 flex items-center justify-between">
            <span class="text-body-sm"><%= l(refund.created_at, format: :long) %></span>
            <span class="text-body-sm font-mono"><%= number_to_currency(refund.amount_cents / 100.0) %></span>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>
</section>
```

- [ ] **Step 4: Write the request spec**

Create `spec/requests/member/payments_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member payments", type: :request do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }
  let(:other_user) { create(:user, customer: customer) }

  let(:payments_module) do
    FeatureModules::Module.find_or_create_by!(key: "payments") { |m| m.name = "Payments" }
  end

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: auth_module) { |a| a.status = :active }
    sign_in user
  end

  context "when the payments module is disabled" do
    it "returns 404 on index" do
      get "/#{customer.id}/member/payments"
      expect(response).to have_http_status(:not_found)
    end
  end

  context "when the payments module is enabled" do
    before do
      FeatureModules::CustomerAssignment.find_or_create_by!(
        customer: customer, feature_module: payments_module
      ) { |a| a.status = :active }
    end

    it "lists only the current user's payments" do
      mine   = build_payment(user: user, customer: customer, amount_cents: 1_000)
      theirs = build_payment(user: other_user, customer: customer, amount_cents: 9_999)
      [mine, theirs].each(&:save!)

      get "/#{customer.id}/member/payments"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(format("%.2f", 10.00))
      expect(response.body).not_to include(format("%.2f", 99.99))
    end

    it "returns 404 when viewing another user's payment by id" do
      theirs = build_payment(user: other_user, customer: customer, amount_cents: 9_999)
      theirs.save!

      get "/#{customer.id}/member/payments/#{theirs.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "renders own payment show" do
      mine = build_payment(user: user, customer: customer, amount_cents: 1_000)
      mine.save!

      get "/#{customer.id}/member/payments/#{mine.id}"
      expect(response).to have_http_status(:ok)
    end
  end

  def build_payment(user:, customer:, amount_cents:)
    order = Payments::Order.create!(
      customer_id: customer.id,
      external_ref: "test-#{SecureRandom.hex(4)}",
      subject: "Test",
      amount_cents: amount_cents
    )
    Payments::Payment.new(
      customer_id: customer.id,
      user_id:     user.id,
      payment_order_id: order.id,
      provider:    "alipay",
      flow:        "qr",
      out_trade_no: "TXN-#{SecureRandom.hex(6)}",
      amount_cents: amount_cents,
      status:      "succeeded"
    )
  end
end
```

- [ ] **Step 5: Run the request spec — expect green**

Run:

```bash
bundle exec rspec spec/requests/member/payments_spec.rb -fd
```

Expected: 4 examples, 0 failures. If `Payments::Order` validations need additional fields beyond what `build_payment` supplies, inspect the order model and update the helper to set them — keep the helper minimal but valid.

- [ ] **Step 6: Write a thin system spec**

Create `spec/system/member/payments_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member payments page", type: :system do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }

  before do
    payments_module = FeatureModules::Module.find_or_create_by!(key: "payments") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(customer: customer, feature_module: payments_module) { |a| a.status = :active }
    sign_in user
  end

  it "renders the empty state when the user has no payments" do
    visit "/#{customer.id}/member/payments"
    expect(page).to have_text("No payments yet")
  end
end
```

- [ ] **Step 7: Run the system spec — expect green**

Run:

```bash
bundle exec rspec spec/system/member/payments_spec.rb -fd
```

Expected: 1 example, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/member/payments_controller.rb app/views/member/payments/ spec/requests/member/payments_spec.rb spec/system/member/payments_spec.rb
git commit -m "feat(member): payments index + show, scoped to current user, module-gated"
```

---

**Phase 4 checkpoint.** Members can browse only their own payment records. Direct access to other users' payments returns 404. The page is hidden from the nav and returns 404 when the Payments module is not enabled for the customer.

---

## Final integration check

### Task 5.1: Run the full member test suite

- [ ] **Step 1: Run all new specs**

Run:

```bash
bundle exec rspec spec/services/member/ spec/contracts/member/ spec/components/member/ spec/requests/member/ spec/system/member/ -fd
```

Expected: every example green; no skipped or pending examples.

- [ ] **Step 2: Run the full project suite for regressions**

Run:

```bash
bundle exec rspec 2>&1 | tail -30
```

Expected: same pass/fail count as before this plan started, plus all new examples passing. Investigate any newly-failing examples in unrelated files before declaring done.

- [ ] **Step 3: Manual smoke check**

```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

Visit (in a browser) — using a real customer id from the database:

- `/<cid>/auth/sign_in` — verify the new auth shell renders
- `/<cid>/auth/sign_up` — verify the sign-up form renders
- `/<cid>/member` — verify the home dashboard renders (you may need to grant the test user the `member` role and not the `admin`)
- `/<cid>/member/profile` — verify show + edit
- `/<cid>/member/security` — verify the three sections render
- `/<cid>/member/payments` — verify either empty state or table

Stop the server with `kill %1`.

---

## Self-Review

### Spec coverage check

| Spec section | Plan task |
|---|---|
| §3 Industry-standard reference shape | 1.2 (registry), 1.3 (base controller), 1.4–1.5 (shell components) |
| §4.1 Two parallel shells | 1.4 + 2.2 |
| §4.2 Controller layout | 1.3, 3.3, 3.4, 4.2 |
| §4.3 View component layout | 1.4, 1.5, 2.1, 3.1 |
| §4.4 Navigation as data | 1.2 |
| §5.1 Page inventory | 2.3–2.5 (auth) + 3.2–3.4 + 4.2 |
| §5.2 Sign in | 2.3 |
| §5.3 Sign up + member role + redirect | 2.4 + 2.6 |
| §5.4 Forgot/reset password | 2.5 |
| §5.5 Home | 3.2 |
| §5.6 Profile show + edit + Reform contract | 3.3 |
| §5.7 Security | 3.4 |
| §5.8 My Payments | 4.1, 4.2 |
| §6 Routes | 1.3 (route block) |
| §7.1–7.3 Three-gate authz | 1.3 (BaseController) |
| §7.4 Test contract | 1.3 (`base_authorization_spec.rb`) |
| §8 Styling | 1.1 |
| §9 Component contracts | 1.4, 1.5, 2.1, 3.1 |
| §10 Reform contract | 3.3 |
| §11 Testing convention | every Phase has accompanying specs |
| §12 Phases | this plan's structure |
| §13 Risks | addressed inline (registration role, customer state, module-disabled UX, mobile gestures, i18n) |
| §14 Acceptance criteria | covered by Final integration check |

No gaps detected.

### Type/signature consistency

- `Member::Navigation::Item.path_for(customer)` is called by `TopNavComponent#nav_items` template (1.5) and matches the definition in 1.2.
- `Member::BaseController#authorize_owned!` is called by `Member::PaymentsController#show` (4.2) with the same signature defined in 1.3.
- `Member::Profiles::UpdateContract` is constructed with a User in both 3.3 controller and contract spec.
- `Member::ShellComponent` props (`customer:`, `user:`, `current_nav:`, `container_width:`) are consistent across 1.4 (definition), 1.4 layout (consumption with default-value fallbacks), and component spec.

No mismatches detected.

### Placeholder scan

- No "TBD" / "TODO" / "implement later" entries.
- Every step that changes code includes the full code.
- Every command has expected output.
- Every spec example has concrete assertions.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-15-member-skeleton.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
