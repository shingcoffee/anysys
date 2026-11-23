# Platform Module Settings Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Platform Module Settings (`/81721200/admin/maintenance/platform/module_settings`) to fix toggle alignment, remove the Routes tab section, discover all module models, and allow model attributes to be toggled as template tokens in `email_template_tokens`.

**Architecture:** Update `ModuleModelDiscovery` for full model discovery across all 5 feature modules (`authentication`, `email`, `payment`, `sms`, `captcha`). Adjust `ModuleToggleComponent` and flex layout in `show.html.erb` to keep toggles right-aligned without wrapping. Update `ModuleSettingsController` to handle `token_model`/`token_attribute`/`token_enabled` params to persist platform rows in `email_template_tokens`. Add the "Model Attributes & Template Tokens" card section to the Technical Reference tab while removing the Routes card.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, ViewComponent, RSpec.

## Global Constraints

- CSS: Only use TailwindCSS utilities (no custom CSS).
- JavaScript: StimulusJS only if needed.
- I18n: All user-facing labels must be localized in both English (`config/locales/maint_platform.en.yml`) and Simplified Chinese (`config/locales/maint_platform.zh-CN.yml`).
- Verification: Run targeted RSpec specs after each task and confirm 0 failures.

---

### Task 1: Comprehensive Model Discovery (`ModuleModelDiscovery`)

**Files:**
- Modify: `app/services/module_model_discovery.rb`
- Test: `spec/services/module_model_discovery_spec.rb`

**Interfaces:**
- Consumes: Module key string (e.g. `"authentication"`, `"email"`, `"payment"`, `"sms"`, `"captcha"`).
- Produces: Array of hashes `[{ name:, table_name:, columns_count:, columns:, associations_count:, associations: }]`.

- [ ] **Step 1: Write the failing test for all 5 feature modules**

In `spec/services/module_model_discovery_spec.rb`, add specs for `"authentication"`, `"email"`, `"payment"`, `"sms"`, and `"captcha"`:

```ruby
# spec/services/module_model_discovery_spec.rb
require "rails_helper"

RSpec.describe ModuleModelDiscovery do
  describe ".call" do
    context "with authentication module" do
      let(:results) { described_class.call("authentication") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers all authentication models including Roles" do
        expect(names).to include("Authentication::User", "Authentication::Event", "Authentication::TrustedDevice", "Role", "RolePermission", "UsersRole")
      end
    end

    context "with email module" do
      let(:results) { described_class.call("email") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers email models from Emails namespace" do
        expect(names).to include("Emails::Credential", "Emails::Message", "Emails::Template", "Emails::TemplateToken")
      end
    end

    context "with payment module" do
      let(:results) { described_class.call("payment") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers payment models from Payments namespace" do
        expect(names).to include("Payments::Payment", "Payments::MerchantAccount", "Payments::Order")
      end
    end

    context "with sms module" do
      let(:results) { described_class.call("sms") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers sms models" do
        expect(names).to include("Sms::Credential", "Sms::Message", "Sms::Template")
      end
    end

    context "with captcha module" do
      let(:results) { described_class.call("captcha") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers captcha models" do
        expect(names).to include("Captcha::ProviderSettings", "Captcha::Verification")
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

- [ ] **Step 2: Run test to verify failure**

Run: `bundle exec rspec spec/services/module_model_discovery_spec.rb`  
Expected: FAIL (email and payment return empty arrays, authentication misses Role/RolePermission/UsersRole).

- [ ] **Step 3: Update `ModuleModelDiscovery` implementation**

In `app/services/module_model_discovery.rb`:

```ruby
# frozen_string_literal: true

class ModuleModelDiscovery
  MODULE_DIRECTORY_MAPPINGS = {
    "authentication" => ["app/models/authentication"],
    "email"          => ["app/models/emails"],
    "payment"        => ["app/models/payments"],
    "sms"            => ["app/models/sms"],
    "captcha"        => ["app/models/captcha"]
  }.freeze

  EXTRA_MODULE_CLASSES = {
    "authentication" => ["Role", "RolePermission", "UsersRole"]
  }.freeze

  def self.call(module_key)
    new(module_key).call
  end

  def initialize(module_key)
    @module_key = module_key.to_s
  end

  def call
    models = discover_directory_models + discover_extra_models
    models.compact.uniq { |m| m[:name] }.sort_by { |m| m[:name] }
  end

  private

  def discover_directory_models
    dirs = MODULE_DIRECTORY_MAPPINGS[@module_key] || ["app/models/#{@module_key}"]
    dirs.flat_map do |rel_dir|
      model_dir = Rails.root.join(rel_dir)
      next [] unless model_dir.directory?

      Dir.glob(model_dir.join("**", "*.rb")).filter_map do |file_path|
        class_name = derive_class_name(file_path)
        klass = class_name.safe_constantize
        next unless klass && klass < ApplicationRecord

        build_model_hash(klass)
      rescue StandardError
        nil
      end
    end
  end

  def discover_extra_models
    class_names = EXTRA_MODULE_CLASSES[@module_key] || []
    class_names.filter_map do |cname|
      klass = cname.safe_constantize
      next unless klass && klass < ApplicationRecord

      build_model_hash(klass)
    rescue StandardError
      nil
    end
  end

  def derive_class_name(file_path)
    relative = Pathname.new(file_path).relative_path_from(Rails.root.join("app", "models"))
    relative.to_s.delete_suffix(".rb").camelize
  end

  def build_model_hash(klass)
    {
      name: klass.name,
      table_name: klass.table_name,
      columns_count: klass.columns.size,
      columns: extract_columns(klass),
      associations_count: klass.reflect_on_all_associations.size,
      associations: extract_associations(klass)
    }
  end

  def extract_columns(klass)
    klass.columns.map do |col|
      {
        name: col.name,
        type: col.type.to_s,
        nullable: col.null,
        default: col.default
      }
    end
  end

  def extract_associations(klass)
    klass.reflect_on_all_associations.map do |assoc|
      {
        name: assoc.name.to_s,
        macro: assoc.macro.to_s,
        target_class: assoc.class_name
      }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/module_model_discovery_spec.rb`  
Expected: PASS with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/module_model_discovery.rb spec/services/module_model_discovery_spec.rb
git commit -m "feat(platform): expand ModuleModelDiscovery for all feature modules"
```

---

### Task 2: Right-Aligned Toggle Layout (`ModuleToggleComponent`)

**Files:**
- Modify: `app/components/admin/maintenance/platform/module_toggle_component.html.erb`
- Modify: `app/components/admin/maintenance/platform/module_toggle_component.rb`
- Test: `spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`

**Interfaces:**
- Consumes: `ModuleToggleComponent` props (`url`, `field`, `on`, `disabled`, etc.).
- Produces: HTML container with `whitespace-nowrap flex-shrink-0 ml-auto flex items-center justify-end gap-3`.

- [ ] **Step 1: Write/update component spec for toggle layout styling**

Check `spec/components/admin/maintenance/platform/module_toggle_component_spec.rb` or create it if missing:

```ruby
# spec/components/admin/maintenance/platform/module_toggle_component_spec.rb
require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleToggleComponent, type: :component do
  it "renders right-aligned flex container with no wrapping classes" do
    rendered = render_inline(described_class.new(
      url: "/81721200/admin/maintenance/platform/module_settings/1",
      field: "status_active",
      on: true
    ))

    expect(rendered.css("div.whitespace-nowrap.flex-shrink-0")).to be_present
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`  
Expected: FAIL (missing `whitespace-nowrap flex-shrink-0`).

- [ ] **Step 3: Update `ModuleToggleComponent` ERB wrapper**

In `app/components/admin/maintenance/platform/module_toggle_component.html.erb`:

```erb
<%# app/components/admin/maintenance/platform/module_toggle_component.html.erb %>
<div class="flex items-center justify-end gap-3 whitespace-nowrap flex-shrink-0 ml-auto">
  <% if disabled? %>
    <button type="button" disabled class="<%= track_classes %>" role="switch" aria-checked="<%= on? %>">
      <span class="<%= knob_classes %>"></span>
    </button>
  <% else %>
    <%= form_with url: url, method: :patch, local: true, class: "inline" do %>
      <input type="hidden" name="<%= field %>" value="<%= next_value %>">
      <% extra_params.each do |key, value| %>
        <input type="hidden" name="<%= key %>" value="<%= value %>">
      <% end %>
      <button type="submit"
              <% if confirm.present? %>data-turbo-confirm="<%= confirm %>"<% end %>
              class="<%= track_classes %>" role="switch" aria-checked="<%= on? %>">
        <span class="<%= knob_classes %>"></span>
      </button>
    <% end %>
  <% end %>
  <span class="text-body-sm text-text-primary"><%= label %></span>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/admin/maintenance/platform/module_toggle_component.html.erb spec/components/admin/maintenance/platform/module_toggle_component_spec.rb
git commit -m "fix(platform): align module toggles right-most without line wrapping"
```

---

### Task 3: Controller Backend for Template Token Persistence

**Files:**
- Modify: `app/controllers/admin/maintenance/platform/module_settings_controller.rb`
- Test: `spec/requests/admin/maintenance/platform/module_settings_spec.rb`

**Interfaces:**
- Consumes: PATCH params `token_model`, `token_attribute`, `token_enabled` ("1" or "0").
- Produces: Creates or destroys platform row in `Emails::TemplateToken` (`customer_id: nil`, `source_type: 'platform_field'`).

- [ ] **Step 1: Write failing request spec for token attribute toggle**

In `spec/requests/admin/maintenance/platform/module_settings_spec.rb`, add:

```ruby
describe "PATCH /:cid/admin/maintenance/platform/module_settings/:id (token attribute toggle)" do
  let(:owner_user) { create(:user, :owner, customer: customer) }
  let(:customer)   { Customer.find_by(id: 81721200) || create(:customer, id: 81721200) }
  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  before { sign_in_as(owner_user) }

  it "creates platform template token when enabled" do
    source_key = "authentication_user.email"
    Emails::TemplateToken.where(source_key: source_key).destroy_all

    patch admin_maintenance_platform_module_setting_path(customer.id, auth_module), params: {
      token_model: "Authentication::User",
      token_attribute: "email",
      token_enabled: "1"
    }

    expect(response).to redirect_to(admin_maintenance_platform_module_setting_path(customer.id, auth_module))
    token = Emails::TemplateToken.platform.find_by(source_key: source_key)
    expect(token).to be_present
    expect(token.label).to eq("User.email")
  end

  it "destroys platform template token when disabled" do
    source_key = "authentication_user.email"
    Emails::TemplateToken.find_or_create_by!(
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: source_key
    ) { |t| t.label = "User.email" }

    patch admin_maintenance_platform_module_setting_path(customer.id, auth_module), params: {
      token_model: "Authentication::User",
      token_attribute: "email",
      token_enabled: "0"
    }

    expect(response).to redirect_to(admin_maintenance_platform_module_setting_path(customer.id, auth_module))
    expect(Emails::TemplateToken.platform.find_by(source_key: source_key)).to be_nil
  end
end
```

- [ ] **Step 2: Run request spec to verify failure**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`  
Expected: FAIL (controller does not handle `params[:token_model]`).

- [ ] **Step 3: Update `ModuleSettingsController#update`**

In `app/controllers/admin/maintenance/platform/module_settings_controller.rb`:

Add `apply_token_attribute!` in `update`:

```ruby
def update
  @feature_module = FeatureModules::Module.find(params[:id])

  apply_status!          if params.key?(:status_active)
  apply_required!        if params.key?(:required)
  apply_handoff_enabled! if params.key?(:handoff_enabled)
  apply_extendable_model! if params.key?(:extendable_model)
  apply_config_defaults!  if params.key?(:config_defaults)
  apply_token_attribute! if params.key?(:token_model) && params.key?(:token_attribute)

  redirect_to show_path, notice: t("maint_platform.flash.module_settings.updated", name: @feature_module.name)
rescue StandardError => e
  redirect_to show_path, alert: t("maint_platform.flash.module_settings.update_failed", error: e.message)
end

private

def apply_token_attribute!
  model_name = params[:token_model].to_s
  attr_name  = params[:token_attribute].to_s
  enabled    = params[:token_enabled] == "1"

  source_key = "#{model_name.underscore.tr('/', '_')}.#{attr_name}"
  label      = "#{model_name.demodulize}.#{attr_name}"

  if enabled
    Emails::TemplateToken.find_or_create_by!(
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: source_key
    ) do |token|
      token.customer_id = nil
      token.label       = label
    end
  else
    Emails::TemplateToken.platform.where(source_key: source_key).destroy_all
  end
end
```

- [ ] **Step 4: Run request spec to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/platform/module_settings_controller.rb spec/requests/admin/maintenance/platform/module_settings_spec.rb
git commit -m "feat(platform): handle model attribute template token toggles in module settings"
```

---

### Task 4: UI View Update & Localization (Remove Routes + Add Model Attributes & Tokens Section)

**Files:**
- Modify: `app/views/admin/maintenance/platform/module_settings/show.html.erb`
- Modify: `config/locales/maint_platform.en.yml`
- Modify: `config/locales/maint_platform.zh-CN.yml`
- Test: `spec/requests/admin/maintenance/platform/module_settings_spec.rb`

**Interfaces:**
- Consumes: `@module_models` array from controller.
- Produces: Updated Technical Reference tab in `show.html.erb` with Routes card removed and Model Attributes & Template Tokens card added.

- [ ] **Step 1: Add I18n strings to locale files**

In `config/locales/maint_platform.en.yml` under `maint_platform.module_settings.show`:
```yaml
tokens:
  title: "Model Attributes & Template Tokens"
  subtitle: "Configure which model attributes are exposed as reference tokens for email and SMS templates"
  available: "Token Available"
  not_available: "Not Tokenized"
  attribute: "Attribute"
  type: "Data Type"
  token_status: "Template Token"
```

In `config/locales/maint_platform.zh-CN.yml` under `maint_platform.module_settings.show`:
```yaml
tokens:
  title: "模型属性与模板 Token"
  subtitle: "配置哪些模型属性可作为邮件和短信模板中的引用 Token"
  available: "可用作 Token"
  not_available: "不可用"
  attribute: "属性"
  type: "数据类型"
  token_status: "模板 Token"
```

- [ ] **Step 2: Update `show.html.erb` under Technical Reference tab**

In `app/views/admin/maintenance/platform/module_settings/show.html.erb`:

1. Remove the `<%# Routes Card %>` card block (lines ~381-429).
2. Add the `<%# Model Attributes & Template Tokens Card %>` block immediately after the Models Card:

```erb
      <%# Model Attributes & Template Tokens Card %>
      <div class="card overflow-hidden">
        <div class="card-header">
          <h2 class="section-header"><%= t("maint_platform.module_settings.show.tokens.title") %></h2>
          <p class="mt-0.5 text-caption"><%= t("maint_platform.module_settings.show.tokens.subtitle") %></p>
        </div>
        <% if @module_models.any? %>
          <div class="divide-y divide-border-subtle">
            <% platform_token_keys = Emails::TemplateToken.platform.pluck(:source_key).to_set %>
            <% @module_models.each do |model| %>
              <div class="p-6">
                <div class="mb-3 flex items-center justify-between">
                  <h3 class="text-body font-medium text-text-primary"><%= model[:name] %></h3>
                  <span class="text-mono text-xs bg-surface-active px-1.5 py-0.5 rounded text-text-muted"><%= model[:table_name] %></span>
                </div>
                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-border-subtle">
                    <thead class="table-header">
                      <tr>
                        <th class="px-4 py-2 text-left text-label"><%= t("maint_platform.module_settings.show.tokens.attribute") %></th>
                        <th class="px-4 py-2 text-left text-label"><%= t("maint_platform.module_settings.show.tokens.type") %></th>
                        <th class="px-4 py-2 text-center text-label w-48"><%= t("maint_platform.module_settings.show.tokens.token_status") %></th>
                      </tr>
                    </thead>
                    <tbody class="bg-surface divide-y divide-border-subtle">
                      <% model[:columns].each do |col| %>
                        <% source_key = "#{model[:name].underscore.tr('/', '_')}.#{col[:name]}" %>
                        <% token_active = platform_token_keys.include?(source_key) %>
                        <tr class="table-row">
                          <td class="px-4 py-2.5 whitespace-nowrap text-mono text-sm text-text-primary">
                            <%= col[:name] %>
                          </td>
                          <td class="px-4 py-2.5 whitespace-nowrap">
                            <%= render BadgeComponent.new(variant: :info, size: :sm) do %><%= col[:type] %><% end %>
                          </td>
                          <td class="px-4 py-2.5 whitespace-nowrap text-center">
                            <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
                                  url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
                                  field: "token_enabled",
                                  on: token_active,
                                  on_label: t("maint_platform.module_settings.show.tokens.available"),
                                  off_label: t("maint_platform.module_settings.show.tokens.not_available"),
                                  extra_params: { token_model: model[:name], token_attribute: col[:name] }
                                ) %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="p-6 text-center">
            <p class="text-body-sm italic"><%= t("maint_platform.module_settings.show.models.empty") %></p>
          </div>
        <% end %>
      </div>
```

- [ ] **Step 3: Write request spec verifying Technical Reference tab rendering**

In `spec/requests/admin/maintenance/platform/module_settings_spec.rb`, add a GET show spec checking the presence of the new tokens section and absence of the routes section:

```ruby
describe "GET /:cid/admin/maintenance/platform/module_settings/:id" do
  let(:owner_user)  { create(:user, :owner, customer: customer) }
  let(:customer)    { Customer.find_by(id: 81721200) || create(:customer, id: 81721200) }
  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  before { sign_in_as(owner_user) }

  it "renders Model Attributes & Template Tokens section and omits Routes card" do
    get admin_maintenance_platform_module_setting_path(customer.id, auth_module)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Model Attributes & Template Tokens")
    expect(response.body).not_to include("maint_platform.module_settings.show.routes.title")
  end
end
```

- [ ] **Step 4: Run request specs to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`  
Expected: PASS with 0 failures.

- [ ] **Step 5: Run full test suite for affected areas**

Run: `bundle exec rspec spec/services/module_model_discovery_spec.rb spec/components/admin/maintenance/platform/module_toggle_component_spec.rb spec/requests/admin/maintenance/platform/module_settings_spec.rb`  
Expected: All specs pass cleanly.

- [ ] **Step 6: Commit**

```bash
git add app/views/admin/maintenance/platform/module_settings/show.html.erb config/locales/maint_platform.en.yml config/locales/maint_platform.zh-CN.yml spec/requests/admin/maintenance/platform/module_settings_spec.rb
git commit -m "feat(platform): display Model Attributes & Template Tokens section and remove Routes card"
```
