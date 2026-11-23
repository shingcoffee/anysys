# Feature Module Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure authentication into `Authentication::` namespace, build auto-discovery services for models/routes, and redesign feature module pages to a minimal clean UI.

**Architecture:** Move User model and auth controllers into `Authentication::` namespace so models and routes can be auto-discovered by convention. Two new services (`ModuleModelDiscovery`, `ModuleRouteDiscovery`) introspect the filesystem and Rails routes. Feature module index becomes a clean list, detail page becomes a single-column stacked layout with Models and Routes sections.

**Tech Stack:** Ruby on Rails 8.1.2, Devise, TailwindCSS, StimulusJS, ViewComponent, RSpec

**Spec:** `docs/superpowers/specs/2026-03-22-feature-module-redesign-design.md`

---

## File Map

### New Files
- `app/models/authentication/user.rb` — moved from `app/models/user.rb`
- `app/controllers/authentication/sessions_controller.rb` — moved from `app/controllers/auth/sessions_controller.rb`
- `app/controllers/authentication/registrations_controller.rb` — moved from `app/controllers/auth/registrations_controller.rb`
- `app/controllers/authentication/passwords_controller.rb` — moved from `app/controllers/auth/passwords_controller.rb`
- `app/controllers/authentication/mfa_controller.rb` — moved from `app/controllers/auth/mfa_controller.rb`
- `app/controllers/authentication/admin/users_controller.rb` — moved from `app/controllers/admin/users_controller.rb`
- `app/views/authentication/` — moved from `app/views/auth/`
- `app/views/authentication/admin/users/` — moved from `app/views/admin/users/`
- `app/services/module_model_discovery.rb` — auto-discovers models in `app/models/<module_key>/`
- `app/services/module_route_discovery.rb` — auto-discovers routes by controller namespace
- `app/components/feature_module_list_item_component.rb` — index row component
- `app/components/feature_module_list_item_component.html.erb` — index row template
- `spec/services/module_model_discovery_spec.rb`
- `spec/services/module_route_discovery_spec.rb`
- `spec/components/feature_module_list_item_component_spec.rb`
- `spec/models/authentication/user_spec.rb` — moved from `spec/models/user_spec.rb`
- `spec/requests/authentication/` — moved from `spec/requests/auth/`
- `spec/requests/authentication/admin/users_spec.rb` — moved from `spec/requests/admin/users_spec.rb`

### Deleted Files
- `app/models/user.rb`
- `app/controllers/auth/sessions_controller.rb`
- `app/controllers/auth/registrations_controller.rb`
- `app/controllers/auth/passwords_controller.rb`
- `app/controllers/auth/mfa_controller.rb`
- `app/controllers/admin/users_controller.rb`
- `app/views/auth/` (entire directory)
- `app/views/admin/users/` (entire directory)
- `app/components/feature_module_card_component.rb`
- `app/components/feature_module_card_component.html.erb`
- `spec/models/user_spec.rb`
- `spec/requests/auth/` (entire directory)
- `spec/requests/admin/users_spec.rb`
- `spec/components/feature_module_card_component_spec.rb`

### Modified Files
- `config/routes.rb` — update Devise + MFA + admin routes to `authentication/` namespace
- `config/initializers/devise.rb` — update comment reference
- `config/initializers/feature_modules.rb` — no User reference changes needed (uses provisioner)
- `app/controllers/concerns/authentication_enforceable.rb` — update `Auth::MfaController` reference
- `app/services/feature_modules/authentication/provisioner.rb` — `User` → `Authentication::User`
- `app/services/feature_modules/authentication/deprovisioner.rb` — `User` → `Authentication::User`
- `app/controllers/feature_modules_controller.rb` — pass discovery data to show view
- `app/views/feature_modules/index.html.erb` — redesign to list layout
- `app/views/feature_modules/show.html.erb` — redesign to stacked single-column with Models/Routes sections
- `spec/factories/users.rb` — update class reference
- `spec/requests/feature_modules_spec.rb` — update for new show page sections
- `spec/services/feature_modules/authentication/registration_spec.rb` — `User` → `Authentication::User`
- `spec/services/feature_modules/authentication/provisioner_spec.rb` — `User` → `Authentication::User`
- Multiple spec files with `User` references (see Task 3)

---

## Task 1: Move User model into Authentication namespace

**Files:**
- Create: `app/models/authentication/user.rb`
- Delete: `app/models/user.rb`

- [ ] **Step 1:** Create the directory and new model file. The content is identical to the current `app/models/user.rb` but wrapped in the `Authentication` module, and the class becomes `Authentication::User`. The table name must be explicitly set since Rails would otherwise look for `authentication_users`.

```ruby
# app/models/authentication/user.rb
# frozen_string_literal: true

module Authentication
  class User < ApplicationRecord
    self.table_name = "users"

    include TenantScoped

    # ... (entire existing User model body, unchanged)
  end
end
```

- [ ] **Step 2:** Delete `app/models/user.rb`

- [ ] **Step 3:** Update `spec/factories/users.rb` — add `class { Authentication::User }` to the factory:
```ruby
factory :user, class: "Authentication::User" do
```

- [ ] **Step 4:** Move `spec/models/user_spec.rb` → `spec/models/authentication/user_spec.rb`. Update the describe block:
```ruby
RSpec.describe Authentication::User, type: :model do
```

- [ ] **Step 5:** Update all source files that reference `User` directly to use `Authentication::User`:
  - `app/services/feature_modules/authentication/provisioner.rb` — all `User.` calls → `Authentication::User.`
  - `app/services/feature_modules/authentication/deprovisioner.rb` — all `User.` calls → `Authentication::User.`
  - `app/controllers/admin/users_controller.rb` — all `User.` calls → `Authentication::User.` (this file moves later, but update the references now)

- [ ] **Step 6:** Update spec files that reference `User` model directly:
  - `spec/services/feature_modules/authentication/registration_spec.rb`
  - `spec/services/feature_modules/authentication/provisioner_spec.rb`
  - `spec/requests/admin/users_spec.rb`
  - `spec/requests/auth/registrations_spec.rb`
  - Any other spec that calls `User.` or `Authentication::User`

- [ ] **Step 7:** Update Devise configuration. In `config/routes.rb`, the `devise_for :users` needs a `class_name` option:
```ruby
devise_for :users, path: ":customer_id/auth",
  class_name: "Authentication::User",
  constraints: { customer_id: /\d{8}/ },
  controllers: {
    sessions: "auth/sessions",
    registrations: "auth/registrations",
    passwords: "auth/passwords"
  }
```

- [ ] **Step 8:** Run `bundle exec rspec spec/models/authentication/user_spec.rb` to verify the model works in its new namespace.

---

## Task 2: Move auth controllers into Authentication namespace

**Files:**
- Create: `app/controllers/authentication/sessions_controller.rb`
- Create: `app/controllers/authentication/registrations_controller.rb`
- Create: `app/controllers/authentication/passwords_controller.rb`
- Create: `app/controllers/authentication/mfa_controller.rb`
- Create: `app/controllers/authentication/admin/users_controller.rb`
- Delete: `app/controllers/auth/sessions_controller.rb`
- Delete: `app/controllers/auth/registrations_controller.rb`
- Delete: `app/controllers/auth/passwords_controller.rb`
- Delete: `app/controllers/auth/mfa_controller.rb`
- Delete: `app/controllers/admin/users_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/concerns/authentication_enforceable.rb`

- [ ] **Step 1:** Create `app/controllers/authentication/` directory and move each controller. For each one, wrap the class in `module Authentication` and update the class name:

  - `Auth::SessionsController` → `Authentication::SessionsController`
  - `Auth::RegistrationsController` → `Authentication::RegistrationsController`
  - `Auth::PasswordsController` → `Authentication::PasswordsController`
  - `Auth::MfaController` → `Authentication::MfaController`

  Inside each controller, update any `User` references to `Authentication::User`.

- [ ] **Step 2:** Create `app/controllers/authentication/admin/` directory and move `Admin::UsersController` → `Authentication::Admin::UsersController`. Update all `User` references to `Authentication::User`.

- [ ] **Step 3:** Delete the old controller files:
```bash
rm app/controllers/auth/sessions_controller.rb
rm app/controllers/auth/registrations_controller.rb
rm app/controllers/auth/passwords_controller.rb
rm app/controllers/auth/mfa_controller.rb
rm app/controllers/admin/users_controller.rb
```
Then remove the empty `app/controllers/auth/` and `app/controllers/admin/` directories if empty.

- [ ] **Step 4:** Move views:
```bash
mv app/views/auth/ app/views/authentication/
mv app/views/admin/users/ app/views/authentication/admin/users/
```
Remove empty `app/views/admin/` directory if empty.

- [ ] **Step 5:** Update `config/routes.rb`:

```ruby
devise_for :users, path: ":customer_id/auth",
  class_name: "Authentication::User",
  constraints: { customer_id: /\d{8}/ },
  controllers: {
    sessions: "authentication/sessions",
    registrations: "authentication/registrations",
    passwords: "authentication/passwords"
  }

scope "/:customer_id", constraints: { customer_id: /\d{8}/ } do
  # MFA / 2FA Routes
  scope "auth/mfa", as: :mfa, controller: "authentication/mfa" do
    get    "setup",         action: :setup,         as: :setup
    post   "confirm_setup", action: :confirm_setup,  as: :confirm_setup
    get    "verify",        action: :verify,         as: :verify
    post   "authenticate",  action: :authenticate,   as: :authenticate
    delete "disable",       action: :disable,         as: :disable
  end

  # Admin user management
  namespace :authentication do
    namespace :admin do
      resources :users, except: [:destroy] do
        member do
          patch :activate
          patch :deactivate
          patch :reset_mfa
        end
      end
    end
  end
  # ... rest of routes
end
```

Note: URL paths can stay as `auth/` for Devise and `auth/mfa/` for MFA to avoid breaking bookmarks. The admin users path will change from `/admin/users` to `/authentication/admin/users`.

- [ ] **Step 6:** Update `app/controllers/concerns/authentication_enforceable.rb`:
  - Change `is_a?(Auth::MfaController)` to `is_a?(Authentication::MfaController)`

- [ ] **Step 7:** Move spec files:
```bash
mkdir -p spec/requests/authentication/admin
mv spec/requests/auth/* spec/requests/authentication/
mv spec/requests/admin/users_spec.rb spec/requests/authentication/admin/users_spec.rb
```
Update describe blocks and controller references in each moved spec file.

- [ ] **Step 8:** Run auth-related specs to verify:
```bash
bundle exec rspec spec/requests/authentication/ spec/models/authentication/
```

---

## Task 3: Update remaining User references across codebase

**Files:**
- Modify: Multiple spec files that reference `User` directly

- [ ] **Step 1:** Search and update remaining `User` references in spec files. These files reference `User` but are NOT auth specs (they create users as test setup):
  - `spec/controllers/entities_controller_spec.rb`
  - `spec/controllers/pages_controller_spec.rb`
  - `spec/requests/feature_modules_spec.rb`
  - `spec/services/activity_generator_spec.rb`
  - `spec/services/activity_steps/populate_primary_spec.rb`
  - `spec/contracts/entity_entry_contract_spec.rb`
  - `spec/services/entity_field_organizer_spec.rb`
  - `spec/services/page_field_populator_spec.rb`
  - `spec/services/page_template_applier_spec.rb`
  - `spec/models/entity_spec.rb`
  - `spec/services/model_generator_spec.rb`
  - `spec/services/contract_generator_spec.rb`
  - `spec/integration/subflow_save_spec.rb`
  - `spec/system/flowchart_management_spec.rb`

  For each file: if it references `User` as a class (e.g., `User.create`, `User.count`), change to `Authentication::User`. Most of these only use the `:user` factory which already has the correct class mapping, so they may not need changes — check each one.

- [ ] **Step 2:** Run full test suite to verify:
```bash
bundle exec rspec
```

---

## Task 4: Build ModuleModelDiscovery service

**Files:**
- Create: `app/services/module_model_discovery.rb`
- Create: `spec/services/module_model_discovery_spec.rb`

- [ ] **Step 1:** Write the spec:

```ruby
# spec/services/module_model_discovery_spec.rb
require "rails_helper"

RSpec.describe ModuleModelDiscovery do
  describe ".call" do
    context "with authentication module" do
      it "discovers Authentication::User model" do
        results = described_class.call("authentication")
        expect(results).to be_an(Array)
        expect(results.length).to be >= 1

        user_entry = results.find { |r| r[:name] == "Authentication::User" }
        expect(user_entry).to be_present
        expect(user_entry[:table_name]).to eq("users")
        expect(user_entry[:columns_count]).to be > 0
      end
    end

    context "with nonexistent module" do
      it "returns empty array" do
        expect(described_class.call("nonexistent")).to eq([])
      end
    end

    context "with module that has no models" do
      it "returns empty array for modules with no model directory" do
        expect(described_class.call("empty_module")).to eq([])
      end
    end
  end
end
```

- [ ] **Step 2:** Run spec to verify it fails:
```bash
bundle exec rspec spec/services/module_model_discovery_spec.rb
```

- [ ] **Step 3:** Implement the service:

```ruby
# app/services/module_model_discovery.rb
# frozen_string_literal: true

class ModuleModelDiscovery
  def self.call(module_key)
    new(module_key).call
  end

  def initialize(module_key)
    @module_key = module_key
  end

  def call
    model_dir = Rails.root.join("app", "models", @module_key)
    return [] unless model_dir.directory?

    discover_models(model_dir)
  end

  private

  def discover_models(dir)
    Dir.glob(dir.join("**", "*.rb")).filter_map do |file_path|
      class_name = derive_class_name(file_path)
      klass = class_name.safe_constantize
      next unless klass && klass < ApplicationRecord

      {
        name: klass.name,
        table_name: klass.table_name,
        columns_count: klass.columns.size,
        associations_count: klass.reflect_on_all_associations.size
      }
    rescue StandardError
      nil
    end
  end

  def derive_class_name(file_path)
    relative = Pathname.new(file_path).relative_path_from(Rails.root.join("app", "models"))
    relative.to_s.delete_suffix(".rb").camelize
  end
end
```

- [ ] **Step 4:** Run spec to verify it passes:
```bash
bundle exec rspec spec/services/module_model_discovery_spec.rb
```

---

## Task 5: Build ModuleRouteDiscovery service

**Files:**
- Create: `app/services/module_route_discovery.rb`
- Create: `spec/services/module_route_discovery_spec.rb`

- [ ] **Step 1:** Write the spec:

```ruby
# spec/services/module_route_discovery_spec.rb
require "rails_helper"

RSpec.describe ModuleRouteDiscovery do
  describe ".call" do
    context "with authentication module" do
      it "discovers authentication routes" do
        results = described_class.call("authentication")
        expect(results).to be_an(Array)
        expect(results.length).to be > 0
      end

      it "returns route entries with required fields" do
        results = described_class.call("authentication")
        entry = results.first
        expect(entry).to have_key(:method)
        expect(entry).to have_key(:path)
        expect(entry).to have_key(:name)
        expect(entry).to have_key(:controller_action)
      end

      it "includes session routes" do
        results = described_class.call("authentication")
        actions = results.map { |r| r[:controller_action] }
        expect(actions).to include(a_string_matching(/authentication\/sessions/))
      end
    end

    context "with nonexistent module" do
      it "returns empty array" do
        expect(described_class.call("nonexistent")).to eq([])
      end
    end
  end
end
```

- [ ] **Step 2:** Run spec to verify it fails:
```bash
bundle exec rspec spec/services/module_route_discovery_spec.rb
```

- [ ] **Step 3:** Implement the service:

```ruby
# app/services/module_route_discovery.rb
# frozen_string_literal: true

class ModuleRouteDiscovery
  HTTP_METHOD_ORDER = %w[GET POST PATCH PUT DELETE].freeze

  def self.call(module_key)
    new(module_key).call
  end

  def initialize(module_key)
    @module_key = module_key
    @prefix = "#{module_key}/"
  end

  def call
    routes = Rails.application.routes.routes.filter_map do |route|
      next unless matches_module?(route)

      build_entry(route)
    end

    routes.sort_by { |r| [r[:path], HTTP_METHOD_ORDER.index(r[:method]) || 99] }
  end

  private

  def matches_module?(route)
    controller = route.defaults[:controller].to_s
    controller.start_with?(@prefix)
  end

  def build_entry(route)
    verb = extract_method(route)
    return nil if verb.blank?

    {
      method: verb,
      path: route.path.spec.to_s.gsub("(.:format)", ""),
      name: route.name,
      controller_action: "#{route.defaults[:controller]}##{route.defaults[:action]}"
    }
  end

  def extract_method(route)
    verb = route.verb
    return verb if verb.is_a?(String) && verb.present?

    verb.to_s.scan(/[A-Z]+/).first
  end
end
```

- [ ] **Step 4:** Run spec to verify it passes:
```bash
bundle exec rspec spec/services/module_route_discovery_spec.rb
```

---

## Task 6: Build FeatureModuleListItemComponent

**Files:**
- Create: `app/components/feature_module_list_item_component.rb`
- Create: `app/components/feature_module_list_item_component.html.erb`
- Create: `spec/components/feature_module_list_item_component_spec.rb`
- Delete: `app/components/feature_module_card_component.rb`
- Delete: `app/components/feature_module_card_component.html.erb`
- Delete: `spec/components/feature_module_card_component_spec.rb`

- [ ] **Step 1:** Write the spec:

```ruby
# spec/components/feature_module_list_item_component_spec.rb
require "rails_helper"

RSpec.describe FeatureModuleListItemComponent, type: :component do
  let(:feature_mod) { create(:feature_module, key: "test_mod", name: "Test Module", description: "A test module") }
  let(:customer) { create(:customer) }

  context "when enabled" do
    it "renders module name and enabled status" do
      render_inline(described_class.new(feature_module: feature_mod, enabled: true, customer_id: customer.id))
      expect(page).to have_text("Test Module")
      expect(page).to have_text("Enabled")
      expect(page).to have_link("Details")
    end
  end

  context "when not enabled" do
    it "renders available status" do
      render_inline(described_class.new(feature_module: feature_mod, enabled: false, customer_id: customer.id))
      expect(page).to have_text("Available")
    end
  end
end
```

- [ ] **Step 2:** Implement the component:

```ruby
# app/components/feature_module_list_item_component.rb
class FeatureModuleListItemComponent < ApplicationComponent
  attr_reader :feature_module, :enabled, :customer_id

  def initialize(feature_module:, enabled:, customer_id:)
    @feature_module = feature_module
    @enabled = enabled
    @customer_id = customer_id
  end

  def enabled? = @enabled
  def required? = feature_module.required?

  def status_label
    if required? && enabled?
      "Required"
    elsif enabled?
      "Enabled"
    else
      "Available"
    end
  end

  def status_variant
    enabled? ? :success : :default
  end
end
```

```erb
<%# app/components/feature_module_list_item_component.html.erb %>
<div class="flex items-center justify-between py-4 border-b border-gray-100 last:border-b-0">
  <div class="min-w-0 flex-1">
    <div class="flex items-center gap-2">
      <p class="text-sm font-semibold text-gray-900"><%= feature_module.name %></p>
      <%= render BadgeComponent.new(variant: status_variant, size: :sm) { status_label } %>
    </div>
    <p class="mt-0.5 text-sm text-gray-500 truncate"><%= feature_module.description %></p>
  </div>
  <div class="ml-4 flex-shrink-0">
    <%= link_to "Details", feature_module_path(customer_id, feature_module),
        class: "text-sm font-medium text-indigo-600 hover:text-indigo-800 transition-colors" %>
  </div>
</div>
```

- [ ] **Step 3:** Run spec:
```bash
bundle exec rspec spec/components/feature_module_list_item_component_spec.rb
```

- [ ] **Step 4:** Delete old card component:
```bash
rm app/components/feature_module_card_component.rb
rm app/components/feature_module_card_component.html.erb
rm spec/components/feature_module_card_component_spec.rb
```

---

## Task 7: Redesign feature module index page

**Files:**
- Modify: `app/views/feature_modules/index.html.erb`

- [ ] **Step 1:** Rewrite the index page to a minimal clean list:

```erb
<%# app/views/feature_modules/index.html.erb %>
<div class="max-w-3xl mx-auto px-4 py-8">
  <header class="mb-6">
    <h1 class="text-xl font-bold text-gray-900">Feature Modules</h1>
    <p class="mt-1 text-sm text-gray-500">
      <%= @available_modules.size %> <%= "module".pluralize(@available_modules.size) %> available,
      <%= @enabled_module_ids.size %> enabled
    </p>
  </header>

  <%= render AlertComponent.new(message: notice, type: :success) %>
  <%= render AlertComponent.new(message: alert, type: :error) %>

  <% if @available_modules.any? %>
    <div class="bg-white border border-gray-200 rounded-lg divide-y divide-gray-100 px-4">
      <% @available_modules.each do |feature_module| %>
        <%= render FeatureModuleListItemComponent.new(
          feature_module: feature_module,
          enabled: @enabled_module_ids.include?(feature_module.id),
          customer_id: current_customer_id
        ) %>
      <% end %>
    </div>
  <% else %>
    <p class="text-sm text-gray-400 italic">No feature modules available.</p>
  <% end %>
</div>
```

- [ ] **Step 2:** Verify by visiting the page in browser or running feature module request specs.

---

## Task 8: Redesign feature module show page

**Files:**
- Modify: `app/controllers/feature_modules_controller.rb`
- Modify: `app/views/feature_modules/show.html.erb`

- [ ] **Step 1:** Update the controller's `show` action to pass discovery data:

```ruby
# In FeatureModulesController#show, after existing code:
def show
  @customer_feature = CustomerFeatureModule.find_by(
    customer_id: current_customer_id,
    feature_module_id: @feature_module.id
  )
  @module_models = ModuleModelDiscovery.call(@feature_module.key)
  @module_routes = ModuleRouteDiscovery.call(@feature_module.key)
end
```

- [ ] **Step 2:** Rewrite `app/views/feature_modules/show.html.erb` as a single-column stacked layout:

The page has these sections (no tabs):
1. **Header** — back link, module name + status pill, enable/disable button
2. **About** — dl with key, version, status, description
3. **Models** — table with Name, Table, Columns columns from `@module_models`
4. **Routes** — table with Method (color-coded badge), Path, Name, Action from `@module_routes`
5. **Configuration Schema** — list of available settings (if any)
6. **My Configuration** — status + config form (if enabled)
7. **Required Module** — owner-only toggle

Each section separated by `<div class="border-t border-gray-200 pt-6 mt-6">`.

HTTP method badges use:
- GET → `bg-green-100 text-green-700`
- POST → `bg-blue-100 text-blue-700`
- PATCH/PUT → `bg-amber-100 text-amber-700`
- DELETE → `bg-red-100 text-red-700`

- [ ] **Step 3:** Update `spec/requests/feature_modules_spec.rb` to verify the new sections render:
  - Show page includes "Models" heading
  - Show page includes "Routes" heading
  - Show page includes discovered model name (e.g., "Authentication::User")
  - Show page includes route entries

- [ ] **Step 4:** Run feature module specs:
```bash
bundle exec rspec spec/requests/feature_modules_spec.rb
```

---

## Task 9: Final verification and cleanup

- [ ] **Step 1:** Remove empty old directories:
```bash
rmdir app/controllers/auth/ 2>/dev/null
rmdir app/controllers/admin/ 2>/dev/null
rmdir app/views/admin/ 2>/dev/null
rmdir spec/requests/auth/ 2>/dev/null
rmdir spec/requests/admin/ 2>/dev/null
```

- [ ] **Step 2:** Grep for stale references:
```bash
grep -r "Auth::Sessions\|Auth::Registrations\|Auth::Passwords\|Auth::Mfa\|Admin::Users" app/ spec/ config/ --include="*.rb" --include="*.erb" -l
grep -r "class User <\|User\.\|\"User\"" app/models/ app/controllers/ app/services/ --include="*.rb" -l
```
Fix any remaining references.

- [ ] **Step 3:** Run full test suite:
```bash
bundle exec rspec
```

- [ ] **Step 4:** Restart server and verify pages load:
```bash
kill $(cat tmp/pids/server.pid 2>/dev/null) 2>/dev/null; sleep 1; bin/rails server -d -b 0.0.0.0 -p 3000
```
Visit feature modules index and show pages in browser.
