# Generic Module Host-Integration Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace module-specific integration plumbing (`AuthenticationEnforceable`, hard-coded auth blocks in the shared layout, manual `register!` calls) with generic, module-agnostic surfaces so any future feature module can plug into per-request hooks, layout navigation, and registration without touching the integration layer.

**Architecture:**
- **Generic enablement API** — `FeatureModule.enabled?(key:, customer_id:)` becomes the single read-side entry point; auth-specific `enabled_for?` / `config_for` shims are removed.
- **Generic per-request hook** — `FeatureModules::BaseModule.before_request(controller)` (no-op by default) is invoked for every enabled module by a new `FeatureModules::HostIntegration` controller concern. The auth module moves its session/MFA enforcement into that hook.
- **Generic nav contribution** — `BaseModule.nav_items_for(controller, section:)` returns nav items per section (`:primary`, `:user_menu`). A `FeatureModules::NavContributionsComponent` ViewComponent renders whatever enabled modules contribute.
- **Auto-discovered registration** — `config/initializers/feature_modules.rb` scans `app/services/feature_modules/*/registration.rb` instead of hard-coding module names.

**Tech Stack:** Rails 8.1, Ruby 3.2, RSpec, ViewComponent, TailwindCSS, Reform (already present). No new gems.

**Commit policy:** Per user preference, the USER commits manually. Commit steps in this plan mean "pause and let the user review the diff before moving on" — do not run `git commit` from the agent.

---

## File Structure

**New files:**
- `app/controllers/concerns/feature_modules/host_integration.rb` — generic controller concern
- `app/components/feature_modules/nav_contributions_component.rb` — ViewComponent class
- `app/components/feature_modules/nav_contributions_component.html.erb` — template
- `app/services/feature_modules/nav_item.rb` — value object for nav contributions
- `spec/controllers/concerns/feature_modules/host_integration_spec.rb`
- `spec/components/feature_modules/nav_contributions_component_spec.rb`
- `spec/services/feature_modules/nav_item_spec.rb`

**Modified files:**
- `app/models/feature_module.rb` — add `enabled?` class method + `enabled_for_customer` scope
- `app/services/feature_modules/base_module.rb` — add `before_request` and `nav_items_for` default no-op hooks
- `app/services/feature_modules/authentication/registration.rb` — implement `before_request` + `nav_items_for`, remove `enabled_for?` (callers migrated to `FeatureModule.enabled?`)
- `app/controllers/application_controller.rb` — swap `AuthenticationEnforceable` → `FeatureModules::HostIntegration`
- `app/controllers/authentication/passwords_controller.rb`, `sessions_controller.rb`, `registrations_controller.rb`, `mfa_controller.rb`, `authentication/admin/users_controller.rb` (if present) — use generic `FeatureModule.enabled?`
- `app/views/layouts/application.html.erb` — replace hard-coded auth blocks with `render FeatureModules::NavContributionsComponent.new(...)`
- `config/initializers/feature_modules.rb` — auto-discovery glob
- `spec/models/feature_module_spec.rb` — specs for new class method + scope
- `spec/services/feature_modules/authentication/registration_spec.rb` — specs for `before_request` + `nav_items_for`; remove `enabled_for?` / `config_for` specs that test removed shims
- `spec/services/feature_modules/base_module_spec.rb` — specs for default hooks

**Deleted files:**
- `app/controllers/concerns/authentication_enforceable.rb`
- `spec/controllers/concerns/authentication_enforceable_spec.rb` (if it exists — appears not to)

---

### Task 1: Add generic `FeatureModule.enabled?` API and `enabled_for_customer` scope

**Why:** Single module-agnostic read API. Every integration point (controllers, views, concern) uses this instead of reaching into `FeatureModules::Authentication::Registration.enabled_for?`.

**Files:**
- Modify: `app/models/feature_module.rb` (add method, ~line 50)
- Modify: `spec/models/feature_module_spec.rb`

- [ ] **Step 1: Write the failing specs**

Append to `spec/models/feature_module_spec.rb` (inside the top-level `RSpec.describe FeatureModule do` block; if unsure where, place before the final `end`):

```ruby
  describe ".enabled?" do
    let(:customer) { create(:customer) }
    let(:module_record) { FeatureModule.find_by!(key: "authentication") }

    it "returns true when an active CustomerFeatureModule row exists" do
      expect(described_class.enabled?(key: "authentication", customer_id: customer.id)).to be true
    end

    it "returns false when the module is suspended for the customer" do
      cfm = CustomerFeatureModule.find_by!(customer: customer, feature_module: module_record)
      cfm.update!(status: :suspended)
      expect(described_class.enabled?(key: "authentication", customer_id: customer.id)).to be false
    end

    it "returns false when the module has no CustomerFeatureModule row for the customer" do
      CustomerFeatureModule.where(customer: customer, feature_module: module_record).destroy_all
      expect(described_class.enabled?(key: "authentication", customer_id: customer.id)).to be false
    end

    it "returns false when the module key does not exist" do
      expect(described_class.enabled?(key: "nonexistent_module", customer_id: customer.id)).to be false
    end

    it "returns false when customer_id is blank" do
      expect(described_class.enabled?(key: "authentication", customer_id: nil)).to be false
    end
  end

  describe ".enabled_for_customer scope" do
    let(:customer) { create(:customer) }

    it "returns modules with an active CustomerFeatureModule row for the given customer" do
      keys = described_class.enabled_for_customer(customer.id).pluck(:key)
      expect(keys).to include("authentication")
    end

    it "excludes modules with suspended CustomerFeatureModule rows" do
      auth_module = FeatureModule.find_by!(key: "authentication")
      CustomerFeatureModule.find_by!(customer: customer, feature_module: auth_module)
        .update!(status: :suspended)
      keys = described_class.enabled_for_customer(customer.id).pluck(:key)
      expect(keys).not_to include("authentication")
    end

    it "returns an empty relation when customer_id is blank" do
      expect(described_class.enabled_for_customer(nil).to_a).to eq([])
    end
  end
```

- [ ] **Step 2: Run and confirm failure**

Run: `bundle exec rspec spec/models/feature_module_spec.rb -e "enabled?" -e "enabled_for_customer" 2>&1 | tail -30`
Expected: `NoMethodError: undefined method 'enabled?' for class FeatureModule` (or scope missing).

- [ ] **Step 3: Implement in `app/models/feature_module.rb`**

Inside the `FeatureModule` class, add the scope below the existing `scope :required, ...` line (around line 49) and the class method inside the `# Public Methods` section (before `def registration_class`). Exact insertions:

After `scope :required, -> { where(required: true) }`:
```ruby
  scope :enabled_for_customer, ->(customer_id) {
    return none if customer_id.blank?

    joins(:customer_feature_modules)
      .where(customer_feature_modules: { customer_id: customer_id, status: :active })
  }
```

Before `def registration_class` (inside `# Public Methods`):
```ruby
  # Generic enablement check — module-agnostic.
  # Used by integration layer instead of module-specific enabled_for? shims.
  def self.enabled?(key:, customer_id:)
    return false if customer_id.blank?

    enabled_for_customer(customer_id).exists?(key: key)
  end
```

- [ ] **Step 4: Run and confirm pass**

Run: `bundle exec rspec spec/models/feature_module_spec.rb 2>&1 | tail -10`
Expected: all FeatureModule specs pass.

- [ ] **Step 5: Pause for user to review and commit**

Do not run `git commit`. User will review the diff manually.

---

### Task 2: Add `before_request` and `nav_items_for` hooks to `BaseModule`

**Why:** Generic extension points. Every module's `Registration` can contribute per-request enforcement and nav items without integration-layer changes.

**Files:**
- Modify: `app/services/feature_modules/base_module.rb`
- Modify: `spec/services/feature_modules/base_module_spec.rb`
- Create: `app/services/feature_modules/nav_item.rb`
- Create: `spec/services/feature_modules/nav_item_spec.rb`

- [ ] **Step 1: Write failing spec for `NavItem` value object**

Create `spec/services/feature_modules/nav_item_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::NavItem do
  describe "construction" do
    it "accepts label, path, svg_path_d, method, section, and html options" do
      item = described_class.new(
        label: "Users",
        path: "/1/authentication/admin/users",
        svg_path_d: "M1 2",
        method: :get,
        section: :primary,
        data: { confirm: "Sure?" }
      )
      expect(item.label).to eq("Users")
      expect(item.path).to eq("/1/authentication/admin/users")
      expect(item.svg_path_d).to eq("M1 2")
      expect(item.method).to eq(:get)
      expect(item.section).to eq(:primary)
      expect(item.data).to eq(confirm: "Sure?")
    end

    it "defaults method to :get, section to :primary, data to empty hash" do
      item = described_class.new(label: "X", path: "/x")
      expect(item.method).to eq(:get)
      expect(item.section).to eq(:primary)
      expect(item.data).to eq({})
    end

    it "supports text-only items (no path) for display labels" do
      item = described_class.new(label: "Welcome, Alice", section: :user_menu)
      expect(item.path).to be_nil
      expect(item.link?).to be false
    end

    it "link? returns true when path is present" do
      expect(described_class.new(label: "X", path: "/x").link?).to be true
    end
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `bundle exec rspec spec/services/feature_modules/nav_item_spec.rb 2>&1 | tail -15`
Expected: `uninitialized constant FeatureModules::NavItem`.

- [ ] **Step 3: Create `app/services/feature_modules/nav_item.rb`**

```ruby
# frozen_string_literal: true

module FeatureModules
  # Value object representing a single nav contribution from a feature module.
  #
  # Modules return an array of these from Registration.nav_items_for(controller, section:).
  # The NavContributionsComponent renders them — modules do not emit HTML directly.
  class NavItem
    attr_reader :label, :path, :svg_path_d, :method, :section, :data, :css_classes

    def initialize(label:, path: nil, svg_path_d: nil, method: :get, section: :primary,
                   data: {}, css_classes: nil)
      @label       = label
      @path        = path
      @svg_path_d  = svg_path_d
      @method      = method
      @section     = section
      @data        = data
      @css_classes = css_classes
    end

    def link?
      path.present?
    end
  end
end
```

- [ ] **Step 4: Run nav_item spec and confirm pass**

Run: `bundle exec rspec spec/services/feature_modules/nav_item_spec.rb 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 5: Write failing specs for BaseModule hooks**

Append to `spec/services/feature_modules/base_module_spec.rb` (inside the top-level describe block):
```ruby
  describe "generic host-integration hooks" do
    let(:dummy_module) do
      Class.new(FeatureModules::BaseModule) do
        def self.module_key; "dummy_hooks"; end
        def self.module_name; "Dummy"; end
        def self.provision!(_); end
      end
    end

    describe ".before_request" do
      it "is a no-op by default and returns nil" do
        fake_controller = double("controller")
        expect(dummy_module.before_request(fake_controller)).to be_nil
      end
    end

    describe ".nav_items_for" do
      it "returns an empty array by default for any section" do
        fake_controller = double("controller")
        expect(dummy_module.nav_items_for(fake_controller, section: :primary)).to eq([])
        expect(dummy_module.nav_items_for(fake_controller, section: :user_menu)).to eq([])
      end
    end
  end
```

- [ ] **Step 6: Run and confirm failure**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb -e "generic host-integration" 2>&1 | tail -10`
Expected: NoMethodError on `before_request` or `nav_items_for`.

- [ ] **Step 7: Add hooks to `app/services/feature_modules/base_module.rb`**

Inside the `class << self` block, after the `def deprovision!(customer); end` method (around line 46), add:
```ruby
      # Generic per-request hook. Called by FeatureModules::HostIntegration concern
      # for every module enabled for the current customer, on every request.
      # Override in subclasses to enforce access control, set context, etc.
      # Must not raise — redirect via the controller and return.
      def before_request(controller)
        nil
      end

      # Generic nav contribution hook. Called by NavContributionsComponent.
      # Return an array of FeatureModules::NavItem for the given section.
      # Sections: :primary (top nav), :user_menu (right-side user area).
      def nav_items_for(controller, section:)
        []
      end
```

- [ ] **Step 8: Run base_module spec and confirm pass**

Run: `bundle exec rspec spec/services/feature_modules/base_module_spec.rb 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 9: Pause for user review and commit.**

---

### Task 3: Create `FeatureModules::HostIntegration` controller concern

**Why:** Single generic concern included in `ApplicationController`. Iterates enabled modules per request and calls `before_request(self)` on each. Replaces `AuthenticationEnforceable`. Exposes `feature_module_enabled?(key)` helper for views.

**Files:**
- Create: `app/controllers/concerns/feature_modules/host_integration.rb`
- Create: `spec/controllers/concerns/feature_modules/host_integration_spec.rb`

- [ ] **Step 1: Write failing spec**

Create `spec/controllers/concerns/feature_modules/host_integration_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::HostIntegration, type: :controller do
  controller(ApplicationController) do
    def index
      render plain: "ok"
    end
  end

  let(:customer) { create(:customer) }

  before do
    routes.draw { get "index" => "anonymous#index" }
  end

  describe "#run_feature_module_before_request" do
    it "invokes before_request on every enabled module's registration" do
      auth_reg = FeatureModules::Authentication::Registration
      allow(controller).to receive(:current_customer_id).and_return(customer.id)

      expect(auth_reg).to receive(:before_request).with(controller)

      get :index
    end

    it "does not invoke before_request for modules not enabled for the customer" do
      auth_module = FeatureModule.find_by!(key: "authentication")
      CustomerFeatureModule.where(customer: customer, feature_module: auth_module).destroy_all

      allow(controller).to receive(:current_customer_id).and_return(customer.id)
      expect(FeatureModules::Authentication::Registration).not_to receive(:before_request)

      get :index
    end

    it "is a no-op when current_customer_id is blank" do
      allow(controller).to receive(:current_customer_id).and_return(nil)
      expect(FeatureModules::Authentication::Registration).not_to receive(:before_request)

      get :index
    end

    it "stops the chain if before_request performed a redirect" do
      allow(controller).to receive(:current_customer_id).and_return(customer.id)
      allow(FeatureModules::Authentication::Registration).to receive(:before_request) do |c|
        c.redirect_to("/somewhere")
      end

      get :index
      expect(response).to redirect_to("/somewhere")
    end
  end

  describe "#feature_module_enabled? helper" do
    it "returns true for modules active for the current customer" do
      allow(controller).to receive(:current_customer_id).and_return(customer.id)
      expect(controller.feature_module_enabled?("authentication")).to be true
    end

    it "returns false when customer has no row for the module" do
      auth_module = FeatureModule.find_by!(key: "authentication")
      CustomerFeatureModule.where(customer: customer, feature_module: auth_module).destroy_all
      allow(controller).to receive(:current_customer_id).and_return(customer.id)
      expect(controller.feature_module_enabled?("authentication")).to be false
    end

    it "returns false when current_customer_id is blank" do
      allow(controller).to receive(:current_customer_id).and_return(nil)
      expect(controller.feature_module_enabled?("authentication")).to be false
    end
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `bundle exec rspec spec/controllers/concerns/feature_modules/host_integration_spec.rb 2>&1 | tail -20`
Expected: `uninitialized constant FeatureModules::HostIntegration`.

- [ ] **Step 3: Create concern**

Create `app/controllers/concerns/feature_modules/host_integration.rb`:
```ruby
# frozen_string_literal: true

module FeatureModules
  # Generic host-integration concern included in ApplicationController.
  #
  # For every request, iterates modules enabled for the current customer
  # and invokes Registration.before_request(self). Any module may redirect
  # or halt via the controller; if the response is already a redirect,
  # remaining modules are skipped.
  #
  # Exposes the generic feature_module_enabled?(key) helper to views.
  #
  # Adding a new cross-cutting module: override .before_request in the
  # module's Registration — no changes needed here.
  module HostIntegration
    extend ActiveSupport::Concern

    included do
      before_action :run_feature_module_before_request

      helper_method :feature_module_enabled?
    end

    # View/controller helper — generic enablement check.
    def feature_module_enabled?(key)
      return false if current_customer_id.blank?

      FeatureModule.enabled?(key: key, customer_id: current_customer_id)
    end

    private

    def run_feature_module_before_request
      return if current_customer_id.blank?

      FeatureModule.enabled_for_customer(current_customer_id).find_each do |fm|
        fm.registration_class.before_request(self)
        return if performed?
      end
    end
  end
end
```

- [ ] **Step 4: Run host_integration spec**

Run: `bundle exec rspec spec/controllers/concerns/feature_modules/host_integration_spec.rb 2>&1 | tail -15`
Expected: all pass.

- [ ] **Step 5: Pause for user review and commit.**

---

### Task 4: Move auth enforcement into `Authentication::Registration.before_request`

**Why:** Auth's session/MFA logic becomes a module-local concern, invoked through the generic hook. No more special-case concern.

**Files:**
- Modify: `app/services/feature_modules/authentication/registration.rb`
- Modify: `spec/services/feature_modules/authentication/registration_spec.rb`

- [ ] **Step 1: Write failing specs for `before_request`**

Append to `spec/services/feature_modules/authentication/registration_spec.rb`:
```ruby
  describe ".before_request" do
    let(:customer) { create(:customer) }
    let(:controller) do
      instance_double(ApplicationController,
                      current_customer_id: customer.id,
                      devise_controller?: false,
                      user_signed_in?: false,
                      request: instance_double("Rack::Request", fullpath: "/#{customer.id}/flowcharts"),
                      performed?: false)
    end

    context "user not signed in" do
      it "redirects to the sign-in path" do
        expect(controller).to receive(:store_location_for).with(:user, "/#{customer.id}/flowcharts")
        expect(controller).to receive(:redirect_to).with(
          "/#{customer.id}/auth/users/sign_in",
          alert: "Please sign in to continue."
        )

        allow(Rails.application.routes.url_helpers).to receive(:new_user_session_path)
          .with(customer_id: customer.id).and_return("/#{customer.id}/auth/users/sign_in")

        described_class.before_request(controller)
      end
    end

    context "devise controller request" do
      it "short-circuits without redirecting" do
        allow(controller).to receive(:devise_controller?).and_return(true)
        expect(controller).not_to receive(:redirect_to)
        described_class.before_request(controller)
      end
    end

    context "already performed response" do
      it "short-circuits" do
        allow(controller).to receive(:performed?).and_return(true)
        expect(controller).not_to receive(:redirect_to)
        described_class.before_request(controller)
      end
    end
  end
```

- [ ] **Step 2: Run and confirm failure**

Run: `bundle exec rspec spec/services/feature_modules/authentication/registration_spec.rb -e "before_request" 2>&1 | tail -20`
Expected: spec fails — `.before_request` returns nil (inherited no-op).

- [ ] **Step 3: Implement `before_request` and remove `enabled_for?`**

In `app/services/feature_modules/authentication/registration.rb`:

Delete the method `def self.enabled_for?(customer_id)` (lines 35–40 in the pre-edit file). Keep `mfa_required_for?` and `config_for` — they're auth-internal configuration helpers used by auth's own controllers.

Add the following methods above `def self.enabled_for?` (or, after deletion, above `def self.mfa_required_for?`):
```ruby
      def self.before_request(controller)
        return if controller.performed?
        return if controller.devise_controller?
        return if controller.is_a?(Authentication::MfaController)

        enforce_session!(controller)
        return if controller.performed?

        enforce_mfa!(controller)
      end

      def self.enforce_session!(controller)
        return if controller.user_signed_in? &&
                  controller.current_user.customer_id == controller.current_customer_id

        controller.store_location_for(:user, controller.request.fullpath)
        controller.redirect_to(
          Rails.application.routes.url_helpers
               .new_user_session_path(customer_id: controller.current_customer_id),
          alert: "Please sign in to continue."
        )
      end

      def self.enforce_mfa!(controller)
        return unless controller.user_signed_in?
        return unless mfa_required_for?(controller.current_customer_id)

        if controller.current_user.mfa_configured?
          return if controller.session[:mfa_verified]

          controller.redirect_to(
            Rails.application.routes.url_helpers
                 .mfa_verify_path(controller.current_customer_id)
          )
        else
          controller.redirect_to(
            Rails.application.routes.url_helpers
                 .mfa_setup_path(controller.current_customer_id)
          )
        end
      end
```

- [ ] **Step 4: Remove the `enabled_for?` spec block**

In `spec/services/feature_modules/authentication/registration_spec.rb`, delete the entire `describe ".enabled_for?"` block (approx lines 46–63 in the pre-edit file). The generic `FeatureModule.enabled?` spec added in Task 1 covers this behavior.

- [ ] **Step 5: Run auth registration specs**

Run: `bundle exec rspec spec/services/feature_modules/authentication/registration_spec.rb 2>&1 | tail -15`
Expected: all pass (existing + new `before_request` specs).

- [ ] **Step 6: Pause for user review and commit.**

---

### Task 5: Swap `AuthenticationEnforceable` → `HostIntegration` in `ApplicationController`, delete old concern

**Why:** Integration layer now generic.

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Delete: `app/controllers/concerns/authentication_enforceable.rb`

- [ ] **Step 1: Update ApplicationController**

Replace in `app/controllers/application_controller.rb`:
```ruby
  include AuthenticationEnforceable
```
with:
```ruby
  include FeatureModules::HostIntegration
```

- [ ] **Step 2: Delete old concern**

Run: `rm /opt/milestone/anysys/app/controllers/concerns/authentication_enforceable.rb`

- [ ] **Step 3: Run controller + request specs to catch fallout**

Run: `bundle exec rspec spec/controllers spec/requests 2>&1 | tail -20`
Expected: all pass. Failures likely indicate remaining callers of the removed concern's helpers — fix in Task 6.

- [ ] **Step 4: Pause for user review and commit.**

---

### Task 6: Migrate auth module's own controllers to generic `FeatureModule.enabled?`

**Why:** Even the auth module shouldn't call itself through a module-specific shim — it goes through the generic API like everyone else, which keeps all enablement logic in one place.

**Files:**
- Modify: `app/controllers/authentication/sessions_controller.rb`
- Modify: `app/controllers/authentication/passwords_controller.rb`
- Modify: `app/controllers/authentication/registrations_controller.rb`
- Modify: `app/controllers/authentication/mfa_controller.rb`

- [ ] **Step 1: Replace in `sessions_controller.rb`**

At line ~73, change:
```ruby
      return if FeatureModules::Authentication::Registration.enabled_for?(current_customer_id)
```
to:
```ruby
      return if FeatureModule.enabled?(key: "authentication", customer_id: current_customer_id)
```

At line ~80, change:
```ruby
      FeatureModules::Authentication::Registration.mfa_required_for?(current_customer_id)
```
Leave this one — `mfa_required_for?` is auth-specific configuration, not an enablement check. Legitimate module-internal call.

- [ ] **Step 2: Replace in `passwords_controller.rb`**

At line ~26, change:
```ruby
      return if FeatureModules::Authentication::Registration.enabled_for?(current_customer_id)
```
to:
```ruby
      return if FeatureModule.enabled?(key: "authentication", customer_id: current_customer_id)
```

- [ ] **Step 3: Replace in `registrations_controller.rb`**

At line ~79, change `.enabled_for?(current_customer_id)` to `FeatureModule.enabled?(key: "authentication", customer_id: current_customer_id)`. Leave the `.config_for(current_customer_id)` call at line ~86 — auth-specific configuration read, module-internal.

- [ ] **Step 4: Leave `mfa_controller.rb` alone**

Line ~70 uses `.mfa_required_for?` — auth-specific, not an enablement check. No change.

- [ ] **Step 5: Run all specs touching auth controllers**

Run: `bundle exec rspec spec/controllers/authentication 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 6: Pause for user review and commit.**

---

### Task 7: Implement auth registration's `nav_items_for`

**Why:** Auth module owns its nav contributions — admin Users link and Sign-out. Layout no longer conditionals on `authentication_enabled?`.

**Files:**
- Modify: `app/services/feature_modules/authentication/registration.rb`
- Modify: `spec/services/feature_modules/authentication/registration_spec.rb`

- [ ] **Step 1: Write failing specs**

Append to `spec/services/feature_modules/authentication/registration_spec.rb`:
```ruby
  describe ".nav_items_for" do
    let(:customer) { create(:customer) }
    let(:user) do
      instance_double(Authentication::User,
                      customer_id: customer.id,
                      display_name: "Alice",
                      admin?: true,
                      owner?: false)
    end
    let(:controller) do
      instance_double(ApplicationController,
                      current_customer_id: customer.id,
                      user_signed_in?: true,
                      current_user: user)
    end

    context "section: :primary" do
      it "contributes the admin Users link when the user is admin or owner" do
        items = described_class.nav_items_for(controller, section: :primary)
        expect(items.map(&:label)).to include("Users")
        users_item = items.find { |i| i.label == "Users" }
        expect(users_item.path).to eq("/#{customer.id}/authentication/admin/users")
      end

      it "omits the Users link when the user is neither admin nor owner" do
        allow(user).to receive(:admin?).and_return(false)
        allow(user).to receive(:owner?).and_return(false)
        items = described_class.nav_items_for(controller, section: :primary)
        expect(items.map(&:label)).not_to include("Users")
      end

      it "returns an empty array when the user is not signed in" do
        allow(controller).to receive(:user_signed_in?).and_return(false)
        allow(controller).to receive(:current_user).and_return(nil)
        expect(described_class.nav_items_for(controller, section: :primary)).to eq([])
      end
    end

    context "section: :user_menu" do
      it "contributes the display_name text and a Sign out link when signed in" do
        items = described_class.nav_items_for(controller, section: :user_menu)
        labels = items.map(&:label)
        expect(labels).to include("Alice")
        expect(labels).to include("Sign out")
        signout = items.find { |i| i.label == "Sign out" }
        expect(signout.method).to eq(:delete)
      end

      it "returns an empty array when the user is not signed in" do
        allow(controller).to receive(:user_signed_in?).and_return(false)
        expect(described_class.nav_items_for(controller, section: :user_menu)).to eq([])
      end
    end

    context "unknown section" do
      it "returns an empty array" do
        expect(described_class.nav_items_for(controller, section: :sidebar)).to eq([])
      end
    end
  end
```

- [ ] **Step 2: Run and confirm failure**

Run: `bundle exec rspec spec/services/feature_modules/authentication/registration_spec.rb -e "nav_items_for" 2>&1 | tail -20`
Expected: fails — default hook returns `[]` for all sections, so admin Users assertion fails.

- [ ] **Step 3: Implement `nav_items_for`**

In `app/services/feature_modules/authentication/registration.rb`, add to the class (before `end` of class body):
```ruby
      def self.nav_items_for(controller, section:)
        case section
        when :primary   then primary_nav_items(controller)
        when :user_menu then user_menu_items(controller)
        else []
        end
      end

      def self.primary_nav_items(controller)
        return [] unless controller.user_signed_in?

        user = controller.current_user
        return [] unless user.admin? || user.owner?

        customer_id = controller.current_customer_id
        [
          FeatureModules::NavItem.new(
            label:      "Users",
            path:       Rails.application.routes.url_helpers
                             .authentication_admin_users_path(customer_id),
            svg_path_d: "M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z",
            section:    :primary
          )
        ]
      end

      def self.user_menu_items(controller)
        return [] unless controller.user_signed_in?

        customer_id = controller.current_customer_id
        user = controller.current_user

        [
          FeatureModules::NavItem.new(
            label:   user.display_name,
            section: :user_menu,
            css_classes: "text-sm text-gray-500"
          ),
          FeatureModules::NavItem.new(
            label:   "Sign out",
            path:    Rails.application.routes.url_helpers
                          .destroy_user_session_path(customer_id: customer_id),
            method:  :delete,
            section: :user_menu,
            data:    { turbo_method: :delete },
            css_classes: "ml-2 px-2 py-1 text-xs font-medium text-gray-500 hover:text-red-600 hover:bg-red-50 rounded transition-colors"
          )
        ]
      end
```

- [ ] **Step 4: Run and confirm pass**

Run: `bundle exec rspec spec/services/feature_modules/authentication/registration_spec.rb 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 5: Pause for user review and commit.**

---

### Task 8: Create `FeatureModules::NavContributionsComponent`

**Why:** Generic ViewComponent renders nav items contributed by any enabled module. Layout delegates to this component — no module-specific branches.

**Files:**
- Create: `app/components/feature_modules/nav_contributions_component.rb`
- Create: `app/components/feature_modules/nav_contributions_component.html.erb`
- Create: `spec/components/feature_modules/nav_contributions_component_spec.rb`

- [ ] **Step 1: Write failing spec**

Create `spec/components/feature_modules/nav_contributions_component_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::NavContributionsComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:controller) do
    instance_double(ApplicationController,
                    current_customer_id: customer.id,
                    user_signed_in?: false,
                    current_user: nil)
  end

  describe "#items" do
    it "concatenates items from every enabled module for the given section" do
      fake_item = FeatureModules::NavItem.new(
        label: "Custom", path: "/custom", section: :primary
      )
      allow(FeatureModules::Authentication::Registration)
        .to receive(:nav_items_for).with(controller, section: :primary).and_return([fake_item])

      component = described_class.new(controller: controller, section: :primary)
      expect(component.items).to eq([fake_item])
    end

    it "returns an empty array when customer_id is blank" do
      allow(controller).to receive(:current_customer_id).and_return(nil)
      component = described_class.new(controller: controller, section: :primary)
      expect(component.items).to eq([])
    end
  end

  describe "rendering" do
    it "renders a link for a NavItem with a path" do
      item = FeatureModules::NavItem.new(
        label: "Users", path: "/1/users", section: :primary
      )
      component = described_class.new(controller: controller, section: :primary)
      allow(component).to receive(:items).and_return([item])

      rendered = render_inline(component)
      expect(rendered.to_html).to include("Users")
      expect(rendered.to_html).to include('href="/1/users"')
    end

    it "renders plain text for a NavItem without a path" do
      item = FeatureModules::NavItem.new(label: "Welcome, Alice", section: :user_menu)
      component = described_class.new(controller: controller, section: :user_menu)
      allow(component).to receive(:items).and_return([item])

      rendered = render_inline(component)
      expect(rendered.to_html).to include("Welcome, Alice")
      expect(rendered.to_html).not_to include("<a ")
    end

    it "renders nothing when there are no items" do
      component = described_class.new(controller: controller, section: :primary)
      allow(component).to receive(:items).and_return([])

      rendered = render_inline(component)
      expect(rendered.to_html.strip).to eq("")
    end
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `bundle exec rspec spec/components/feature_modules/nav_contributions_component_spec.rb 2>&1 | tail -15`
Expected: `uninitialized constant FeatureModules::NavContributionsComponent`.

- [ ] **Step 3: Implement component class**

Create `app/components/feature_modules/nav_contributions_component.rb`:
```ruby
# frozen_string_literal: true

module FeatureModules
  # Renders nav items contributed by every feature module enabled for
  # the current customer, for a given section (:primary or :user_menu).
  #
  # Modules contribute via Registration.nav_items_for(controller, section:).
  # Adding a new module's nav items requires no changes here or to layouts.
  class NavContributionsComponent < ViewComponent::Base
    def initialize(controller:, section:)
      @controller = controller
      @section    = section
    end

    def items
      customer_id = @controller.current_customer_id
      return [] if customer_id.blank?

      FeatureModule.enabled_for_customer(customer_id).flat_map do |fm|
        fm.registration_class.nav_items_for(@controller, section: @section)
      end.compact
    end
  end
end
```

- [ ] **Step 4: Implement template**

Create `app/components/feature_modules/nav_contributions_component.html.erb`:
```erb
<% items.each do |item| %>
  <% if item.link? %>
    <%= link_to item.path,
                data: item.data,
                class: item.css_classes || "px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md transition-colors" do %>
      <span class="flex items-center gap-1.5">
        <% if item.svg_path_d.present? %>
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="<%= item.svg_path_d %>" />
          </svg>
        <% end %>
        <%= item.label %>
      </span>
    <% end %>
  <% else %>
    <span class="<%= item.css_classes || 'text-sm text-gray-500' %>"><%= item.label %></span>
  <% end %>
<% end %>
```

- [ ] **Step 5: Run and confirm pass**

Run: `bundle exec rspec spec/components/feature_modules/nav_contributions_component_spec.rb 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 6: Pause for user review and commit.**

---

### Task 9: Replace hard-coded auth blocks in `application.html.erb` with component

**Why:** Shared layout no longer references any specific module.

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Replace the admin Users block**

Delete lines 67–84 (the `<% if authentication_enabled? && user_signed_in? && (current_user.admin? || current_user.owner?) %>` block containing the Users link and the Code Generators link — note the Code Generators link is NOT auth-contributed; see step 2).

Replace with:
```erb
              <%= render FeatureModules::NavContributionsComponent.new(controller: controller, section: :primary) %>

              <% if user_signed_in? && (current_user.admin? || current_user.owner?) %>
                <%= link_to admin_code_generators_path, class: "px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md transition-colors" do %>
                  <span class="flex items-center gap-1.5">
                    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
                    </svg>
                    Code Generators
                  </span>
                <% end %>
              <% end %>
```

Note: Code Generators is system-admin functionality, not module-contributed, so it stays in the layout. It's now gated only on `user_signed_in? && admin/owner` without the module check.

- [ ] **Step 2: Replace the user-menu block**

Delete lines 93–102 (the `<% if authentication_enabled? && user_signed_in? %>` block).

Replace with:
```erb
              <% if user_signed_in? %>
                <div class="relative ml-2 pl-2 border-l border-gray-200">
                  <%= render FeatureModules::NavContributionsComponent.new(controller: controller, section: :user_menu) %>
                </div>
              <% end %>
```

- [ ] **Step 3: Run layout-related request specs**

Run: `bundle exec rspec spec/requests 2>&1 | tail -20` (or `spec/views` if layout specs exist)
Expected: all pass.

- [ ] **Step 4: Manual browser check**

Start server: `bin/rails server` (or note to user: "please launch dev server to verify the nav renders correctly for an authenticated admin user").

Check in browser:
- Auth-enabled customer, admin signed in: Users link visible, Sign out visible, display_name shown
- Auth-enabled customer, regular user signed in: Users link hidden, Sign out visible
- Auth-disabled customer: no auth nav items (just primary Flowcharts/Pages/Modules etc.)

If agent cannot launch a browser, say so explicitly in the final report rather than claiming it was verified.

- [ ] **Step 5: Pause for user review and commit.**

---

### Task 10: Auto-discover registrations in initializer

**Why:** Adding a new module means creating `app/services/feature_modules/<key>/registration.rb` — no initializer edit required.

**Files:**
- Modify: `config/initializers/feature_modules.rb`

- [ ] **Step 1: Rewrite initializer**

Replace the content of `config/initializers/feature_modules.rb` with:
```ruby
# frozen_string_literal: true

# Auto-discover and register every feature module under app/services/feature_modules/*/registration.rb.
#
# To add a new feature module:
#   1. Create app/services/feature_modules/<key>/registration.rb extending FeatureModules::BaseModule
#   2. (Optional) If it should be required for all customers, call `required!` in the registration class
#   3. That's it — no edits to this file.
#
Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection.table_exists?(:feature_modules)

  registration_paths = Rails.root.glob("app/services/feature_modules/*/registration.rb")

  registration_paths.each do |path|
    require_dependency(path.to_s)

    # Derive module name from directory: .../feature_modules/<key>/registration.rb
    key_dir = path.parent.basename.to_s
    klass_name = "FeatureModules::#{key_dir.camelize}::Registration"

    begin
      klass = klass_name.constantize
    rescue NameError => e
      AppLogger.warn("Skipping feature module at #{path}: #{e.message}", source: "FeatureModules")
      next
    end

    klass.register!
  end

  # Ensure required modules are provisioned for all existing customers
  ::FeatureModule.required.find_each do |fm|
    Customer.find_each do |customer|
      cfm = CustomerFeatureModule.find_or_initialize_by(customer: customer, feature_module: fm)
      next if cfm.persisted? && cfm.active?

      cfm.update!(
        status: :active,
        enabled_at: cfm.enabled_at || Time.current,
        configuration: cfm.configuration.presence || {}.to_json
      )
      fm.registration_class.provision!(customer)
    end
  end
rescue ActiveRecord::StatementInvalid, ActiveModel::UnknownAttributeError => e
  AppLogger.warn("Feature module registration skipped: #{e.message}", source: "FeatureModules")
end
```

Note: the pre-edit file also sets `auth.update!(required: true)` — that one-time migration step is removed because `required: true` is expected to be declared in the Registration class itself (or already set in the DB). Verify with a fresh rails console after this task that `FeatureModule.find_by(key: "authentication").required?` returns `true`. If it does not (fresh DB), the correct location to declare it is via a DB seed/migration, NOT in the initializer — filing this as a follow-up note for the user rather than putting env-specific data in the initializer.

- [ ] **Step 2: Boot the app and confirm no regressions**

Run: `bin/rails runner "puts FeatureModule.pluck(:key).sort"`
Expected: `authentication` and `payment` both listed (payment is auto-discovered now too, while it wasn't before).

- [ ] **Step 3: Run full feature_modules spec suite**

Run: `bundle exec rspec spec/services/feature_modules spec/models/feature_module_spec.rb spec/models/customer_feature_module_spec.rb 2>&1 | tail -15`
Expected: all pass.

- [ ] **Step 4: Pause for user review and commit.**

---

### Task 11: Full sweep and cleanup verification

**Why:** Confirm no remaining module-specific references leak into integration surfaces.

**Files:** (read-only audit)

- [ ] **Step 1: Grep for residual auth-specific integration leaks**

Run:
```bash
grep -rn "FeatureModules::Authentication::Registration" app/ config/ --include="*.rb" --include="*.erb"
grep -rn "authentication_enabled?\|mfa_required_for_customer?" app/ config/ --include="*.rb" --include="*.erb"
grep -rn "AuthenticationEnforceable" app/ config/ --include="*.rb"
```

Expected results:
- `FeatureModules::Authentication::Registration` references: ONLY inside `app/services/feature_modules/authentication/**`, `app/controllers/authentication/**`, `app/views/authentication/**`, `spec/**`. None in `application_controller.rb`, `application.html.erb`, or cross-cutting concerns.
- `authentication_enabled?` / `mfa_required_for_customer?`: ZERO matches outside `app/services/feature_modules/authentication/**` and specs.
- `AuthenticationEnforceable`: ZERO matches.

If any unexpected match appears, migrate it to `FeatureModule.enabled?(key: "authentication", customer_id: ...)` or `feature_module_enabled?("authentication")` respectively.

- [ ] **Step 2: Run full test suite**

Run: `bundle exec rspec 2>&1 | tail -30`
Expected: all pass. Record total example count to confirm coverage didn't drop.

- [ ] **Step 3: Verify end-to-end with `bin/rails runner`**

Run:
```bash
bin/rails runner "
customer = Customer.first
ctrl = Struct.new(:current_customer_id, :user_signed_in?, :current_user, :performed?, :devise_controller?) do
  def is_a?(klass); false; end
end.new(customer.id, false, nil, false, true)
puts 'enabled?: ' + FeatureModule.enabled?(key: 'authentication', customer_id: customer.id).to_s
puts 'enabled_for_customer keys: ' + FeatureModule.enabled_for_customer(customer.id).pluck(:key).sort.inspect
"
```
Expected: `enabled?: true`, `keys: [\"authentication\"]` (payment is registered but not enabled per-customer by default).

- [ ] **Step 4: Final pause for user review and commit.**

After user reviews and commits, this plan is complete.

---

## Follow-up notes (not in plan, flagged for the user)

- Payment module gets auto-discovered after Task 10 — previously it was defined but never registered. If the user does not want it appearing in the `FeatureModule` admin, either delete `app/services/feature_modules/payment/registration.rb` or gate auto-discovery on a `published?` class-method convention. Raising as a question, not implementing.
- The `required: true` flag for authentication was previously forced in the initializer. After Task 10 it relies on whatever's already in the DB or a seed. If fresh-DB bootstrap needs it, propose a proper seed/migration in a follow-up — don't re-embed in initializer.
- `Authentication::Registration` is reaching ~150 lines covering five responsibilities (lifecycle, config, enforcement, schema, nav). Once the payment module also grows substantive hooks, consider extracting collaborators per module (`RequestEnforcer`, `NavContributor`) so each `Registration` class stays a thin dispatcher. Not blocking; revisit when a second module requires a real `before_request` or `nav_items_for` implementation.
