# Dashboard Foundation Refactor — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat 4-section dashboard nav with a three-zone (Workspace / Admin / Platform) shell, a professional top bar (workspace switcher, search palette, help, notifications, user menu), a two-row nav that collapses to a mobile accordion drawer, and a per-page max-width helper — without touching any page-level view.

**Architecture:** Zones are declared in a `Dashboard::ZoneRegistry` service and gated per user via a `ZoneDefinition#permitted_for?` predicate. The existing `ShellComponent` grows a zone-tabs row above the section-tabs row. `TopbarComponent` absorbs four new topbar children (`WorkspaceSwitcherComponent`, `SearchButtonComponent` + palette, `HelpMenuComponent`, `NotificationsButtonComponent`). Mobile collapses everything into a restructured `DrawerComponent` with a zone pill + section accordion + per-section sidebar tree. A `container_width` layout helper reads `content_for(:container_width)` and maps `:narrow|:wide|:full` to a Tailwind class. Admin and Platform zones render empty-state landings in Phase 1 — no existing page is relocated.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, ViewComponent, TailwindCSS v4, StimulusJS, RSpec, Capybara.

**Spec:** `docs/superpowers/specs/2026-04-28-dashboard-foundation-refactor-design.md`

---

## File Structure

### New files

- `app/services/dashboard/zone_definition.rb` — POJO with `key`, `label`, `path_proc`, `sections`, `permitted_by`; method `permitted_for?(user)`.
- `app/services/dashboard/zone_registry.rb` — `ZONES` array + `for(user)`.
- `app/controllers/dashboard/admin_controller.rb` — zone root, empty-state.
- `app/controllers/dashboard/platform_controller.rb` — zone root, empty-state.
- `app/views/dashboard/admin/show.html.erb` — empty-state view.
- `app/views/dashboard/platform/show.html.erb` — empty-state view.
- `app/components/dashboard/zone_tabs_component.rb` + `.html.erb`
- `app/components/dashboard/workspace_switcher_component.rb` + `.html.erb`
- `app/components/dashboard/search_button_component.rb` + `.html.erb`
- `app/components/dashboard/search_palette_component.rb` + `.html.erb`
- `app/components/dashboard/help_menu_component.rb` + `.html.erb`
- `app/components/dashboard/notifications_button_component.rb` + `.html.erb`
- `app/components/dashboard/empty_zone_component.rb` + `.html.erb` — shared empty-state for Admin/Platform landings.
- `app/javascript/controllers/dashboard_zone_tabs_controller.js`
- `app/javascript/controllers/dashboard_search_controller.js`
- `app/javascript/controllers/dashboard_workspace_switcher_controller.js`
- `app/javascript/controllers/dashboard_help_menu_controller.js`
- `app/helpers/dashboard_layout_helper.rb` — `container_width_class`.

### Modified files

- `config/routes.rb` — add `admin` and `platform` routes under tenant scope.
- `app/controllers/application_controller.rb` — add `current_dashboard_zone`, `require_platform_owner!`, `require_admin_or_owner!`; update `DASHBOARD_SECTION_BY_PATH_PREFIX`.
- `app/models/authentication/user.rb` — add `platform_owner?` predicate.
- `app/components/dashboard/shell_component.{rb,html.erb}` — accept `current_zone`, `zones`, `sections`; render zone-tabs row; wrap `yield` in container-width helper.
- `app/components/dashboard/topbar_component.{rb,html.erb}` — accept `switchable_customers`, `zones`, `current_zone`; render new topbar children.
- `app/components/dashboard/section_tabs_component.{rb,html.erb}` — remove `TABS` constant, accept `sections:`; remove mobile variant.
- `app/components/dashboard/drawer_component.{rb,html.erb}` — accordion (zone pill → sections → tree); slide animation.
- `app/javascript/controllers/dashboard_drawer_controller.js` — handle slide animation + in-drawer zone switching.
- `app/services/dashboard/sidebar_builder.rb` — accept a `section` argument; builds tree for that section only.
- `app/views/layouts/dashboard.html.erb` — pass new props; reflect the new shell contract.

### Test files (new)

- `spec/models/authentication/user_platform_owner_spec.rb`
- `spec/services/dashboard/zone_definition_spec.rb`
- `spec/services/dashboard/zone_registry_spec.rb`
- `spec/controllers/application_controller_zone_helpers_spec.rb`
- `spec/requests/dashboard/admin_zone_spec.rb`
- `spec/requests/dashboard/platform_zone_spec.rb`
- `spec/components/dashboard/zone_tabs_component_spec.rb`
- `spec/components/dashboard/workspace_switcher_component_spec.rb`
- `spec/components/dashboard/search_button_component_spec.rb`
- `spec/components/dashboard/search_palette_component_spec.rb`
- `spec/components/dashboard/help_menu_component_spec.rb`
- `spec/components/dashboard/notifications_button_component_spec.rb`
- `spec/components/dashboard/empty_zone_component_spec.rb`
- `spec/components/dashboard/shell_component_spec.rb` (update)
- `spec/components/dashboard/topbar_component_spec.rb` (update)
- `spec/components/dashboard/section_tabs_component_spec.rb` (update)
- `spec/components/dashboard/drawer_component_spec.rb` (update)
- `spec/helpers/dashboard_layout_helper_spec.rb`
- `spec/system/dashboard/shell_navigation_spec.rb`
- `spec/system/dashboard/responsive_drawer_spec.rb`
- `spec/system/dashboard/search_palette_spec.rb`

---

## Conventions shared across tasks

- All Ruby files start with `# frozen_string_literal: true`.
- ViewComponent classes extend `ApplicationComponent`.
- Tests use RSpec. Component tests use `render_inline`.
- Customer IDs are 8-digit integers (route constraint `constraints: { customer_id: /\d{8}/ }`).
- Stimulus controllers import as `import { Controller } from "@hotwired/stimulus"`.
- Only TailwindCSS for styling; only StimulusJS for JS.
- Factories already exist for `authentication_user` and `customer` — reuse them.
- When a commit message is shown, the same `Co-Authored-By` footer is appended to every commit.

---

## Task 1: Add `platform_owner?` predicate to User

**Files:**
- Modify: `app/models/authentication/user.rb`
- Test: `spec/models/authentication/user_platform_owner_spec.rb`

- [ ] **Step 1.1: Write the failing test**

Create `spec/models/authentication/user_platform_owner_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::User, "#platform_owner?" do
  let(:user) { build(:authentication_user, email: "owner@example.com") }

  around do |example|
    original = ENV["PLATFORM_OWNER_EMAILS"]
    example.run
  ensure
    ENV["PLATFORM_OWNER_EMAILS"] = original
  end

  it "returns false when PLATFORM_OWNER_EMAILS is unset" do
    ENV.delete("PLATFORM_OWNER_EMAILS")
    expect(user.platform_owner?).to eq(false)
  end

  it "returns false when PLATFORM_OWNER_EMAILS is blank" do
    ENV["PLATFORM_OWNER_EMAILS"] = ""
    expect(user.platform_owner?).to eq(false)
  end

  it "returns true when user's email is listed in PLATFORM_OWNER_EMAILS" do
    ENV["PLATFORM_OWNER_EMAILS"] = "owner@example.com,root@example.com"
    expect(user.platform_owner?).to eq(true)
  end

  it "is case-insensitive and ignores surrounding whitespace" do
    ENV["PLATFORM_OWNER_EMAILS"] = " Owner@Example.COM , root@example.com "
    expect(user.platform_owner?).to eq(true)
  end

  it "returns false when email is not listed" do
    ENV["PLATFORM_OWNER_EMAILS"] = "root@example.com"
    expect(user.platform_owner?).to eq(false)
  end
end
```

- [ ] **Step 1.2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/authentication/user_platform_owner_spec.rb -fd`
Expected: 5 failures with `NoMethodError: undefined method 'platform_owner?'`.

- [ ] **Step 1.3: Add the predicate**

Edit `app/models/authentication/user.rb`. Insert this method inside the class, below `admin_or_owner?` (around line 130):

```ruby
def platform_owner?
  list = ENV["PLATFORM_OWNER_EMAILS"].to_s
  return false if list.strip.empty?

  allowed = list.split(",").map { |e| e.strip.downcase }
  allowed.include?(email.to_s.downcase)
end
```

- [ ] **Step 1.4: Run tests**

Run: `bundle exec rspec spec/models/authentication/user_platform_owner_spec.rb -fd`
Expected: 5 examples, 0 failures.

- [ ] **Step 1.5: Commit**

```bash
git add app/models/authentication/user.rb spec/models/authentication/user_platform_owner_spec.rb
git commit -m "$(cat <<'EOF'
feat(auth): add User#platform_owner? predicate (env allowlist)

Phase 1 dashboard refactor needs a platform-owner gate that doesn't yet
require a schema change. Reads PLATFORM_OWNER_EMAILS (comma-separated,
case-insensitive). Phase 3 will replace with a schema column.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `ZoneDefinition` POJO

**Files:**
- Create: `app/services/dashboard/zone_definition.rb`
- Test: `spec/services/dashboard/zone_definition_spec.rb`

- [ ] **Step 2.1: Write the failing test**

Create `spec/services/dashboard/zone_definition_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::ZoneDefinition do
  let(:user) { double("User", admin_or_owner?: false, platform_owner?: false) }
  let(:admin_user) { double("User", admin_or_owner?: true, platform_owner?: false) }

  describe "#permitted_for?" do
    it "returns true when permitted_by is nil" do
      zone = described_class.new(key: :workspace, label: "Workspace", permitted_by: nil, sections: [])
      expect(zone.permitted_for?(user)).to eq(true)
    end

    it "calls a Proc with the user and returns its value" do
      zone = described_class.new(key: :admin, label: "Admin", permitted_by: ->(u) { u.admin_or_owner? }, sections: [])
      expect(zone.permitted_for?(user)).to eq(false)
      expect(zone.permitted_for?(admin_user)).to eq(true)
    end

    it "sends a Symbol to the user" do
      zone = described_class.new(key: :admin, label: "Admin", permitted_by: :admin_or_owner?, sections: [])
      expect(zone.permitted_for?(user)).to eq(false)
      expect(zone.permitted_for?(admin_user)).to eq(true)
    end

    it "returns false when user is nil" do
      zone = described_class.new(key: :admin, label: "Admin", permitted_by: :admin_or_owner?, sections: [])
      expect(zone.permitted_for?(nil)).to eq(false)
    end
  end

  describe "#sections" do
    it "returns an empty array when none provided" do
      zone = described_class.new(key: :admin, label: "Admin", sections: nil)
      expect(zone.sections).to eq([])
    end

    it "freezes the provided sections" do
      zone = described_class.new(key: :admin, label: "Admin", sections: [{ key: :x, label: "X" }])
      expect(zone.sections).to be_frozen
    end
  end
end
```

- [ ] **Step 2.2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/dashboard/zone_definition_spec.rb -fd`
Expected: `NameError: uninitialized constant Dashboard::ZoneDefinition`.

- [ ] **Step 2.3: Implement the POJO**

Create `app/services/dashboard/zone_definition.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class ZoneDefinition
    attr_reader :key, :label, :path_proc, :sections, :permitted_by

    def initialize(key:, label:, sections: nil, path_proc: nil, permitted_by: nil)
      @key = key
      @label = label
      @path_proc = path_proc
      @sections = (sections || []).freeze
      @permitted_by = permitted_by
    end

    def permitted_for?(user)
      return false if user.nil?
      return true if permitted_by.nil?

      case permitted_by
      when Proc   then !!permitted_by.call(user)
      when Symbol then !!user.public_send(permitted_by)
      else
        raise ArgumentError, "permitted_by must be nil, a Proc, or a Symbol"
      end
    end

    def path_for(customer)
      path_proc ? path_proc.call(customer) : nil
    end
  end
end
```

- [ ] **Step 2.4: Run tests**

Run: `bundle exec rspec spec/services/dashboard/zone_definition_spec.rb -fd`
Expected: 6 examples, 0 failures.

- [ ] **Step 2.5: Commit**

```bash
git add app/services/dashboard/zone_definition.rb spec/services/dashboard/zone_definition_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): add Dashboard::ZoneDefinition POJO

Describes a navigation zone (key, label, sections, permission gate). Used
by ZoneRegistry and ZoneTabsComponent in the new three-zone shell.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `ZoneRegistry` service

**Files:**
- Create: `app/services/dashboard/zone_registry.rb`
- Test: `spec/services/dashboard/zone_registry_spec.rb`

- [ ] **Step 3.1: Write the failing test**

Create `spec/services/dashboard/zone_registry_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::ZoneRegistry do
  let(:member)    { double("User", admin_or_owner?: false, platform_owner?: false) }
  let(:admin)     { double("User", admin_or_owner?: true,  platform_owner?: false) }
  let(:platform)  { double("User", admin_or_owner?: true,  platform_owner?: true)  }

  describe ".for" do
    it "returns only :workspace for a plain member" do
      expect(described_class.for(member).map(&:key)).to eq([:workspace])
    end

    it "returns :workspace and :admin for an admin/owner" do
      expect(described_class.for(admin).map(&:key)).to eq([:workspace, :admin])
    end

    it "returns all three zones for a platform owner" do
      expect(described_class.for(platform).map(&:key)).to eq([:workspace, :admin, :platform])
    end

    it "returns an empty array when user is nil" do
      expect(described_class.for(nil)).to eq([])
    end
  end

  describe ".zone" do
    it "fetches a zone by key" do
      expect(described_class.zone(:workspace).label).to eq("Workspace")
    end

    it "returns nil for an unknown key" do
      expect(described_class.zone(:nope)).to be_nil
    end
  end

  describe "workspace sections (Phase 1)" do
    it "includes home, entity_entries, pages, modules, settings" do
      keys = described_class.zone(:workspace).sections.map { |s| s[:key] }
      expect(keys).to eq(%i[home entity_entries pages modules settings])
    end
  end

  describe "admin and platform zones (Phase 1)" do
    it "have no sections yet" do
      expect(described_class.zone(:admin).sections).to eq([])
      expect(described_class.zone(:platform).sections).to eq([])
    end
  end
end
```

- [ ] **Step 3.2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/dashboard/zone_registry_spec.rb -fd`
Expected: `NameError: uninitialized constant Dashboard::ZoneRegistry`.

- [ ] **Step 3.3: Implement the registry**

Create `app/services/dashboard/zone_registry.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class ZoneRegistry
    ZONES = [
      ZoneDefinition.new(
        key: :workspace,
        label: "Workspace",
        path_proc: ->(customer) { "/#{customer.id}/" },
        permitted_by: nil,
        sections: [
          { key: :home,           label: "Home",           path_prefix: "/" },
          { key: :entity_entries, label: "Entity Entries", path_prefix: "/dashboard/entity_entries" },
          { key: :pages,          label: "Pages",          path_prefix: "/pages" },
          { key: :modules,        label: "Modules",        path_prefix: "/feature_modules" },
          { key: :settings,       label: "Settings",       path_prefix: "/dashboard/settings" }
        ]
      ),
      ZoneDefinition.new(
        key: :admin,
        label: "Admin",
        path_proc: ->(customer) { "/#{customer.id}/admin" },
        permitted_by: :admin_or_owner?,
        sections: []
      ),
      ZoneDefinition.new(
        key: :platform,
        label: "Platform",
        path_proc: ->(customer) { "/#{customer.id}/platform" },
        permitted_by: :platform_owner?,
        sections: []
      )
    ].freeze

    def self.for(user)
      return [] if user.nil?

      ZONES.select { |z| z.permitted_for?(user) }
    end

    def self.zone(key)
      ZONES.find { |z| z.key == key }
    end
  end
end
```

- [ ] **Step 3.4: Run tests**

Run: `bundle exec rspec spec/services/dashboard/zone_registry_spec.rb -fd`
Expected: 9 examples, 0 failures.

- [ ] **Step 3.5: Commit**

```bash
git add app/services/dashboard/zone_registry.rb spec/services/dashboard/zone_registry_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): add ZoneRegistry with workspace/admin/platform zones

Declarative zone definitions for the three-zone shell. Admin and Platform
have empty section arrays in Phase 1; sections move in during Phase 3.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: ApplicationController helpers (`current_dashboard_zone`, gates)

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Test: `spec/controllers/application_controller_zone_helpers_spec.rb`

- [ ] **Step 4.1: Write the failing test**

Create `spec/controllers/application_controller_zone_helpers_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def show
      render plain: "zone=#{current_dashboard_zone} section=#{current_dashboard_section}"
    end
  end

  before do
    routes.draw { get ":customer_id/anything" => "anonymous#show", constraints: { customer_id: /\d{8}/ } }
  end

  describe "#current_dashboard_zone" do
    it "returns :workspace for a normal tenant path" do
      get :show, params: { customer_id: "12345678", anything: "pages" }
      expect(response.body).to include("zone=workspace")
    end
  end
end
```

Because controller anonymous specs are awkward with scoped routes, also add a simpler unit-ish test via `ActionDispatch::TestRequest` — replace the whole file with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, "zone helpers" do
  let(:controller) { described_class.new }

  def set_path(path)
    request = ActionDispatch::TestRequest.create
    request.path_info = path
    controller.instance_variable_set(:@_request, request)
  end

  describe "#current_dashboard_zone" do
    it "returns :workspace for the root tenant path" do
      set_path("/12345678/")
      expect(controller.send(:current_dashboard_zone)).to eq(:workspace)
    end

    it "returns :workspace for /pages" do
      set_path("/12345678/pages")
      expect(controller.send(:current_dashboard_zone)).to eq(:workspace)
    end

    it "returns :admin for /admin and any sub-path" do
      set_path("/12345678/admin")
      expect(controller.send(:current_dashboard_zone)).to eq(:admin)
      set_path("/12345678/admin/users")
      expect(controller.send(:current_dashboard_zone)).to eq(:admin)
    end

    it "returns :platform for /platform and any sub-path" do
      set_path("/12345678/platform")
      expect(controller.send(:current_dashboard_zone)).to eq(:platform)
      set_path("/12345678/platform/flowcharts")
      expect(controller.send(:current_dashboard_zone)).to eq(:platform)
    end

    it "does not mistake a path prefix (e.g. /adminstrative) for :admin" do
      set_path("/12345678/administrative")
      expect(controller.send(:current_dashboard_zone)).to eq(:workspace)
    end
  end

  describe "#current_dashboard_section" do
    it "returns :home for the tenant root" do
      set_path("/12345678/")
      expect(controller.send(:current_dashboard_section)).to eq(:home)
    end

    it "returns :pages for /pages" do
      set_path("/12345678/pages")
      expect(controller.send(:current_dashboard_section)).to eq(:pages)
    end
  end
end
```

- [ ] **Step 4.2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/application_controller_zone_helpers_spec.rb -fd`
Expected: failures — `current_dashboard_zone` is missing; `current_dashboard_section` defaults to `:entity_entries` instead of `:home`.

- [ ] **Step 4.3: Add the helpers**

Edit `app/controllers/application_controller.rb`. Replace the `DASHBOARD_SECTION_BY_PATH_PREFIX` constant and the `current_dashboard_section` method, and add a new `current_dashboard_zone` method and `require_platform_owner!` / `require_admin_or_owner!` gates:

Replace lines 29–99 of `application_controller.rb` with:

```ruby
  helper_method :current_dashboard_section, :current_dashboard_zone

  # ==========================================================================
  # Authorization Helpers
  # ==========================================================================

  def require_owner_role!
    return if current_customer&.owner?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access denied. Owner role required." }
      format.json { render json: { error: "Access denied. Owner role required." }, status: :forbidden }
    end
  end

  def require_admin_role!
    return if current_customer&.owner? || current_customer&.admin?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access denied. Admin role required." }
      format.json { render json: { error: "Access denied. Admin role required." }, status: :forbidden }
    end
  end

  def require_admin_or_owner!
    return if current_user&.admin_or_owner?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access denied. Admin or owner role required." }
      format.json { render json: { error: "Access denied. Admin or owner role required." }, status: :forbidden }
    end
  end

  def require_platform_owner!
    return if current_user&.platform_owner?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access denied. Platform owner role required." }
      format.json { render json: { error: "Access denied. Platform owner role required." }, status: :forbidden }
    end
  end

  def owner?
    current_customer&.owner?
  end

  def admin?
    current_customer&.owner? || current_customer&.admin?
  end

  helper_method :owner?, :admin?

  def dashboard_layout
    return "application" unless Current.customer
    PLATFORM_OWNER_CONTROLLERS.include?(self.class.name) ? "application" : "dashboard"
  end

  # --------------------------------------------------------------------------
  # Zone & section inference from request path
  # --------------------------------------------------------------------------

  def current_dashboard_zone
    tenant_relative = tenant_relative_path
    return :admin    if tenant_relative.start_with?("/admin")    && !tenant_relative.start_with?("/administrative")
    return :platform if tenant_relative.start_with?("/platform")
    :workspace
  end

  # Default dashboard section derived from the request path.
  DASHBOARD_SECTION_BY_PATH_PREFIX = {
    "/dashboard/entity_entries" => :entity_entries,
    "/dashboard/modules"        => :modules,
    "/dashboard/settings"       => :settings,
    "/pages"                    => :pages,
    "/feature_modules"          => :modules,
    "/authentication/admin"     => :settings,
    "/customers"                => :settings
  }.freeze

  def current_dashboard_section
    tr = tenant_relative_path
    return :home if tr == "" || tr == "/"

    DASHBOARD_SECTION_BY_PATH_PREFIX.each do |prefix, section|
      return section if tr.start_with?(prefix)
    end
    :home
  end

  private

  def tenant_relative_path
    request.path.to_s.sub(%r{\A/\d{8}}, "")
  end
```

Note the two behavioral changes vs the original:
1. The default section is now `:home` (was `:entity_entries`) — matches the new "Home is the zone root" design.
2. `/admin` and `/platform` are recognized as zone prefixes.

- [ ] **Step 4.4: Run the new spec**

Run: `bundle exec rspec spec/controllers/application_controller_zone_helpers_spec.rb -fd`
Expected: 7 examples, 0 failures.

- [ ] **Step 4.5: Run existing controller/request specs to check for regressions**

Run: `bundle exec rspec spec/controllers spec/requests -fd --fail-fast`
Expected: 0 failures. If any spec relied on the old `:entity_entries` default, update it to `:home`.

- [ ] **Step 4.6: Commit**

```bash
git add app/controllers/application_controller.rb spec/controllers/application_controller_zone_helpers_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): add zone helpers + admin/platform gates to ApplicationController

current_dashboard_zone reads the tenant-relative path; require_platform_owner!
and require_admin_or_owner! gate the new zone-root controllers. Default
section is now :home (was :entity_entries).

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Shared `EmptyZoneComponent`

**Files:**
- Create: `app/components/dashboard/empty_zone_component.rb`
- Create: `app/components/dashboard/empty_zone_component.html.erb`
- Test: `spec/components/dashboard/empty_zone_component_spec.rb`

- [ ] **Step 5.1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::EmptyZoneComponent, type: :component do
  it "renders the zone label in the heading" do
    render_inline(described_class.new(zone_label: "Admin"))
    expect(page).to have_css("h1", text: "Admin")
  end

  it "renders the coming-soon description" do
    render_inline(described_class.new(zone_label: "Platform"))
    expect(page).to have_text("Coming soon")
  end
end
```

- [ ] **Step 5.2: Run test**

Run: `bundle exec rspec spec/components/dashboard/empty_zone_component_spec.rb -fd`
Expected: `NameError: uninitialized constant Dashboard::EmptyZoneComponent`.

- [ ] **Step 5.3: Implement the component**

Create `app/components/dashboard/empty_zone_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class EmptyZoneComponent < ApplicationComponent
    def initialize(zone_label:)
      @zone_label = zone_label
    end

    attr_reader :zone_label
  end
end
```

Create `app/components/dashboard/empty_zone_component.html.erb`:

```erb
<section class="max-w-2xl mx-auto py-16 px-4 text-center">
  <div class="mx-auto w-12 h-12 rounded-full bg-indigo-50 flex items-center justify-center mb-4">
    <svg class="w-6 h-6 text-indigo-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path stroke-linecap="round" stroke-linejoin="round"
            d="M12 6v6l4 2m4-2a8 8 0 11-16 0 8 8 0 0116 0z"/>
    </svg>
  </div>
  <h1 class="text-xl font-semibold text-gray-900 mb-2"><%= zone_label %></h1>
  <p class="text-sm text-gray-600">
    Coming soon — this area will house <%= zone_label.downcase %> tools.
    Navigation lives here; content will land in a future release.
  </p>
</section>
```

- [ ] **Step 5.4: Run tests**

Run: `bundle exec rspec spec/components/dashboard/empty_zone_component_spec.rb -fd`
Expected: 2 examples, 0 failures.

- [ ] **Step 5.5: Commit**

```bash
git add app/components/dashboard/empty_zone_component.rb app/components/dashboard/empty_zone_component.html.erb spec/components/dashboard/empty_zone_component_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): add EmptyZoneComponent for Admin/Platform landings

Phase 1 ships zone shells without content; this component renders a
consistent "coming soon" landing inside the new zones.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Admin & Platform zone controllers + routes

**Files:**
- Create: `app/controllers/dashboard/admin_controller.rb`
- Create: `app/controllers/dashboard/platform_controller.rb`
- Create: `app/views/dashboard/admin/show.html.erb`
- Create: `app/views/dashboard/platform/show.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/dashboard/admin_zone_spec.rb`
- Test: `spec/requests/dashboard/platform_zone_spec.rb`

- [ ] **Step 6.1: Add the routes**

Edit `config/routes.rb`. Locate the tenant scope around line 42 (`scope "/:customer_id", constraints: { customer_id: /\d{8}/ } do`). Add just inside that scope, **after** the `get "/", to: "dashboard/landing#show", as: :dashboard_root` line:

```ruby
    get "admin",    to: "dashboard/admin#show",    as: :dashboard_admin_root
    get "platform", to: "dashboard/platform#show", as: :dashboard_platform_root
```

- [ ] **Step 6.2: Write the failing request specs**

Create `spec/requests/dashboard/admin_zone_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Admin zone", type: :request do
  let(:customer) { create(:customer) }
  let(:member)   { create(:authentication_user, customer: customer, role: :member) }
  let(:admin)    { create(:authentication_user, customer: customer, role: :admin) }

  before { host! "www.example.com" }

  context "as a member" do
    before { sign_in member }

    it "is denied access with a flash alert and redirect" do
      get "/#{customer.id}/admin"
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(flash[:alert]).to include("Admin or owner")
    end
  end

  context "as an admin" do
    before { sign_in admin }

    it "renders the empty-state landing" do
      get "/#{customer.id}/admin"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coming soon")
    end
  end

  context "when not signed in" do
    it "redirects to the sign-in page" do
      get "/#{customer.id}/admin"
      expect(response).to have_http_status(:redirect)
    end
  end
end
```

Create `spec/requests/dashboard/platform_zone_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Platform zone", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:authentication_user, customer: customer, role: :admin, email: "admin@example.com") }
  let(:platform) { create(:authentication_user, customer: customer, role: :owner, email: "platform@example.com") }

  before { host! "www.example.com" }

  around do |example|
    original = ENV["PLATFORM_OWNER_EMAILS"]
    ENV["PLATFORM_OWNER_EMAILS"] = "platform@example.com"
    example.run
  ensure
    ENV["PLATFORM_OWNER_EMAILS"] = original
  end

  context "as an admin who is not a platform owner" do
    before { sign_in admin }

    it "is denied access" do
      get "/#{customer.id}/platform"
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(flash[:alert]).to include("Platform owner")
    end
  end

  context "as a platform owner" do
    before { sign_in platform }

    it "renders the empty-state landing" do
      get "/#{customer.id}/platform"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coming soon")
    end
  end
end
```

- [ ] **Step 6.3: Run tests and confirm they fail**

Run: `bundle exec rspec spec/requests/dashboard/admin_zone_spec.rb spec/requests/dashboard/platform_zone_spec.rb -fd`
Expected: failures — controllers missing.

- [ ] **Step 6.4: Implement the controllers**

Create `app/controllers/dashboard/admin_controller.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class AdminController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin_or_owner!

    def show
      # Phase 1: empty-state landing. Phase 3 replaces with real content.
    end
  end
end
```

Create `app/controllers/dashboard/platform_controller.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class PlatformController < ApplicationController
    before_action :authenticate_user!
    before_action :require_platform_owner!

    def show
      # Phase 1: empty-state landing. Phase 3 replaces with real content.
    end
  end
end
```

Create `app/views/dashboard/admin/show.html.erb`:

```erb
<%= render Dashboard::EmptyZoneComponent.new(zone_label: "Admin") %>
```

Create `app/views/dashboard/platform/show.html.erb`:

```erb
<%= render Dashboard::EmptyZoneComponent.new(zone_label: "Platform") %>
```

- [ ] **Step 6.5: Run tests**

Run: `bundle exec rspec spec/requests/dashboard/admin_zone_spec.rb spec/requests/dashboard/platform_zone_spec.rb -fd`
Expected: 5 examples, 0 failures.

- [ ] **Step 6.6: Commit**

```bash
git add app/controllers/dashboard/admin_controller.rb app/controllers/dashboard/platform_controller.rb app/views/dashboard/admin/show.html.erb app/views/dashboard/platform/show.html.erb config/routes.rb spec/requests/dashboard/admin_zone_spec.rb spec/requests/dashboard/platform_zone_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): add Admin and Platform zone roots with empty-state

Two new routes at /:customer_id/admin and /:customer_id/platform, gated by
role. Phase 1 renders a consistent empty-state; Phase 3 populates content.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `DashboardLayoutHelper` and container-width

**Files:**
- Create: `app/helpers/dashboard_layout_helper.rb`
- Test: `spec/helpers/dashboard_layout_helper_spec.rb`

- [ ] **Step 7.1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardLayoutHelper, type: :helper do
  describe "#container_width_class" do
    it "returns max-w-3xl for :narrow" do
      expect(helper.container_width_class(:narrow)).to eq("max-w-3xl mx-auto px-4 sm:px-6 lg:px-8")
    end

    it "returns max-w-7xl for :wide" do
      expect(helper.container_width_class(:wide)).to eq("max-w-7xl mx-auto px-4 sm:px-6 lg:px-8")
    end

    it "returns a full-width class for :full" do
      expect(helper.container_width_class(:full)).to eq("w-full px-4 sm:px-6 lg:px-8")
    end

    it "returns :wide for nil / unknown" do
      expect(helper.container_width_class(nil)).to eq(helper.container_width_class(:wide))
      expect(helper.container_width_class(:whatever)).to eq(helper.container_width_class(:wide))
    end

    it "accepts strings and symbols interchangeably" do
      expect(helper.container_width_class("narrow")).to eq(helper.container_width_class(:narrow))
    end
  end
end
```

- [ ] **Step 7.2: Run test to verify it fails**

Run: `bundle exec rspec spec/helpers/dashboard_layout_helper_spec.rb -fd`
Expected: `NameError: uninitialized constant DashboardLayoutHelper`.

- [ ] **Step 7.3: Implement the helper**

Create `app/helpers/dashboard_layout_helper.rb`:

```ruby
# frozen_string_literal: true

module DashboardLayoutHelper
  WIDTH_CLASSES = {
    narrow: "max-w-3xl mx-auto px-4 sm:px-6 lg:px-8",
    wide:   "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8",
    full:   "w-full px-4 sm:px-6 lg:px-8"
  }.freeze

  def container_width_class(tier)
    key = tier.to_s.to_sym if tier
    WIDTH_CLASSES.fetch(key, WIDTH_CLASSES[:wide])
  end
end
```

- [ ] **Step 7.4: Run tests**

Run: `bundle exec rspec spec/helpers/dashboard_layout_helper_spec.rb -fd`
Expected: 5 examples, 0 failures.

- [ ] **Step 7.5: Commit**

```bash
git add app/helpers/dashboard_layout_helper.rb spec/helpers/dashboard_layout_helper_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): container-width helper (narrow/wide/full)

Phase 1 introduces the mechanism; pages opt in via content_for
(:container_width, :narrow). Default remains :wide.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `SidebarBuilder` accepts a section argument

**Files:**
- Modify: `app/services/dashboard/sidebar_builder.rb`
- Modify: existing `spec/services/dashboard/sidebar_builder_spec.rb` if present
- Test: add cases to the sidebar builder spec (or create one)

- [ ] **Step 8.1: Check for existing spec**

Run: `ls spec/services/dashboard/ | grep sidebar_builder`
If `sidebar_builder_spec.rb` exists, read it first and preserve existing behavior in the TDD step. If it does not exist, create it.

- [ ] **Step 8.2: Write the failing test**

Create (or augment) `spec/services/dashboard/sidebar_builder_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SidebarBuilder do
  let(:user)     { create(:authentication_user, role: :member) }
  let(:customer) { user.customer }
  let(:context) do
    Dashboard::DashboardContext.new(
      current_user:     user,
      current_customer: customer,
      current_section:  section,
      request_path:     "/#{customer.id}/dashboard/entity_entries"
    )
  end

  context "without a section argument (backward-compat)" do
    let(:section) { :entity_entries }

    it "returns a tree populated by all contributors" do
      tree = described_class.build(context)
      expect(tree).to be_a(Dashboard::SidebarTree)
      expect(tree.nodes_for(:entity_entries)).not_to be_empty
    end
  end

  context "with a specific section" do
    let(:section) { :pages }

    it "returns a tree restricted to that section" do
      tree = described_class.build(context, section: :pages)
      expect(tree.nodes_for(:pages)).not_to be_empty
      expect(tree.nodes_for(:entity_entries)).to eq([])
    end
  end
end
```

- [ ] **Step 8.3: Run test**

Run: `bundle exec rspec spec/services/dashboard/sidebar_builder_spec.rb -fd`
Expected: failure — `build` takes exactly 1 argument.

- [ ] **Step 8.4: Add the optional section parameter**

Replace `app/services/dashboard/sidebar_builder.rb` with:

```ruby
# frozen_string_literal: true

module Dashboard
  class SidebarBuilder
    def self.build(context, section: nil)
      tree = SidebarTree.new
      SidebarContributor.registry.each do |contributor_class|
        contributor_class.new(context).contribute.each do |node|
          next if section && node.section != section
          tree.add(node)
        end
      end
      PermissionFilter.apply(tree, context.current_user)
    end
  end
end
```

- [ ] **Step 8.5: Run full sidebar and dashboard spec suite**

Run: `bundle exec rspec spec/services/dashboard spec/components/dashboard -fd`
Expected: 0 failures. Existing callers pass `build(context)` with no keyword and get the same full tree as before.

- [ ] **Step 8.6: Commit**

```bash
git add app/services/dashboard/sidebar_builder.rb spec/services/dashboard/sidebar_builder_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): SidebarBuilder accepts :section to scope the tree

New shell renders only the active section's sidebar. Default (no section
kwarg) preserves the full-tree behavior for the mobile drawer and any
caller not yet migrated.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `SectionTabsComponent` refactor (remove TABS, accept sections prop)

**Files:**
- Modify: `app/components/dashboard/section_tabs_component.rb`
- Modify: `app/components/dashboard/section_tabs_component.html.erb`
- Modify/create: `spec/components/dashboard/section_tabs_component_spec.rb`

- [ ] **Step 9.1: Write the failing test**

Create `spec/components/dashboard/section_tabs_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SectionTabsComponent, type: :component do
  let(:customer) { build_stubbed(:customer) }
  let(:sections) do
    [
      { key: :home,           label: "Home",           path_prefix: "/" },
      { key: :entity_entries, label: "Entity Entries", path_prefix: "/dashboard/entity_entries" },
      { key: :pages,          label: "Pages",          path_prefix: "/pages" }
    ]
  end

  it "renders a tab link for each section" do
    render_inline(described_class.new(customer: customer, sections: sections, current_section: :pages))

    expect(page).to have_link("Home",           href: "/#{customer.id}/")
    expect(page).to have_link("Entity Entries", href: "/#{customer.id}/dashboard/entity_entries")
    expect(page).to have_link("Pages",          href: "/#{customer.id}/pages")
  end

  it "highlights the current section" do
    render_inline(described_class.new(customer: customer, sections: sections, current_section: :pages))

    active = page.find("a", text: "Pages")
    expect(active[:class]).to include("border-indigo-600")
  end

  it "renders nothing when sections is empty" do
    render_inline(described_class.new(customer: customer, sections: [], current_section: nil))
    expect(page.native.to_html.strip).to eq("")
  end
end
```

- [ ] **Step 9.2: Run test**

Run: `bundle exec rspec spec/components/dashboard/section_tabs_component_spec.rb -fd`
Expected: failures — initializer signature mismatch.

- [ ] **Step 9.3: Rewrite the component**

Replace `app/components/dashboard/section_tabs_component.rb` with:

```ruby
# frozen_string_literal: true

module Dashboard
  class SectionTabsComponent < ApplicationComponent
    def initialize(customer:, sections:, current_section:)
      @customer = customer
      @sections = sections || []
      @current_section = current_section
    end

    attr_reader :customer, :sections, :current_section

    def render?
      sections.any?
    end

    def path_for(section)
      "/#{customer.id}#{section[:path_prefix]}".sub(%r{/+\z}, "/")
    end

    def classes_for(section)
      base = "inline-flex items-center px-4 h-10 text-sm font-medium border-b-2 -mb-px " \
             "transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 rounded-t"
      if section[:key] == current_section
        "#{base} border-indigo-600 text-gray-900"
      else
        "#{base} border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300"
      end
    end
  end
end
```

Replace `app/components/dashboard/section_tabs_component.html.erb` with:

```erb
<nav class="hidden md:flex border-b border-gray-200 bg-white" aria-label="Dashboard sections">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex">
    <% sections.each do |section| %>
      <%= link_to section[:label], path_for(section), class: classes_for(section) %>
    <% end %>
  </div>
</nav>
```

The mobile dropdown variant is removed (the drawer handles mobile nav now).

- [ ] **Step 9.4: Run the section-tabs spec and component specs**

Run: `bundle exec rspec spec/components/dashboard/section_tabs_component_spec.rb -fd`
Expected: 3 examples, 0 failures.

- [ ] **Step 9.5: Check for callers still using old signature**

Run: `grep -rn "SectionTabsComponent.new" app/ spec/`
Expected: any remaining call sites should use the new `(customer:, sections:, current_section:)` signature. The shell component is updated in Task 15 and the drawer in Task 14 — until those tasks land, the layout won't render. That's OK for this task's commit because the layout is exercised end-to-end in Task 15.

- [ ] **Step 9.6: Commit**

```bash
git add app/components/dashboard/section_tabs_component.rb app/components/dashboard/section_tabs_component.html.erb spec/components/dashboard/section_tabs_component_spec.rb
git commit -m "$(cat <<'EOF'
refactor(dashboard): SectionTabsComponent accepts sections prop

TABS constant removed; sections are now supplied by the active zone.
Mobile dropdown variant dropped — drawer is the mobile nav.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `ZoneTabsComponent`

**Files:**
- Create: `app/components/dashboard/zone_tabs_component.rb`
- Create: `app/components/dashboard/zone_tabs_component.html.erb`
- Create: `app/javascript/controllers/dashboard_zone_tabs_controller.js`
- Test: `spec/components/dashboard/zone_tabs_component_spec.rb`

- [ ] **Step 10.1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::ZoneTabsComponent, type: :component do
  let(:customer) { build_stubbed(:customer) }
  let(:zones) do
    [
      Dashboard::ZoneDefinition.new(key: :workspace, label: "Workspace", path_proc: ->(c) { "/#{c.id}/" }, sections: [{ key: :home, label: "Home", path_prefix: "/" }]),
      Dashboard::ZoneDefinition.new(key: :admin,     label: "Admin",     path_proc: ->(c) { "/#{c.id}/admin" })
    ]
  end

  it "renders a tab for each zone" do
    render_inline(described_class.new(customer: customer, zones: zones, current_zone: :workspace))

    expect(page).to have_link("Workspace", href: "/#{customer.id}/")
    expect(page).to have_link("Admin",     href: "/#{customer.id}/admin")
  end

  it "highlights the current zone" do
    render_inline(described_class.new(customer: customer, zones: zones, current_zone: :admin))

    active = page.find("a", text: "Admin")
    expect(active[:class]).to include("bg-white")
    expect(active[:class]).to include("shadow-sm")
  end

  it "renders nothing when only one zone is available" do
    render_inline(described_class.new(customer: customer, zones: zones.take(1), current_zone: :workspace))
    expect(page.native.to_html.strip).to eq("")
  end

  it "attaches the Stimulus controller" do
    render_inline(described_class.new(customer: customer, zones: zones, current_zone: :workspace))
    expect(page).to have_css("[data-controller='dashboard-zone-tabs']")
  end
end
```

- [ ] **Step 10.2: Run test**

Run: `bundle exec rspec spec/components/dashboard/zone_tabs_component_spec.rb -fd`
Expected: `NameError: uninitialized constant Dashboard::ZoneTabsComponent`.

- [ ] **Step 10.3: Implement the component**

Create `app/components/dashboard/zone_tabs_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class ZoneTabsComponent < ApplicationComponent
    def initialize(customer:, zones:, current_zone:)
      @customer = customer
      @zones = zones || []
      @current_zone = current_zone
    end

    attr_reader :customer, :zones, :current_zone

    def render?
      zones.size > 1
    end

    def path_for(zone)
      zone.path_for(customer)
    end

    def classes_for(zone)
      base = "inline-flex items-center h-11 px-4 text-sm font-medium rounded-md transition-colors " \
             "focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500"
      if zone.key == current_zone
        "#{base} bg-white shadow-sm text-gray-900 ring-1 ring-gray-200"
      else
        "#{base} text-gray-600 hover:text-gray-900 hover:bg-gray-100"
      end
    end
  end
end
```

Create `app/components/dashboard/zone_tabs_component.html.erb`:

```erb
<nav class="hidden md:block bg-gray-50 border-b border-gray-200"
     aria-label="Dashboard zones"
     data-controller="dashboard-zone-tabs">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center gap-1 py-1.5">
    <% zones.each do |zone| %>
      <%= link_to zone.label,
                  path_for(zone),
                  class: classes_for(zone),
                  data: { dashboard_zone_tabs_target: "tab", zone_key: zone.key } %>
    <% end %>
  </div>
</nav>
```

Create `app/javascript/controllers/dashboard_zone_tabs_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Adds Left/Right arrow-key navigation across zone tabs.
export default class extends Controller {
  static targets = ["tab"]

  connect() {
    this.element.addEventListener("keydown", this.#onKeyDown)
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.#onKeyDown)
  }

  #onKeyDown = (event) => {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return
    const tabs = this.tabTargets
    const current = document.activeElement
    const idx = tabs.indexOf(current)
    if (idx === -1) return
    event.preventDefault()
    const delta = event.key === "ArrowRight" ? 1 : -1
    const next = tabs[(idx + delta + tabs.length) % tabs.length]
    next.focus()
  }
}
```

- [ ] **Step 10.4: Run test**

Run: `bundle exec rspec spec/components/dashboard/zone_tabs_component_spec.rb -fd`
Expected: 4 examples, 0 failures.

- [ ] **Step 10.5: Commit**

```bash
git add app/components/dashboard/zone_tabs_component.rb app/components/dashboard/zone_tabs_component.html.erb app/javascript/controllers/dashboard_zone_tabs_controller.js spec/components/dashboard/zone_tabs_component_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): add ZoneTabsComponent (top-level zone nav)

Segmented control between section tabs. Hides itself when user can only
access one zone. Arrow-key navigation via dashboard-zone-tabs Stimulus
controller.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: `WorkspaceSwitcherComponent`

**Files:**
- Create: `app/components/dashboard/workspace_switcher_component.rb`
- Create: `app/components/dashboard/workspace_switcher_component.html.erb`
- Create: `app/javascript/controllers/dashboard_workspace_switcher_controller.js`
- Test: `spec/components/dashboard/workspace_switcher_component_spec.rb`

- [ ] **Step 11.1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::WorkspaceSwitcherComponent, type: :component do
  let(:customer)  { build_stubbed(:customer, name: "Acme Inc") }
  let(:other)     { build_stubbed(:customer, name: "Beta LLC") }

  it "renders the customer name as a static label when there are no alternatives" do
    render_inline(described_class.new(customer: customer, switchable_customers: []))
    expect(page).to have_text("Acme Inc")
    expect(page).not_to have_css("[data-controller='dashboard-workspace-switcher']")
  end

  it "renders a dropdown trigger when there is more than one workspace" do
    render_inline(described_class.new(customer: customer, switchable_customers: [other]))
    expect(page).to have_css("[data-controller='dashboard-workspace-switcher']")
    expect(page).to have_css("button", text: "Acme Inc")
  end

  it "lists the other workspaces inside the dropdown" do
    render_inline(described_class.new(customer: customer, switchable_customers: [other]))
    expect(page).to have_link("Beta LLC", href: "/#{other.id}/")
  end

  it "highlights the current workspace in the list" do
    render_inline(described_class.new(customer: customer, switchable_customers: [other]))
    expect(page).to have_css("[aria-current='true']", text: "Acme Inc")
  end
end
```

- [ ] **Step 11.2: Run test**

Run: `bundle exec rspec spec/components/dashboard/workspace_switcher_component_spec.rb -fd`
Expected: `NameError`.

- [ ] **Step 11.3: Implement**

Create `app/components/dashboard/workspace_switcher_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class WorkspaceSwitcherComponent < ApplicationComponent
    def initialize(customer:, switchable_customers: [])
      @customer = customer
      @switchable_customers = Array(switchable_customers)
    end

    attr_reader :customer, :switchable_customers

    def interactive?
      switchable_customers.any?
    end

    def all_customers
      ([customer] + switchable_customers).uniq { |c| c.id }.sort_by { |c| c.name.to_s.downcase }
    end

    def initial_badge
      customer.name[0].to_s.upcase
    end
  end
end
```

Create `app/components/dashboard/workspace_switcher_component.html.erb`:

```erb
<% if interactive? %>
  <div class="relative" data-controller="dashboard-workspace-switcher">
    <button type="button"
            class="inline-flex items-center gap-2 h-9 px-2 rounded-md hover:bg-gray-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500"
            data-action="click->dashboard-workspace-switcher#toggle"
            aria-haspopup="menu"
            data-dashboard-workspace-switcher-target="trigger">
      <span class="w-7 h-7 bg-indigo-600 rounded-md flex items-center justify-center text-white text-[13px] font-semibold">
        <%= initial_badge %>
      </span>
      <span class="text-sm font-semibold text-gray-900 truncate max-w-[14rem]"><%= customer.name %></span>
      <svg class="w-4 h-4 text-gray-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/>
      </svg>
    </button>
    <div class="hidden absolute left-0 mt-2 w-64 bg-white border border-gray-200 rounded-md shadow-lg py-1 z-40"
         data-dashboard-workspace-switcher-target="panel"
         role="menu">
      <% all_customers.each do |c| %>
        <% current = c.id == customer.id %>
        <%= link_to "/#{c.id}/",
                    class: "flex items-center gap-2 px-3 py-2 text-sm hover:bg-gray-50 #{current ? 'bg-gray-50 text-gray-900 font-medium' : 'text-gray-700'}",
                    role: "menuitem",
                    aria: current ? { current: "true" } : {} do %>
          <span class="w-5 h-5 bg-indigo-600 rounded text-white text-[11px] flex items-center justify-center">
            <%= c.name[0].to_s.upcase %>
          </span>
          <span class="truncate"><%= c.name %></span>
        <% end %>
      <% end %>
    </div>
  </div>
<% else %>
  <div class="inline-flex items-center gap-2 h-9 px-2">
    <span class="w-7 h-7 bg-indigo-600 rounded-md flex items-center justify-center text-white text-[13px] font-semibold">
      <%= initial_badge %>
    </span>
    <span class="text-sm font-semibold text-gray-900 truncate max-w-[14rem]"><%= customer.name %></span>
  </div>
<% end %>
```

Create `app/javascript/controllers/dashboard_workspace_switcher_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "trigger"]

  connect() {
    this.boundOutside = (e) => { if (!this.element.contains(e.target)) this.close() }
    document.addEventListener("click", this.boundOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
  }

  toggle(event) {
    event.stopPropagation()
    this.panelTarget.classList.toggle("hidden")
  }

  close() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("hidden")
  }
}
```

- [ ] **Step 11.4: Run tests**

Run: `bundle exec rspec spec/components/dashboard/workspace_switcher_component_spec.rb -fd`
Expected: 4 examples, 0 failures.

- [ ] **Step 11.5: Commit**

```bash
git add app/components/dashboard/workspace_switcher_component.rb app/components/dashboard/workspace_switcher_component.html.erb app/javascript/controllers/dashboard_workspace_switcher_controller.js spec/components/dashboard/workspace_switcher_component_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): WorkspaceSwitcherComponent in topbar

Replaces the static customer-name label. Becomes a dropdown only when
the user has access to more than one workspace (platform owner case).

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: `SearchButtonComponent` + `SearchPaletteComponent` + Stimulus

**Files:**
- Create: `app/components/dashboard/search_button_component.rb` + erb
- Create: `app/components/dashboard/search_palette_component.rb` + erb
- Create: `app/javascript/controllers/dashboard_search_controller.js`
- Test: `spec/components/dashboard/search_button_component_spec.rb`
- Test: `spec/components/dashboard/search_palette_component_spec.rb`

- [ ] **Step 12.1: Write the failing tests**

```ruby
# spec/components/dashboard/search_button_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SearchButtonComponent, type: :component do
  it "renders a button with the ⌘K hint" do
    render_inline(described_class.new)
    expect(page).to have_css("button[aria-label='Open search']")
    expect(page).to have_css("kbd", text: "⌘K")
  end

  it "wires the click to the shared dashboard-search controller" do
    render_inline(described_class.new)
    expect(page).to have_css("button[data-action*='dashboard-search#open']")
  end
end
```

```ruby
# spec/components/dashboard/search_palette_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SearchPaletteComponent, type: :component do
  it "is hidden by default" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-dashboard-search-target='panel'].hidden")
  end

  it "renders a placeholder empty state" do
    render_inline(described_class.new)
    expect(page).to have_text("Search is coming soon")
  end
end
```

- [ ] **Step 12.2: Run tests**

Run: `bundle exec rspec spec/components/dashboard/search_button_component_spec.rb spec/components/dashboard/search_palette_component_spec.rb -fd`
Expected: failures.

- [ ] **Step 12.3: Implement**

Create `app/components/dashboard/search_button_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class SearchButtonComponent < ApplicationComponent
  end
end
```

Create `app/components/dashboard/search_button_component.html.erb`:

```erb
<button type="button"
        aria-label="Open search"
        class="inline-flex items-center gap-2 h-9 px-3 rounded-md bg-gray-50 hover:bg-gray-100 border border-gray-200 text-sm text-gray-500 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 md:min-w-[280px]"
        data-action="click->dashboard-search#open">
  <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
    <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-4.35-4.35m1.5-5.4a6.9 6.9 0 11-13.8 0 6.9 6.9 0 0113.8 0z"/>
  </svg>
  <span class="hidden md:inline">Search</span>
  <span class="hidden lg:inline-flex items-center gap-1 ml-auto">
    <kbd class="px-1.5 py-0.5 text-[11px] font-medium rounded border border-gray-200 bg-white text-gray-500">⌘K</kbd>
  </span>
</button>
```

Create `app/components/dashboard/search_palette_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class SearchPaletteComponent < ApplicationComponent
  end
end
```

Create `app/components/dashboard/search_palette_component.html.erb`:

```erb
<div class="hidden fixed inset-0 z-50"
     data-dashboard-search-target="panel"
     role="dialog"
     aria-modal="true"
     aria-labelledby="search-palette-title">
  <div class="absolute inset-0 bg-gray-900/40"
       data-action="click->dashboard-search#close"></div>
  <div class="relative mx-auto mt-24 max-w-xl bg-white rounded-lg shadow-xl border border-gray-200 overflow-hidden">
    <div class="flex items-center gap-2 px-4 h-12 border-b border-gray-200">
      <svg class="w-4 h-4 text-gray-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-4.35-4.35m1.5-5.4a6.9 6.9 0 11-13.8 0 6.9 6.9 0 0113.8 0z"/>
      </svg>
      <input type="text"
             placeholder="Search pages, entries, settings…"
             data-dashboard-search-target="input"
             class="flex-1 bg-transparent border-0 outline-none text-sm text-gray-900 placeholder-gray-400 focus:ring-0"
             aria-label="Search" />
      <kbd class="px-1.5 py-0.5 text-[11px] font-medium rounded border border-gray-200 bg-gray-50 text-gray-500">Esc</kbd>
    </div>
    <div class="py-10 px-6 text-center text-sm text-gray-500" id="search-palette-title">
      Search is coming soon. This palette will return results across pages,
      entries, and settings in a later release.
    </div>
  </div>
</div>
```

Create `app/javascript/controllers/dashboard_search_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input"]

  connect() {
    this.boundKeydown = (event) => {
      const meta = event.metaKey || event.ctrlKey
      if (meta && event.key.toLowerCase() === "k") {
        event.preventDefault()
        this.open()
      } else if (event.key === "Escape" && this.isOpen) {
        event.preventDefault()
        this.close()
      }
    }
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  get isOpen() {
    return this.hasPanelTarget && !this.panelTarget.classList.contains("hidden")
  }

  open() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.remove("hidden")
    if (this.hasInputTarget) this.inputTarget.focus()
  }

  close() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("hidden")
  }
}
```

- [ ] **Step 12.4: Run tests**

Run: `bundle exec rspec spec/components/dashboard/search_button_component_spec.rb spec/components/dashboard/search_palette_component_spec.rb -fd`
Expected: 4 examples, 0 failures.

- [ ] **Step 12.5: Commit**

```bash
git add app/components/dashboard/search_button_component.rb app/components/dashboard/search_button_component.html.erb app/components/dashboard/search_palette_component.rb app/components/dashboard/search_palette_component.html.erb app/javascript/controllers/dashboard_search_controller.js spec/components/dashboard/search_button_component_spec.rb spec/components/dashboard/search_palette_component_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): ⌘K search button and palette (placeholder)

Visual slot + keyboard shortcut scaffold. Palette renders a coming-soon
empty state; a real search backend is a later project.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: `HelpMenuComponent` and `NotificationsButtonComponent`

**Files:**
- Create: `app/components/dashboard/help_menu_component.rb` + erb
- Create: `app/components/dashboard/notifications_button_component.rb` + erb
- Create: `app/javascript/controllers/dashboard_help_menu_controller.js`
- Test: `spec/components/dashboard/help_menu_component_spec.rb`
- Test: `spec/components/dashboard/notifications_button_component_spec.rb`

- [ ] **Step 13.1: Write failing tests**

```ruby
# spec/components/dashboard/help_menu_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::HelpMenuComponent, type: :component do
  it "renders a ? button that opens the help menu" do
    render_inline(described_class.new)
    expect(page).to have_css("button[aria-label='Help']")
    expect(page).to have_css("[data-controller='dashboard-help-menu']")
  end

  it "contains standard help links (docs, shortcuts, about)" do
    render_inline(described_class.new)
    expect(page).to have_link("Documentation")
    expect(page).to have_link("Keyboard shortcuts")
    expect(page).to have_link("About")
  end
end
```

```ruby
# spec/components/dashboard/notifications_button_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::NotificationsButtonComponent, type: :component do
  it "renders a bell button with no badge by default" do
    render_inline(described_class.new)
    expect(page).to have_css("button[aria-label='Notifications']")
    expect(page).not_to have_css("[data-badge-count]")
  end
end
```

- [ ] **Step 13.2: Run tests**

Run: `bundle exec rspec spec/components/dashboard/help_menu_component_spec.rb spec/components/dashboard/notifications_button_component_spec.rb -fd`
Expected: failures.

- [ ] **Step 13.3: Implement**

Create `app/components/dashboard/help_menu_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class HelpMenuComponent < ApplicationComponent
  end
end
```

Create `app/components/dashboard/help_menu_component.html.erb`:

```erb
<div class="relative" data-controller="dashboard-help-menu">
  <button type="button"
          aria-label="Help"
          aria-haspopup="menu"
          class="h-9 w-9 inline-flex items-center justify-center rounded-md text-gray-500 hover:text-gray-700 hover:bg-gray-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500"
          data-action="click->dashboard-help-menu#toggle">
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path stroke-linecap="round" stroke-linejoin="round"
            d="M8.228 9a4 4 0 117.544 1.446c-.37.87-1.17 1.475-2.022 1.8-.42.163-.75.5-.75.95V13m0 3h.01M12 21a9 9 0 100-18 9 9 0 000 18z"/>
    </svg>
  </button>
  <div class="hidden absolute right-0 mt-2 w-56 bg-white border border-gray-200 rounded-md shadow-lg py-1 z-40"
       data-dashboard-help-menu-target="panel"
       role="menu">
    <%= link_to "Documentation", "/docs", target: "_blank", rel: "noopener",
                class: "flex items-center gap-2 px-3 py-2 text-sm text-gray-700 hover:bg-gray-50", role: "menuitem" %>
    <%= link_to "Keyboard shortcuts", "/docs/keyboard-shortcuts", target: "_blank", rel: "noopener",
                class: "flex items-center gap-2 px-3 py-2 text-sm text-gray-700 hover:bg-gray-50", role: "menuitem" %>
    <div class="my-1 h-px bg-gray-100"></div>
    <%= link_to "About", "/about",
                class: "flex items-center gap-2 px-3 py-2 text-sm text-gray-700 hover:bg-gray-50", role: "menuitem" %>
  </div>
</div>
```

Create `app/javascript/controllers/dashboard_help_menu_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.boundOutside = (e) => { if (!this.element.contains(e.target)) this.close() }
    document.addEventListener("click", this.boundOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
  }

  toggle(event) {
    event.stopPropagation()
    this.panelTarget.classList.toggle("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }
}
```

Create `app/components/dashboard/notifications_button_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class NotificationsButtonComponent < ApplicationComponent
  end
end
```

Create `app/components/dashboard/notifications_button_component.html.erb`:

```erb
<button type="button"
        aria-label="Notifications"
        class="h-9 w-9 inline-flex items-center justify-center rounded-md text-gray-500 hover:text-gray-700 hover:bg-gray-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500">
  <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
    <path stroke-linecap="round" stroke-linejoin="round"
          d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
  </svg>
</button>
```

- [ ] **Step 13.4: Run tests**

Run: `bundle exec rspec spec/components/dashboard/help_menu_component_spec.rb spec/components/dashboard/notifications_button_component_spec.rb -fd`
Expected: 3 examples, 0 failures.

- [ ] **Step 13.5: Commit**

```bash
git add app/components/dashboard/help_menu_component.rb app/components/dashboard/help_menu_component.html.erb app/components/dashboard/notifications_button_component.rb app/components/dashboard/notifications_button_component.html.erb app/javascript/controllers/dashboard_help_menu_controller.js spec/components/dashboard/help_menu_component_spec.rb spec/components/dashboard/notifications_button_component_spec.rb
git commit -m "$(cat <<'EOF'
feat(dashboard): add HelpMenu and NotificationsButton topbar components

Notifications button is a visual slot with no badge in Phase 1; the feed
lands later. Help menu opens docs/shortcuts/about.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Refactor `DrawerComponent` (mobile accordion, zone pill)

**Files:**
- Modify: `app/components/dashboard/drawer_component.rb`
- Modify: `app/components/dashboard/drawer_component.html.erb`
- Modify: `app/javascript/controllers/dashboard_drawer_controller.js` (may already exist)
- Test: `spec/components/dashboard/drawer_component_spec.rb`

- [ ] **Step 14.1: Check for existing drawer controller**

Run: `ls app/javascript/controllers/ | grep drawer`
If a `dashboard_drawer_controller.js` already exists, open it and read its current shape. Prefer augmenting over rewriting if the open/close logic already works.

- [ ] **Step 14.2: Write the failing test**

Create or replace `spec/components/dashboard/drawer_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::DrawerComponent, type: :component do
  let(:customer) { build_stubbed(:customer, name: "Acme") }
  let(:tree)     { Dashboard::SidebarTree.new }
  let(:zones) do
    [
      Dashboard::ZoneDefinition.new(key: :workspace, label: "Workspace",
        path_proc: ->(c) { "/#{c.id}/" },
        sections: [
          { key: :home,  label: "Home",  path_prefix: "/" },
          { key: :pages, label: "Pages", path_prefix: "/pages" }
        ]),
      Dashboard::ZoneDefinition.new(key: :admin, label: "Admin",
        path_proc: ->(c) { "/#{c.id}/admin" })
    ]
  end

  it "renders zone pill with each accessible zone" do
    render_inline(described_class.new(
      customer: customer, tree: tree,
      zones: zones, current_zone: :workspace,
      current_section: :home, current_path: "/#{customer.id}/"
    ))
    expect(page).to have_link("Workspace")
    expect(page).to have_link("Admin")
  end

  it "lists sections of the current zone" do
    render_inline(described_class.new(
      customer: customer, tree: tree,
      zones: zones, current_zone: :workspace,
      current_section: :home, current_path: "/#{customer.id}/"
    ))
    expect(page).to have_link("Home")
    expect(page).to have_link("Pages")
  end

  it "applies the slide-in class when drawer controller is initialized" do
    render_inline(described_class.new(
      customer: customer, tree: tree,
      zones: zones, current_zone: :workspace,
      current_section: :home, current_path: "/#{customer.id}/"
    ))
    panel = page.find("[data-dashboard-drawer-target='panel']")
    expect(panel[:class]).to include("-translate-x-full")
    expect(panel[:class]).to include("transition-transform")
  end
end
```

- [ ] **Step 14.3: Rewrite the component**

Replace `app/components/dashboard/drawer_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class DrawerComponent < ApplicationComponent
    def initialize(customer:, tree:, zones:, current_zone:, current_section:, current_path:)
      @customer = customer
      @tree = tree
      @zones = zones || []
      @current_zone = current_zone
      @current_section = current_section
      @current_path = current_path
    end

    attr_reader :customer, :tree, :zones, :current_zone, :current_section, :current_path

    def current_zone_definition
      zones.find { |z| z.key == current_zone } || zones.first
    end

    def current_sections
      current_zone_definition&.sections || []
    end

    def section_path(section)
      "/#{customer.id}#{section[:path_prefix]}".sub(%r{/+\z}, "/")
    end

    def zone_pill_class(zone)
      base = "flex-1 inline-flex items-center justify-center h-8 text-[13px] font-medium rounded transition-colors"
      if zone.key == current_zone
        "#{base} bg-white text-gray-900 shadow-sm"
      else
        "#{base} text-gray-600 hover:text-gray-900"
      end
    end
  end
end
```

Replace `app/components/dashboard/drawer_component.html.erb`:

```erb
<div class="md:hidden" data-controller="dashboard-drawer">
  <div data-dashboard-drawer-target="backdrop"
       data-action="click->dashboard-drawer#close"
       class="hidden fixed inset-0 bg-gray-900/50 z-40 transition-opacity"></div>
  <aside data-dashboard-drawer-target="panel"
         class="fixed top-0 left-0 h-full w-72 bg-white border-r border-gray-200 z-50 overflow-y-auto shadow-xl -translate-x-full transition-transform duration-200 ease-out">
    <div class="flex items-center justify-between px-4 h-14 border-b border-gray-200">
      <span class="text-sm font-semibold text-gray-900 truncate"><%= customer.name %></span>
      <button type="button"
              data-action="click->dashboard-drawer#close"
              aria-label="Close menu"
              class="p-1.5 text-gray-700 rounded-md hover:bg-gray-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      </button>
    </div>

    <% if zones.size > 1 %>
      <div class="px-3 pt-3">
        <div class="flex p-1 bg-gray-100 rounded-md">
          <% zones.each do |zone| %>
            <%= link_to zone.label, zone.path_for(customer), class: zone_pill_class(zone) %>
          <% end %>
        </div>
      </div>
    <% end %>

    <% if current_sections.any? %>
      <nav class="px-2 pt-3 pb-2 space-y-0.5" aria-label="Sections">
        <% current_sections.each do |section| %>
          <% active = section[:key] == current_section %>
          <%= link_to section_path(section),
                      class: "flex items-center px-3 py-2 rounded-md text-sm #{active ? 'bg-indigo-50 text-indigo-700 font-medium' : 'text-gray-700 hover:bg-gray-50'}" do %>
            <%= section[:label] %>
          <% end %>
        <% end %>
      </nav>
    <% end %>

    <% current_sections.each do |section| %>
      <% nodes = tree.nodes_for(section[:key]) %>
      <% next if nodes.empty? %>
      <div class="px-4 pt-4 pb-1 text-[11px] uppercase tracking-wider font-semibold text-gray-500"><%= section[:label] %></div>
      <ul class="px-2 pb-2 space-y-0.5">
        <% nodes.each do |node| %>
          <%= render Dashboard::SidebarNodeComponent.new(node: node, current_path: current_path) %>
        <% end %>
      </ul>
    <% end %>
  </aside>
</div>
```

Update `app/javascript/controllers/dashboard_drawer_controller.js` — if it already exists, verify it supports the new slide animation. Replace its contents with:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop"]

  open() {
    this.backdropTarget.classList.remove("hidden")
    this.panelTarget.classList.remove("-translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
  }

  close() {
    this.backdropTarget.classList.add("hidden")
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("-translate-x-full")
  }
}
```

- [ ] **Step 14.4: Run tests**

Run: `bundle exec rspec spec/components/dashboard/drawer_component_spec.rb -fd`
Expected: 3 examples, 0 failures.

- [ ] **Step 14.5: Commit**

```bash
git add app/components/dashboard/drawer_component.rb app/components/dashboard/drawer_component.html.erb app/javascript/controllers/dashboard_drawer_controller.js spec/components/dashboard/drawer_component_spec.rb
git commit -m "$(cat <<'EOF'
refactor(dashboard): drawer becomes zone-pill + section list + tree

Mobile nav now mirrors the three-zone structure: zone pill at top, section
list, then per-section sidebar tree. Slide animation uses transition-transform.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Refactor `TopbarComponent`

**Files:**
- Modify: `app/components/dashboard/topbar_component.rb`
- Modify: `app/components/dashboard/topbar_component.html.erb`
- Test: `spec/components/dashboard/topbar_component_spec.rb`

- [ ] **Step 15.1: Write the failing test**

Create or replace `spec/components/dashboard/topbar_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::TopbarComponent, type: :component do
  let(:customer) { build_stubbed(:customer, name: "Acme") }
  let(:user)     { build_stubbed(:authentication_user, customer: customer) }

  it "renders the workspace switcher" do
    render_inline(described_class.new(customer: customer, user: user, switchable_customers: []))
    expect(page).to have_text("Acme")
  end

  it "renders the search button" do
    render_inline(described_class.new(customer: customer, user: user, switchable_customers: []))
    expect(page).to have_css("button[aria-label='Open search']")
  end

  it "renders the help menu and notifications button" do
    render_inline(described_class.new(customer: customer, user: user, switchable_customers: []))
    expect(page).to have_css("button[aria-label='Help']")
    expect(page).to have_css("button[aria-label='Notifications']")
  end

  it "renders the user menu when a user is present" do
    render_inline(described_class.new(customer: customer, user: user, switchable_customers: []))
    expect(page).to have_css("[data-controller='dashboard-user-menu']")
  end

  it "omits the user menu when user is nil" do
    render_inline(described_class.new(customer: customer, user: nil, switchable_customers: []))
    expect(page).not_to have_css("[data-controller='dashboard-user-menu']")
  end

  it "renders the mobile hamburger button" do
    render_inline(described_class.new(customer: customer, user: user, switchable_customers: []))
    expect(page).to have_css("button[aria-label='Open menu']")
  end
end
```

- [ ] **Step 15.2: Run tests**

Run: `bundle exec rspec spec/components/dashboard/topbar_component_spec.rb -fd`
Expected: failures.

- [ ] **Step 15.3: Rewrite the component**

Replace `app/components/dashboard/topbar_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class TopbarComponent < ApplicationComponent
    def initialize(customer:, user:, switchable_customers: [])
      @customer = customer
      @user = user
      @switchable_customers = Array(switchable_customers)
    end

    attr_reader :customer, :user, :switchable_customers
  end
end
```

Replace `app/components/dashboard/topbar_component.html.erb`:

```erb
<header class="bg-white border-b border-gray-200">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-14 flex items-center gap-3">
    <button type="button"
            class="md:hidden p-1.5 text-gray-700 rounded-md hover:bg-gray-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500"
            data-action="click->dashboard-drawer#open"
            aria-label="Open menu">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16"/>
      </svg>
    </button>

    <%= render Dashboard::WorkspaceSwitcherComponent.new(customer: customer, switchable_customers: switchable_customers) %>

    <div class="hidden md:flex flex-1 items-center justify-center px-8">
      <%= render Dashboard::SearchButtonComponent.new %>
    </div>

    <div class="flex items-center gap-1 ml-auto">
      <div class="md:hidden">
        <%= render Dashboard::SearchButtonComponent.new %>
      </div>
      <%= render Dashboard::HelpMenuComponent.new %>
      <%= render Dashboard::NotificationsButtonComponent.new %>
      <%= render Dashboard::UserMenuComponent.new(user: user, customer: customer) if user %>
    </div>
  </div>
</header>
```

- [ ] **Step 15.4: Run tests**

Run: `bundle exec rspec spec/components/dashboard/topbar_component_spec.rb -fd`
Expected: 6 examples, 0 failures.

- [ ] **Step 15.5: Commit**

```bash
git add app/components/dashboard/topbar_component.rb app/components/dashboard/topbar_component.html.erb spec/components/dashboard/topbar_component_spec.rb
git commit -m "$(cat <<'EOF'
refactor(dashboard): Topbar gains workspace switcher, search, help, bell

Topbar now composes WorkspaceSwitcher, SearchButton, HelpMenu,
NotificationsButton, and UserMenu. Mobile search collapses to icon-only.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Refactor `ShellComponent` (zone row, sections, width helper, palette)

**Files:**
- Modify: `app/components/dashboard/shell_component.rb`
- Modify: `app/components/dashboard/shell_component.html.erb`
- Test: `spec/components/dashboard/shell_component_spec.rb`

- [ ] **Step 16.1: Write the failing test**

Replace `spec/components/dashboard/shell_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::ShellComponent, type: :component do
  let(:customer) { build_stubbed(:customer, name: "Acme") }
  let(:user)     { build_stubbed(:authentication_user, customer: customer) }
  let(:tree)     { Dashboard::SidebarTree.new }
  let(:zones) do
    [
      Dashboard::ZoneRegistry.zone(:workspace),
      Dashboard::ZoneRegistry.zone(:admin)
    ]
  end

  def render_shell(current_section: :home, current_zone: :workspace, zones_override: zones)
    render_inline(described_class.new(
      customer: customer, user: user, tree: tree,
      zones: zones_override, current_zone: current_zone,
      current_section: current_section,
      current_path: "/#{customer.id}/"
    )) { "PAGE BODY" }
  end

  it "renders the topbar, zone tabs, section tabs, sidebar, and body" do
    render_shell
    expect(page).to have_text("Acme")
    expect(page).to have_text("PAGE BODY")
    expect(page).to have_link("Workspace")
    expect(page).to have_link("Home")
  end

  it "omits the sidebar when current_section is :home" do
    render_shell(current_section: :home)
    expect(page).not_to have_css("aside.hidden.md\\:block")
  end

  it "omits the section tabs and sidebar when the zone has no sections" do
    render_shell(current_zone: :admin)
    expect(page).not_to have_link("Home")
  end

  it "includes the search palette" do
    render_shell
    expect(page).to have_css("[data-dashboard-search-target='panel']", visible: :all)
  end

  it "wraps the body in a container with the default wide width" do
    render_shell
    expect(page).to have_css("div.max-w-7xl", text: "PAGE BODY")
  end
end
```

- [ ] **Step 16.2: Run tests**

Run: `bundle exec rspec spec/components/dashboard/shell_component_spec.rb -fd`
Expected: failures.

- [ ] **Step 16.3: Rewrite the component**

Replace `app/components/dashboard/shell_component.rb`:

```ruby
# frozen_string_literal: true

module Dashboard
  class ShellComponent < ApplicationComponent
    def initialize(customer:, user:, tree:, zones:, current_zone:, current_section:, current_path:, switchable_customers: [], container_width: :wide)
      @customer = customer
      @user = user
      @tree = tree
      @zones = zones || []
      @current_zone = current_zone
      @current_section = current_section
      @current_path = current_path
      @switchable_customers = Array(switchable_customers)
      @container_width = container_width
    end

    attr_reader :customer, :user, :tree, :zones, :current_zone,
                :current_section, :current_path, :switchable_customers,
                :container_width

    def current_zone_definition
      zones.find { |z| z.key == current_zone }
    end

    def current_sections
      current_zone_definition&.sections || []
    end

    def show_sidebar?
      current_section != :home && current_sections.any?
    end

    def container_classes
      helpers.container_width_class(container_width)
    end
  end
end
```

Replace `app/components/dashboard/shell_component.html.erb`:

```erb
<div class="min-h-screen flex flex-col bg-gray-50">
  <%= render Dashboard::TopbarComponent.new(
        customer: customer,
        user: user,
        switchable_customers: switchable_customers
      ) %>

  <%= render Dashboard::ZoneTabsComponent.new(
        customer: customer,
        zones: zones,
        current_zone: current_zone
      ) %>

  <%= render Dashboard::SectionTabsComponent.new(
        customer: customer,
        sections: current_sections,
        current_section: current_section
      ) %>

  <div class="flex flex-1 overflow-hidden">
    <% if show_sidebar? %>
      <%= render Dashboard::SidebarComponent.new(
            tree: tree,
            section: current_section,
            current_path: current_path
          ) %>
    <% end %>

    <%= render Dashboard::DrawerComponent.new(
          customer: customer,
          tree: tree,
          zones: zones,
          current_zone: current_zone,
          current_section: current_section,
          current_path: current_path
        ) %>

    <main class="flex-1 overflow-auto">
      <div class="<%= container_classes %> py-8">
        <%= content %>
      </div>
    </main>
  </div>

  <%= render Dashboard::SearchPaletteComponent.new %>
</div>
```

Note: the `container_width` prop accepts `:narrow|:wide|:full` and falls back to `:wide` via the helper. The layout (Task 17) reads `content_for(:container_width)` and passes it in.

- [ ] **Step 16.4: Run tests**

Run: `bundle exec rspec spec/components/dashboard/shell_component_spec.rb -fd`
Expected: 5 examples, 0 failures.

- [ ] **Step 16.5: Commit**

```bash
git add app/components/dashboard/shell_component.rb app/components/dashboard/shell_component.html.erb spec/components/dashboard/shell_component_spec.rb
git commit -m "$(cat <<'EOF'
refactor(dashboard): ShellComponent — zone row, section tabs, width, palette

Shell now composes ZoneTabs + SectionTabs + Sidebar (conditional) +
Drawer + SearchPalette. Accepts container_width (:narrow|:wide|:full),
hides sidebar on :home section, and on zones with no sections.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: Wire the layout to the new shell contract

**Files:**
- Modify: `app/views/layouts/dashboard.html.erb`
- Test: `spec/system/dashboard/shell_navigation_spec.rb` (created in Task 19)

- [ ] **Step 17.1: Edit the layout**

Replace `app/views/layouts/dashboard.html.erb`:

```erb
<%# app/views/layouts/dashboard.html.erb %>
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Dashboard" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= yield :head %>
    <link rel="icon" href="/icon.png" type="image/png">
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-gray-50">
    <%
      zones = Dashboard::ZoneRegistry.for(current_user)
      dashboard_context = Dashboard::DashboardContext.new(
        current_user:     current_user,
        current_customer: current_customer,
        current_section:  current_dashboard_section,
        request_path:     request.path
      )
      dashboard_tree = Dashboard::SidebarBuilder.build(dashboard_context)
      width = content_for?(:container_width) ? content_for(:container_width).to_s.strip.to_sym : :wide
    %>
    <%= render Dashboard::ShellComponent.new(
      customer: current_customer,
      user: current_user,
      tree: dashboard_tree,
      zones: zones,
      current_zone: current_dashboard_zone,
      current_section: current_dashboard_section,
      current_path: request.path,
      switchable_customers: [],
      container_width: width
    ) do %>
      <% if flash.any? %>
        <% flash.each do |type, message| %>
          <div class="mb-4 <%= type == 'alert' ? 'bg-red-50 border-red-400 text-red-800' : 'bg-green-50 border-green-400 text-green-800' %> border-l-4 p-3 text-sm" role="alert">
            <%= message %>
          </div>
        <% end %>
      <% end %>
      <%= yield %>
    <% end %>
  </body>
</html>
```

Notes:
- `switchable_customers: []` is always empty in Phase 1. The workspace switcher already degrades to a static label in that case. Phase 3 / tenant-switching work populates it.
- `content_for(:container_width)` is read if present; default is `:wide`.

- [ ] **Step 17.2: Run the existing non-regression dashboard specs**

Run: `bundle exec rspec spec/components/dashboard spec/requests/dashboard spec/system/dashboard -fd --fail-fast`
Expected: 0 failures.

- [ ] **Step 17.3: Boot the server and smoke-test**

Run: `bundle exec rails runner "puts 'boot ok'"`
Expected: prints "boot ok" with no eager-load errors.

- [ ] **Step 17.4: Commit**

```bash
git add app/views/layouts/dashboard.html.erb
git commit -m "$(cat <<'EOF'
feat(dashboard): wire layout to new three-zone shell

Layout now passes zones (from ZoneRegistry.for(user)), current_zone,
container_width (from content_for) into ShellComponent.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Update the base `SidebarComponent` (narrower on laptop)

**Files:**
- Modify: `app/components/dashboard/sidebar_component.html.erb`
- Test: covered by existing `sidebar_component_spec.rb` (no behavior change)

- [ ] **Step 18.1: Read the existing component**

Run: `cat app/components/dashboard/sidebar_component.rb app/components/dashboard/sidebar_component.html.erb`

- [ ] **Step 18.2: Adjust the Tailwind width classes**

In `app/components/dashboard/sidebar_component.html.erb`, find the `<aside ...>` element's class list. Change any occurrence of `w-64` or similar fixed width to:

```
w-56 xl:w-64
```

So the sidebar renders at 224px on laptop (`md`-`xl`) and 256px at `xl` and up. If the existing class list uses different tokens, preserve them and only swap the width tokens.

- [ ] **Step 18.3: Run existing specs**

Run: `bundle exec rspec spec/components/dashboard/sidebar_component_spec.rb -fd`
Expected: 0 failures.

- [ ] **Step 18.4: Commit**

```bash
git add app/components/dashboard/sidebar_component.html.erb
git commit -m "$(cat <<'EOF'
style(dashboard): narrower sidebar on laptop breakpoint

w-56 up to xl; w-64 at xl+. Same as the two-tier responsive plan in
the Phase 1 design.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 19: System specs — navigation, responsive, search palette

**Files:**
- Create: `spec/system/dashboard/shell_navigation_spec.rb`
- Create: `spec/system/dashboard/responsive_drawer_spec.rb`
- Create: `spec/system/dashboard/search_palette_spec.rb`

- [ ] **Step 19.1: Shell navigation spec**

Create `spec/system/dashboard/shell_navigation_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard shell navigation", type: :system do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:authentication_user, customer: customer, role: :admin) }

  before do
    driven_by(:rack_test)
    sign_in admin
  end

  it "shows workspace and admin zones in the zone tabs" do
    visit "/#{customer.id}/"
    expect(page).to have_link("Workspace")
    expect(page).to have_link("Admin")
  end

  it "does not show the platform zone for non-platform users" do
    visit "/#{customer.id}/"
    expect(page).not_to have_link("Platform")
  end

  it "navigates to the Admin zone root" do
    visit "/#{customer.id}/"
    click_link "Admin"
    expect(page).to have_current_path("/#{customer.id}/admin")
    expect(page).to have_text("Coming soon")
  end

  it "shows section tabs for the Workspace zone" do
    visit "/#{customer.id}/"
    expect(page).to have_link("Home")
    expect(page).to have_link("Pages")
  end

  it "omits section tabs for the Admin zone (no sections in Phase 1)" do
    visit "/#{customer.id}/admin"
    expect(page).not_to have_link("Home")
  end
end
```

- [ ] **Step 19.2: Responsive drawer spec**

Create `spec/system/dashboard/responsive_drawer_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard responsive drawer", type: :system, js: true do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:authentication_user, customer: customer, role: :admin) }

  before do
    driven_by(:selenium_chrome_headless, screen_size: [375, 812])
    sign_in admin
  end

  it "opens the drawer from the hamburger button on mobile" do
    visit "/#{customer.id}/"
    expect(page).to have_css("aside[data-dashboard-drawer-target='panel'].-translate-x-full", visible: :all)
    find("button[aria-label='Open menu']").click
    expect(page).to have_css("aside[data-dashboard-drawer-target='panel'].translate-x-0")
    expect(page).to have_link("Workspace")
    expect(page).to have_link("Admin")
  end

  it "closes the drawer when the backdrop is clicked" do
    visit "/#{customer.id}/"
    find("button[aria-label='Open menu']").click
    find("[data-dashboard-drawer-target='backdrop']").click
    expect(page).to have_css("aside[data-dashboard-drawer-target='panel'].-translate-x-full")
  end
end
```

If the project does not already configure Selenium / headless Chrome, replace `driven_by(:selenium_chrome_headless, screen_size: [375, 812])` with whatever existing JS driver the repo uses (check `spec/support/` and `spec/rails_helper.rb`). If no JS driver is configured, skip this spec and file a follow-up — don't add a new driver setup as part of this task.

- [ ] **Step 19.3: Search palette spec**

Create `spec/system/dashboard/search_palette_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard search palette", type: :system, js: true do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:authentication_user, customer: customer, role: :admin) }

  before do
    driven_by(:selenium_chrome_headless)
    sign_in admin
  end

  it "opens the palette on click" do
    visit "/#{customer.id}/"
    expect(page).to have_css("[data-dashboard-search-target='panel'].hidden", visible: :all)
    find("button[aria-label='Open search']", match: :first).click
    expect(page).to have_no_css("[data-dashboard-search-target='panel'].hidden")
    expect(page).to have_text("Search is coming soon")
  end

  it "closes the palette on Escape" do
    visit "/#{customer.id}/"
    find("button[aria-label='Open search']", match: :first).click
    expect(page).to have_no_css("[data-dashboard-search-target='panel'].hidden")
    page.driver.browser.action.send_keys(:escape).perform
    expect(page).to have_css("[data-dashboard-search-target='panel'].hidden", visible: :all)
  end
end
```

Same fallback: if no JS driver is configured, skip and file a follow-up.

- [ ] **Step 19.4: Run the system specs**

Run: `bundle exec rspec spec/system/dashboard -fd`
Expected: 0 failures (JS-driven specs may be skipped if no driver is configured).

- [ ] **Step 19.5: Commit**

```bash
git add spec/system/dashboard/shell_navigation_spec.rb spec/system/dashboard/responsive_drawer_spec.rb spec/system/dashboard/search_palette_spec.rb
git commit -m "$(cat <<'EOF'
test(dashboard): system specs for zone nav, drawer, search palette

End-to-end coverage for Phase 1 shell: zone tabs visibility by role,
drawer open/close on mobile, ⌘K palette open/close.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 20: Full regression pass + precompile + smoke

**Files:** none — verification only.

- [ ] **Step 20.1: Run the full RSpec suite**

Run: `bundle exec rspec -fd --fail-fast`
Expected: 0 failures.

If a non-dashboard spec fails because it expected the default dashboard section to be `:entity_entries`, update that spec's expectation to `:home`. No other default-value changes are expected.

- [ ] **Step 20.2: Precompile assets**

Run: `bundle exec rails assets:precompile`
Expected: clean completion; no Tailwind warnings about undefined classes. Remove `public/assets/.manifest.json` afterward:

```bash
rm -f public/assets/.manifest.json
```

- [ ] **Step 20.3: Boot the server, smoke-test three role tiers**

Start the server: `bundle exec rails server -b 0.0.0.0 -p 3000` (or reuse an existing instance).
Smoke paths:
- As a member: visit `/<customer_id>/` — expect Workspace zone tabs only; visit `/<customer_id>/admin` — expect redirect to root with flash alert.
- As an admin: visit `/<customer_id>/` — expect Workspace + Admin tabs; visit `/<customer_id>/admin` — expect "Coming soon" page.
- With `PLATFORM_OWNER_EMAILS=owner@example.com` and signed in as that user — visit `/<customer_id>/platform` — expect "Coming soon" page; zone tab row shows all three.

Document any visual issue found and fix before commit.

- [ ] **Step 20.4: Commit the regression pass (if any spec updates were needed)**

If Step 20.1 required spec updates:

```bash
git add spec/
git commit -m "$(cat <<'EOF'
test: adjust default-section expectations to :home (dashboard refactor)

Phase 1 changes the default dashboard section from :entity_entries to
:home to match the new zone-landing model.

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

If no spec updates were needed, skip this step.

---

## Self-Review

**Spec coverage:**
- §1 Goals → covered by Tasks 1–19 overall.
- §2 Zone model → Tasks 2, 3, 4 (registry + zone_definition + controller helpers).
- §2.1 Platform-owner predicate → Task 1.
- §2.2 Zone root paths → Task 6 (routes + controllers + empty-state views).
- §3.1–3.3 Layout regions and responsive → Tasks 14, 15, 16, 18 (drawer, topbar, shell, sidebar widths).
- §3.4 Per-page max-width → Task 7 (helper) + Task 16 (shell wiring) + Task 17 (layout reading content_for).
- §3.5 Spacing/typography → baked into component classes across Tasks 9, 10, 11, 13, 14, 15, 16.
- §4 Components → each component has its own task.
- §5 Data flow → Task 17 wires the pipeline end-to-end.
- §6 Stimulus controllers → Tasks 10, 11, 12, 13, 14.
- §7 Routes → Task 6.
- §8 Controllers → Task 6.
- §9 Error handling → Task 4 adds `require_platform_owner!` and `require_admin_or_owner!`; Task 6 specs assert redirect+flash.
- §10 Testing strategy → each task has component/request specs; Task 19 adds system specs; Task 20 runs the full suite.
- §11 Migration & rollout → Task 17 is the single cut-over; no data migration in this plan.

**Placeholder scan:** No TBDs. Every step has either concrete code, a concrete command, or an explicit fallback.

**Type consistency:**
- `ZoneDefinition(key:, label:, sections:, path_proc:, permitted_by:)` used consistently in Tasks 2, 3, 10, 14, 16.
- `section` hash shape `{ key:, label:, path_prefix: }` used in Tasks 3, 9, 14, 16.
- `SectionTabsComponent.new(customer:, sections:, current_section:)` signature used in Task 9 and Task 16.
- `ShellComponent.new(customer:, user:, tree:, zones:, current_zone:, current_section:, current_path:, switchable_customers:, container_width:)` used in Task 16 and Task 17.

**Risk notes for executor:**
- `spec/controllers/application_controller_zone_helpers_spec.rb` uses `ActionDispatch::TestRequest` directly because a full `type: :request` harness for the ApplicationController class isn't appropriate. If the spec suite has a custom `TestRequest` setup, follow the repo's established pattern instead.
- Task 19's JS specs depend on an existing Selenium setup. If none exists, skip them and file a follow-up — don't block Phase 1 on driver configuration.

---

Plan complete and saved to `docs/superpowers/plans/2026-04-28-dashboard-foundation-refactor.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
