# Module Settings Platform Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the platform-owner module settings page, expose editable platform defaults per module (part a) and add a per-model "Extendable" toggle (default off) that governs which models the Entity Builder may extend (part b).

**Architecture:** Persist the extendable-model set as a JSON column on `feature_modules`. The existing `ModuleSettingsController#update` gains two new param branches (`extendable_model`, `config_defaults`). A new `ExtendableModelRegistry` collects owner-flagged models across a customer's enabled modules; a new `base_model_fields` endpoint feeds the already-present (currently dead) entity-form JS. Entity selection of base models persists on a re-added `entities.extendable_models` column and surfaces through the existing `EntityFieldOrganizer` base-fields channel.

**Tech Stack:** Rails 8.1, Trailblazer/Reform (existing), ViewComponent, StimulusJS, RSpec, TailwindCSS. JSON persisted via the app's `JsonSerializable` concern.

---

## File Structure

- `db/migrate/*_add_extendable_models_to_feature_modules.rb` — new `text` column on `feature_modules`.
- `db/migrate/*_add_extendable_models_to_entities.rb` — re-add `text` column on `entities`.
- `app/models/feature_modules/module.rb` — `json_attribute :extendable_models` + `extendable_model?` / `set_extendable_model!`.
- `app/models/entity.rb` — `json_attribute :extendable_models` + accessor in snapshot.
- `app/services/extendable_model_registry.rb` — NEW; cross-module collection for a customer.
- `app/controllers/admin/maintenance/platform/module_settings_controller.rb` — new update branches.
- `app/controllers/admin/maintenance/entities_controller.rb` — `base_model_fields` action.
- `config/routes.rb` — `base_model_fields` collection route; (entities controller already mounted).
- `app/views/admin/maintenance/platform/module_settings/show.html.erb` — Extendable column, Email link card, editable config defaults.
- `app/views/admin/maintenance/entities/_form.html.erb` — "Extend base model(s)" select + wired Stimulus values.
- `app/services/entity_field_organizer.rb` — populate `base_fields` from the entity's extendable models.
- Specs under `spec/models`, `spec/services`, `spec/requests`.

---

## Task 1: Persist extendable-model set on FeatureModules::Module

**Files:**
- Create: `db/migrate/20260629000001_add_extendable_models_to_feature_modules.rb`
- Modify: `app/models/feature_modules/module.rb`
- Test: `spec/models/feature_modules/module_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/feature_modules/module_spec.rb`:

```ruby
RSpec.describe FeatureModules::Module do
  describe "extendable models" do
    let(:mod) { described_class.create!(key: "demo", name: "Demo") }

    it "defaults to no extendable models" do
      expect(mod.extendable_models_json).to eq([])
      expect(mod.extendable_model?("Some::Model")).to be(false)
    end

    it "adds and removes a model class idempotently" do
      mod.set_extendable_model!("Payments::Order", true)
      mod.set_extendable_model!("Payments::Order", true)
      expect(mod.reload.extendable_models_json).to eq(["Payments::Order"])
      expect(mod.extendable_model?("Payments::Order")).to be(true)

      mod.set_extendable_model!("Payments::Order", false)
      expect(mod.reload.extendable_models_json).to eq([])
      expect(mod.extendable_model?("Payments::Order")).to be(false)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/feature_modules/module_spec.rb -e "extendable models"`
Expected: FAIL — `extendable_models_json` undefined.

- [ ] **Step 3: Write the migration**

`db/migrate/20260629000001_add_extendable_models_to_feature_modules.rb`:

```ruby
# frozen_string_literal: true

class AddExtendableModelsToFeatureModules < ActiveRecord::Migration[8.1]
  def change
    add_column :feature_modules, :extendable_models, :text
  end
end
```

Run: `bin/rails db:migrate db:test:prepare`

- [ ] **Step 4: Implement model methods**

In `app/models/feature_modules/module.rb`, after the existing `json_attribute :configuration_schema, default: {}` line add:

```ruby
    json_attribute :extendable_models, default: []
```

And in the public methods area (after `mandatory?`):

```ruby
    def extendable_model?(class_name)
      extendable_models_json.include?(class_name.to_s)
    end

    def set_extendable_model!(class_name, on)
      set = Array(extendable_models_json).dup
      if on
        set |= [class_name.to_s]
      else
        set -= [class_name.to_s]
      end
      update!(extendable_models: set.to_json)
    end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/models/feature_modules/module_spec.rb -e "extendable models"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260629000001_add_extendable_models_to_feature_modules.rb db/schema.rb app/models/feature_modules/module.rb spec/models/feature_modules/module_spec.rb
git commit -m "feat(modules): persist extendable-model set on feature_modules"
```

---

## Task 2: ExtendableModelRegistry service

**Files:**
- Create: `app/services/extendable_model_registry.rb`
- Test: `spec/services/extendable_model_registry_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe ExtendableModelRegistry do
  let(:customer) { Customer.create!(id: 999001, name: "Acme") }

  it "returns only flagged models from modules enabled for the customer" do
    mod = FeatureModules::Module.create!(key: "payment", name: "Payments", status: :active)
    FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: mod, status: :active)
    mod.set_extendable_model!("Payments::Order", true)

    result = described_class.for_customer(customer.id)
    expect(result.map { |r| r[:class_name] }).to include("Payments::Order")
    expect(result.first).to include(:label, :module_key)
  end

  it "excludes models from modules not enabled for the customer" do
    mod = FeatureModules::Module.create!(key: "sms", name: "SMS", status: :active)
    mod.set_extendable_model!("Sms::Message", true)
    # no CustomerAssignment for this customer
    expect(described_class.for_customer(customer.id).map { |r| r[:class_name] }).not_to include("Sms::Message")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/extendable_model_registry_spec.rb`
Expected: FAIL — uninitialized constant `ExtendableModelRegistry`.

- [ ] **Step 3: Implement the service**

`app/services/extendable_model_registry.rb`:

```ruby
# frozen_string_literal: true

# Collects, across all feature modules enabled for a customer, the models the
# platform owner has flagged as extendable. Used to populate the Entity Builder's
# "extend base model" picker so it only ever offers owner-approved models.
class ExtendableModelRegistry
  def self.for_customer(customer_id)
    new(customer_id).call
  end

  def initialize(customer_id)
    @customer_id = customer_id
  end

  def call
    return [] if @customer_id.blank?

    FeatureModules::Module.enabled_for_customer(@customer_id).flat_map do |mod|
      Array(mod.extendable_models_json).map do |class_name|
        { class_name: class_name, label: class_name.demodulize.titleize, module_key: mod.key }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/extendable_model_registry_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/extendable_model_registry.rb spec/services/extendable_model_registry_spec.rb
git commit -m "feat(entities): add ExtendableModelRegistry for owner-approved base models"
```

---

## Task 3: ModuleSettingsController — extendable-model toggle + config defaults

**Files:**
- Modify: `app/controllers/admin/maintenance/platform/module_settings_controller.rb`
- Test: `spec/requests/admin/maintenance/platform/module_settings_spec.rb`

- [ ] **Step 1: Write the failing test**

In the request spec (create if absent; sign in as platform owner — follow existing platform request-spec setup helpers):

```ruby
RSpec.describe "Platform module settings", type: :request do
  # ... owner sign-in setup mirroring other platform/* request specs ...
  let(:mod) { FeatureModules::Module.create!(key: "payment", name: "Payments", status: :active) }

  it "toggles a model as extendable" do
    allow(ModuleModelDiscovery).to receive(:call).with("payment").and_return([{ name: "Payments::Order" }])
    patch "/81721200/admin/maintenance/platform/module_settings/#{mod.id}",
          params: { extendable_model: "Payments::Order", extendable: "1" }
    expect(mod.reload.extendable_model?("Payments::Order")).to be(true)
  end

  it "rejects an unknown class name" do
    allow(ModuleModelDiscovery).to receive(:call).with("payment").and_return([{ name: "Payments::Order" }])
    patch "/81721200/admin/maintenance/platform/module_settings/#{mod.id}",
          params: { extendable_model: "Evil::Klass", extendable: "1" }
    expect(mod.reload.extendable_model?("Evil::Klass")).to be(false)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: FAIL — model not toggled.

- [ ] **Step 3: Implement controller branches**

In `module_settings_controller.rb#update`, add after the existing `apply_required!` line:

```ruby
      apply_extendable_model! if params.key?(:extendable_model)
      apply_config_defaults!  if params.key?(:config_defaults)
```

Add private methods:

```ruby
    def apply_extendable_model!
      class_name = params[:extendable_model].to_s
      known = ModuleModelDiscovery.call(@feature_module.key).any? { |m| m[:name] == class_name }
      return unless known

      @feature_module.set_extendable_model!(class_name, params[:extendable] == "1")
    end

    def apply_config_defaults!
      schema = @feature_module.configuration_schema_json || {}
      return if schema.empty?

      permitted = params.require(:config_defaults).permit(*schema.keys).to_h
      merged = schema.each_with_object({}) do |(key, defn), acc|
        acc[key] = defn.merge("default" => permitted.fetch(key, defn["default"]))
      end
      @feature_module.update!(configuration_schema: merged.to_json)
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/platform/module_settings_controller.rb spec/requests/admin/maintenance/platform/module_settings_spec.rb
git commit -m "feat(platform): toggle extendable models + edit module config defaults"
```

---

## Task 4: Models card — Extendable toggle column + Email link card + editable defaults

**Files:**
- Modify: `app/views/admin/maintenance/platform/module_settings/show.html.erb`

- [ ] **Step 1: Add Extendable column header**

In the Models card `<thead>`, after the Associations `<th>`:

```erb
              <th class="px-6 py-3 text-center text-label">Extendable</th>
```

- [ ] **Step 2: Add Extendable toggle cell**

In the Models `<tbody>` row, after the associations `<td>`:

```erb
                <td class="px-6 py-4 whitespace-nowrap text-center">
                  <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
                        url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
                        field: "extendable",
                        on: @feature_module.extendable_model?(model[:name]),
                        on_label: "Allowed", off_label: "Not allowed"
                      ) do %>
                    <%= hidden_field_tag :extendable_model, model[:name] %>
                  <% end %>
                </td>
```

NOTE: confirm `ModuleToggleComponent` renders block content inside its `<form>`; if it does not accept a block, instead add an `extra_params:` option to the component (see Task 4a).

- [ ] **Step 2a (only if needed): extend ModuleToggleComponent to carry extra hidden params**

Modify `app/components/admin/maintenance/platform/module_toggle_component.rb` initializer to accept `extra_params: {}` and render a hidden input per pair inside the form in its template. Pass `extra_params: { extendable_model: model[:name] }`.

- [ ] **Step 3: Add Email credentials link card**

After the SMS configuration `<% if @feature_module.key == "sms" %>` block, add a parallel block for `email` linking to `admin_maintenance_platform_module_settings_emails_credentials_path(current_customer_id)` with a "Credentials" row (copy the SMS Credentials `<li>` markup, change label/description/icon target path).

- [ ] **Step 4: Make Configuration Schema card editable**

Wrap the existing Configuration Schema table in a `form_with url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module), method: :patch`. Replace the static Default cell with `<%= text_field_tag "config_defaults[#{key}]", schema_def["default"] %>` (use existing `input-field` styling) and add a submit button below the table. Only render the form wrapper when `schema.any?`.

- [ ] **Step 5: Verify render (smoke)**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails runner 'puts ApplicationController.render(template: "admin/maintenance/platform/module_settings/show", assigns: {}) rescue puts $!.message'`
(Or rely on a request spec hitting `show` for an owner — preferred.) Expected: no template error.

- [ ] **Step 6: Commit**

```bash
git add app/views/admin/maintenance/platform/module_settings/show.html.erb app/components/admin/maintenance/platform/module_toggle_component.rb app/components/admin/maintenance/platform/module_toggle_component.html.erb
git commit -m "feat(platform): models extendable toggle, email credentials link, editable config defaults"
```

---

## Task 5: base_model_fields endpoint (feed the dead entity-form JS)

**Files:**
- Modify: `config/routes.rb` (collection route under `resources :entities, controller: "maintenance/entities"`)
- Modify: `app/controllers/admin/maintenance/entities_controller.rb`
- Test: `spec/requests/admin/maintenance/entities_base_model_fields_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
RSpec.describe "Entity base_model_fields", type: :request do
  # owner/admin sign-in for a customer; mirror existing entities request-spec setup
  it "returns columns for a currently-extendable model" do
    mod = FeatureModules::Module.create!(key: "payment", name: "Payments", status: :active)
    FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: mod, status: :active)
    mod.set_extendable_model!("Payments::Order", true)

    get "/#{customer.id}/admin/maintenance/entities/base_model_fields",
        params: { model: "Payments::Order" }, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["fields"]).to be_an(Array)
  end

  it "refuses a non-extendable model" do
    get "/#{customer.id}/admin/maintenance/entities/base_model_fields",
        params: { model: "Payments::Order" }, headers: { "Accept" => "application/json" }
    expect(JSON.parse(response.body)["fields"]).to eq([])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/entities_base_model_fields_spec.rb`
Expected: FAIL — no route.

- [ ] **Step 3: Add route**

In `config/routes.rb`, inside the `resources :entities, controller: "maintenance/entities"` `collection do` block (alongside `get :trash`), add:

```ruby
            get :base_model_fields
```

- [ ] **Step 4: Implement action**

In `app/controllers/admin/maintenance/entities_controller.rb`:

```ruby
    def base_model_fields
      class_name = params[:model].to_s
      allowed = ExtendableModelRegistry.for_customer(current_customer.id).any? { |m| m[:class_name] == class_name }
      fields =
        if allowed && (klass = class_name.safe_constantize) && klass < ApplicationRecord
          klass.column_names
        else
          []
        end
      render json: { fields: fields }
    end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/entities_base_model_fields_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/maintenance/entities_controller.rb spec/requests/admin/maintenance/entities_base_model_fields_spec.rb
git commit -m "feat(entities): base_model_fields endpoint scoped to owner-approved models"
```

---

## Task 6: Entity form — "Extend base model(s)" select + persist selection

**Files:**
- Create: `db/migrate/20260629000002_add_extendable_models_to_entities.rb`
- Modify: `app/models/entity.rb`
- Modify: `app/controllers/admin/maintenance/entities_controller.rb` (permit param)
- Modify: `app/views/admin/maintenance/entities/_form.html.erb`
- Modify: `app/services/entity_field_organizer.rb`
- Test: `spec/models/entity_spec.rb`, `spec/services/entity_field_organizer_spec.rb`

- [ ] **Step 1: Migration to re-add column**

`db/migrate/20260629000002_add_extendable_models_to_entities.rb`:

```ruby
# frozen_string_literal: true

class AddExtendableModelsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :extendable_models, :text
  end
end
```

Run: `bin/rails db:migrate db:test:prepare`

- [ ] **Step 2: Model — json attribute + snapshot**

In `app/models/entity.rb`, add to the json_attribute block:

```ruby
  json_attribute :extendable_models, default: []
```

Include it in `definition_snapshot` (`"extendable_models" => extendable_models_json || []`) and in `apply_definition_snapshot!` (`extendable_models: snap["extendable_models"].to_json`).

- [ ] **Step 3: Permit the param**

In `entities_controller.rb` strong params, add `:extendable_models` (it arrives as a JSON string from the form, mirroring `property_schema`/`associations`). Add a hidden field in the form (Step 4) so the multi-select value is serialized to JSON before submit by the existing `entity-form` controller, OR permit `extendable_models: []` if submitting a raw array. Use the JSON-string hidden-field approach to match `property_schema` convention:

```ruby
      params.require(:entity).permit(..., :extendable_models)
```

- [ ] **Step 4: Form select + Stimulus wiring**

In `_form.html.erb`, add to the `form_with ... data:` hash:

```ruby
              entity_form_extendable_models_value: (@entity.extendable_models_json || []).to_json,
```

Add a new card section (after Basic Information) only when base models exist:

```erb
<% base_models = ExtendableModelRegistry.for_customer(current_customer_id) %>
<div class="card">
  <div class="px-6 py-4 border-b border-border-subtle">
    <h3 class="section-header">Extend Base Model</h3>
  </div>
  <div class="p-6">
    <% if base_models.any? %>
      <select multiple
              class="input-field"
              data-action="change->entity-form#extendableModelChanged">
        <% base_models.each do |bm| %>
          <option value="<%= bm[:class_name] %>"
                  <%= "selected" if (@entity.extendable_models_json || []).include?(bm[:class_name]) %>>
            <%= bm[:label] %> <span class="text-text-muted">(<%= bm[:module_key] %>)</span>
          </option>
        <% end %>
      </select>
      <%= hidden_field_tag "entity[extendable_models]",
            (@entity.extendable_models_json || []).to_json,
            data: { entity_form_target: "extendableModelsField" } %>
    <% else %>
      <p class="text-body-sm italic">No base models are available to extend. A platform owner enables them under Maintenance / Platform / Module Settings.</p>
    <% end %>
  </div>
</div>
```

Update `entity_form_controller.js#extendableModelChanged` to also write the serialized selection into `extendableModelsFieldTarget.value` (add the target to `static targets`). Keep changes minimal — the JS monolith is otherwise untested (per project memory).

- [ ] **Step 5: EntityFieldOrganizer base_fields**

Add a model spec and organizer spec asserting selected base models surface columns into `base_fields`:

```ruby
# spec/services/entity_field_organizer_spec.rb (add)
it "includes columns of selected extendable base models in base_fields" do
  entity = build_entity_with(extendable_models: ["Payments::Order"].to_json)
  sections = described_class.call(entity)
  expect(sections[:base_fields]).to have_key("Payments::Order")
end
```

Implement in `entity_field_organizer.rb#call`:

```ruby
      base_fields: extract_base_fields,
```

```ruby
  def extract_base_fields
    Array(@entity.extendable_models_json).index_with do |class_name|
      klass = class_name.safe_constantize
      next [] unless klass && klass < ApplicationRecord

      system = %w[id customer_id created_at updated_at]
      klass.columns.reject { |c| system.include?(c.name) }.map { |c| { "key" => c.name, "name_slug" => c.name, "type" => c.type.to_s } }
    end
  end
```

- [ ] **Step 6: Run tests**

Run: `bundle exec rspec spec/models/entity_spec.rb spec/services/entity_field_organizer_spec.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260629000002_add_extendable_models_to_entities.rb db/schema.rb app/models/entity.rb app/controllers/admin/maintenance/entities_controller.rb app/views/admin/maintenance/entities/_form.html.erb app/services/entity_field_organizer.rb app/javascript/controllers/entity_form_controller.js spec/models/entity_spec.rb spec/services/entity_field_organizer_spec.rb
git commit -m "feat(entities): extend-base-model picker wired to owner-approved models"
```

---

## Task 7: Full targeted regression run

- [ ] **Step 1: Run touched-layer specs**

Run:
```bash
bundle exec rspec \
  spec/models/feature_modules/module_spec.rb \
  spec/models/entity_spec.rb \
  spec/services/extendable_model_registry_spec.rb \
  spec/services/entity_field_organizer_spec.rb \
  spec/requests/admin/maintenance/platform/module_settings_spec.rb \
  spec/requests/admin/maintenance/entities_base_model_fields_spec.rb
```
Expected: all PASS.

- [ ] **Step 2: Rebuild assets + smoke the page**

Run:
```bash
rm -f public/assets/.manifest.json
bin/rails tailwindcss:build
```
Then a request spec or manual SKIP_AUTH smoke of `/81721200/admin/maintenance/platform/module_settings/<id>`.

- [ ] **Step 3: Final commit if anything outstanding**

```bash
git add -A && git commit -m "test: targeted regression for module settings refactor"
```

---

## Self-Review notes

- Part (a) coverage: Email link card (Task 4 Step 3), editable config defaults (Task 3 + Task 4 Step 4), existing SMS/Payment/Captcha sections retained. Modules with no declared schema simply show no editable defaults — acceptable, documented in spec.
- Part (b) coverage: persistence (Task 1), registry (Task 2), toggle UI + controller (Tasks 3–4), endpoint (Task 5), builder select + entity persistence + base_fields surfacing (Task 6). Default-off guaranteed by empty-array default.
- Conservative boundary: runtime save-back into real base-model rows (dropped `extended_model_entries`) is OUT of scope and noted in the spec; this plan stops at builder selection + page-field surfacing, all test-covered.
- Risk: `ModuleToggleComponent` may not accept block/extra params — Task 4 Step 2a covers the fallback.
