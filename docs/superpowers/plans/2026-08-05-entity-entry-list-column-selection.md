# Entity Entry List Column Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins select/unselect which entity attributes appear as columns on `/:cid/admin/entities/:id`, with per-customer per-entity persistence.

**Architecture:** Store preferences in `EntityIndexSetting` (JSON `config.visible_column_keys`, Member-surface idiom). Resolve table columns via `Admin::Entities::ColumnsBuilder`. Column picker ViewComponent on the show page (reuse Stimulus `dropdown`) PATCHes `Admin::EntityIndexSettingsController` through a Reform contract + Operation.

**Tech Stack:** Rails 8.1 / Ruby 3.2.8 / ViewComponent / Tailwind / Stimulus / Reform / RSpec / Vitest (only if new JS is added — prefer reusing `dropdown_controller`)

**Spec:** `docs/superpowers/specs/2026-08-05-entity-entry-list-column-selection-design.md`

## Global Constraints

- Admin URL only; auth via existing `RouteAuthorization` admin gate
- Multi-tenant: always scope by `current_customer.id`; never trust client `customer_id`
- I18n: every new user-facing string in both `en` and `zh-CN`
- No hard-coded UI strings in views/JS
- System columns `id`, `created_at`, `updated_at` always visible/locked; never persisted in preference
- Attribute identity = `name_slug` from `entity.data_fields` (exclude Calculated)
- Preference scope = per `(customer_id, entity_id)` shared by all tenant admins
- Empty preference key absent → defaults; key present as `[]` → attribute columns hidden; do not coerce `[]` to `nil`
- No column reordering in v1
- Do **not** git commit unless the human explicitly asks
- Prefer reusing `dropdown` Stimulus controller; add new JS only if required (then 100% Vitest coverage)

## File map

| File | Responsibility |
|------|----------------|
| `db/migrate/*_create_entity_index_settings.rb` | Table + unique index |
| `app/models/entity_index_setting.rb` | Overlay model |
| `app/services/admin/entities/columns_builder.rb` | Resolve `@columns` |
| `app/concepts/entity_index_settings/contract/update.rb` | Reform validation |
| `app/concepts/entity_index_settings/operation/update.rb` | Persist overlay |
| `app/controllers/admin/entity_index_settings_controller.rb` | PATCH endpoint |
| `app/controllers/admin/entities_controller.rb` | Use ColumnsBuilder |
| `app/components/admin/entities/column_picker_component.rb` (+ erb) | Chooser UI |
| `app/views/admin/entities/show.html.erb` | Mount picker above table |
| `config/routes.rb` | Nested `resource :index_setting` |
| `config/locales/admin_misc.en.yml` / `.zh-CN.yml` | Copy |
| `config/locales/comp_admin.en.yml` / `.zh-CN.yml` | Component copy if needed |
| Matching specs under `spec/` | Model / service / contract / operation / request / component |

---

### Task 1: `EntityIndexSetting` model + migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_entity_index_settings.rb`
- Create: `app/models/entity_index_setting.rb`
- Create: `spec/models/entity_index_setting_spec.rb`

**Interfaces:**
- Produces: `EntityIndexSetting.for(customer_id:, entity_id:) -> EntityIndexSetting`
- Produces: `#visible_column_keys -> Array<Symbol> | nil`
- Produces: `#write_overlay(visible_column_keys:) -> void` (mutates `config_json`)

- [ ] **Step 1: Write the failing model spec**

```ruby
# spec/models/entity_index_setting_spec.rb
require "rails_helper"

RSpec.describe EntityIndexSetting, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:entity) { create(:entity, customer: customer) }

  describe ".for" do
    it "returns an unsaved record when none exists" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      expect(setting).to be_new_record
      expect(setting.customer_id).to eq(customer.id)
      expect(setting.entity_id).to eq(entity.id)
    end

    it "returns the existing row" do
      existing = described_class.create!(customer_id: customer.id, entity_id: entity.id, config: {})
      expect(described_class.for(customer_id: customer.id, entity_id: entity.id)).to eq(existing)
    end
  end

  describe "#visible_column_keys" do
    it "returns nil when the key is absent (defaults)" do
      setting = described_class.new(config: {})
      expect(setting.visible_column_keys).to be_nil
    end

    it "returns [] when the key is explicitly empty" do
      setting = described_class.new(config: { "visible_column_keys" => [] })
      expect(setting.visible_column_keys).to eq([])
    end

    it "returns symbols when keys are present" do
      setting = described_class.new(config: { "visible_column_keys" => %w[title status] })
      expect(setting.visible_column_keys).to eq(%i[title status])
    end
  end

  describe "#write_overlay" do
    it "persists string keys including empty array" do
      setting = described_class.for(customer_id: customer.id, entity_id: entity.id)
      setting.write_overlay(visible_column_keys: [])
      setting.save!
      expect(setting.reload.visible_column_keys).to eq([])
    end
  end

  it "enforces uniqueness on [customer_id, entity_id]" do
    described_class.create!(customer_id: customer.id, entity_id: entity.id, config: {})
    dup = described_class.new(customer_id: customer.id, entity_id: entity.id, config: {})
    expect(dup).not_to be_valid
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/models/entity_index_setting_spec.rb`
Expected: FAIL (uninitialized constant / missing table)

- [ ] **Step 3: Migration**

```ruby
class CreateEntityIndexSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_index_settings do |t|
      t.references :customer, null: false, foreign_key: true, type: :bigint
      t.references :entity,   null: false, foreign_key: true, type: :bigint
      t.text :config, null: false, default: "{}"
      t.timestamps
    end

    add_index :entity_index_settings, %i[customer_id entity_id], unique: true,
              name: "idx_entity_index_settings_on_customer_and_entity"
  end
end
```

Use `t.text :config` + `JsonSerializable` like `Member::SurfaceSetting` (not native json column) for consistency.

- [ ] **Step 4: Model**

```ruby
# app/models/entity_index_setting.rb
class EntityIndexSetting < ApplicationRecord
  include JsonSerializable

  belongs_to :customer
  belongs_to :entity

  json_attribute :config, default: {}

  validates :entity_id, uniqueness: { scope: :customer_id }

  def self.for(customer_id:, entity_id:)
    scope = where(customer_id: customer_id, entity_id: entity_id)
    scope.first || scope.new
  end

  def visible_column_keys
    cfg = config_json || {}
    return nil unless cfg.key?("visible_column_keys")
    Array(cfg["visible_column_keys"]).map(&:to_sym)
  end

  def write_overlay(visible_column_keys:)
    next_config = (config_json || {}).dup
    next_config["visible_column_keys"] = Array(visible_column_keys).map(&:to_s)
    self.config_json = next_config
  end
end
```

- [ ] **Step 5: Migrate + run spec**

Run: `bin/rails db:migrate` and `bundle exec rspec spec/models/entity_index_setting_spec.rb`
Expected: PASS

---

### Task 2: `Admin::Entities::ColumnsBuilder`

**Files:**
- Create: `app/services/admin/entities/columns_builder.rb`
- Create: `spec/services/admin/entities/columns_builder_spec.rb`
- Modify: `app/controllers/admin/entities_controller.rb`

**Interfaces:**
- Consumes: `Entity`, `EntityIndexSetting#visible_column_keys`
- Produces: `Admin::Entities::ColumnsBuilder.call(entity:, setting:, t:) -> Array<Hash>`  
  where each hash has `:key`, `:label`, `:sortable`, and optionally `:searchable`

Column rules:
- Always append system columns `id`, `created_at`, `updated_at` (labels via `t.("admin_misc.entities.columns.<key>")`, sortable: true). Prefer attribute columns **before** system columns to match today’s order (`search_cols + base`).
- Candidate attribute slugs = `entity.data_fields` with present `name_slug`.
- Labels: `display_label.presence || name.presence || name_slug.humanize`
- If `setting.visible_column_keys.nil?`: default keys = `(searchable_field_keys as strings ∩ candidates)`; if that intersection is empty, `candidates.first(3)`.
- If preference present (including `[]`): `preferred.map(&:to_s) & candidates`, preserving preference order.
- Attribute columns: `sortable: false`, `searchable: false` (JSON `data` column — SQL sort/search on slug is invalid; do not perpetuate broken flags for newly chosen attrs). System columns remain sortable.
- Ignore stale preferred keys not in candidates.
- Exclude Calculated fields via `data_fields`.

- [ ] **Step 1: Failing service spec** covering default, preference, `[]`, stale keys, calculated exclusion, label fallback, per-entity candidate set.

- [ ] **Step 2: Implement ColumnsBuilder**

```ruby
module Admin
  module Entities
    class ColumnsBuilder
      SYSTEM_KEYS = %i[id created_at updated_at].freeze

      def self.call(entity:, setting:, t: I18n.method(:t))
        new(entity:, setting:, t:).call
      end

      def initialize(entity:, setting:, t:)
        @entity = entity
        @setting = setting
        @t = t
      end

      def call
        attribute_columns + system_columns
      end

      private

      def attribute_columns
        selected_slugs.map { |slug| attribute_column(slug) }
      end

      def selected_slugs
        preferred = @setting.visible_column_keys
        if preferred.nil?
          default_slugs
        else
          preferred.map(&:to_s) & candidate_slugs
        end
      end

      def default_slugs
        from_searchable = Array(@entity.searchable_field_keys).map(&:to_s) & candidate_slugs
        return from_searchable if from_searchable.any?
        candidate_slugs.first(3)
      end

      def candidate_slugs
        @candidate_slugs ||= @entity.data_fields.filter_map { |f| f["name_slug"].presence }
      end

      def fields_by_slug
        @fields_by_slug ||= @entity.data_fields.index_by { |f| f["name_slug"] }
      end

      def attribute_column(slug)
        field = fields_by_slug[slug] || {}
        label = field["display_label"].presence || field["name"].presence || slug.to_s.humanize
        { key: slug.to_sym, label: label, sortable: false, searchable: false }
      end

      def system_columns
        SYSTEM_KEYS.map do |key|
          {
            key: key,
            label: @t.call("admin_misc.entities.columns.#{key}"),
            sortable: true
          }
        end
      end
    end
  end
end
```

- [ ] **Step 3: Wire `Admin::EntitiesController#show`**

Replace private `columns_for` with:

```ruby
setting = EntityIndexSetting.for(customer_id: current_customer.id, entity_id: @entity.id)
columns = Admin::Entities::ColumnsBuilder.call(entity: @entity, setting: setting)
```

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/services/admin/entities/columns_builder_spec.rb spec/requests/admin/entities_spec.rb` (or whatever covers show)
Expected: PASS (update any brittle column assertions)

---

### Task 3: Update contract + operation + route + controller

**Files:**
- Create: `app/concepts/entity_index_settings/contract/update.rb`
- Create: `app/concepts/entity_index_settings/operation/update.rb`
- Create: `app/controllers/admin/entity_index_settings_controller.rb`
- Modify: `config/routes.rb` (nested under admin entities)
- Create: `spec/concepts/entity_index_settings/contract/update_spec.rb`
- Create: `spec/concepts/entity_index_settings/operation/update_spec.rb`
- Create: `spec/requests/admin/entity_index_settings_spec.rb`

**Interfaces:**
- Route: `PATCH /:customer_id/admin/entities/:entity_id/index_setting` → `admin_entity_index_setting_path(customer_id, entity_id)`
- `EntityIndexSettings::Operation::Update.call(customer:, entity:, params:) -> Result(success?, errors)`
- Params: `{ visible_column_keys: [...] }` (array; missing checkboxes ⇒ omit from array; use hidden empty field pattern so uncheck-all submits `[]`)

Contract rules (mirror Member `MAX_VISIBLE_KEYS = 50`):
- `visible_column_keys` max 50 entries
- each key must be in entity `data_fields` `name_slug` set
- unknown keys → validation error

- [ ] **Step 1: Contract**

```ruby
module EntityIndexSettings
  module Contract
    class Update < Reform::Form
      MAX_VISIBLE_KEYS = 50

      property :visible_column_keys, virtual: true

      validate :visible_column_keys_shape

      def visible_column_keys_shape
        keys = Array(visible_column_keys).map(&:to_s)
        if keys.size > MAX_VISIBLE_KEYS
          errors.add(:visible_column_keys, I18n.t("admin_misc.entities.index_setting.errors.too_many"))
        end
        # allowed_slugs injected via build — see operation
      end
    end
  end
end
```

Prefer validating allowed slugs in the Operation after building the form with entity context (pass `allowed_slugs:` into a custom validator, or validate in Operation before save). Keep Reform for shape/size; Operation rejects unknown slugs with I18n error.

- [ ] **Step 2: Operation**

```ruby
module EntityIndexSettings
  module Operation
    class Update
      Result = Struct.new(:success?, :errors, keyword_init: true)

      def self.call(customer:, entity:, params:)
        payload = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        keys = Array(payload[:visible_column_keys] || payload["visible_column_keys"]).map(&:to_s)
        allowed = entity.data_fields.filter_map { |f| f["name_slug"].presence }

        if keys.size > Contract::Update::MAX_VISIBLE_KEYS
          errors = ActiveModel::Errors.new(EntityIndexSetting.new)
          errors.add(:visible_column_keys, I18n.t("admin_misc.entities.index_setting.errors.too_many"))
          return Result.new(success?: false, errors: errors)
        end

        unknown = keys - allowed
        if unknown.any?
          errors = ActiveModel::Errors.new(EntityIndexSetting.new)
          errors.add(:visible_column_keys, I18n.t("admin_misc.entities.index_setting.errors.invalid_keys"))
          return Result.new(success?: false, errors: errors)
        end

        setting = EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id)
        setting.write_overlay(visible_column_keys: keys)
        setting.save!
        Result.new(success?: true, errors: nil)
      end
    end
  end
end
```

(Adjust to use Reform if preferred; Operation+manual validation is acceptable if it matches sibling simplicity — prefer Reform when easy.)

- [ ] **Step 3: Controller**

```ruby
module Admin
  class EntityIndexSettingsController < ApplicationController
    dashboard_menu_item :entities

    def update
      entity = Entity.for_customer(current_customer.id).find(params[:entity_id])
      result = EntityIndexSettings::Operation::Update.call(
        customer: current_customer,
        entity: entity,
        params: params.require(:entity_index_setting).permit(visible_column_keys: [])
      )

      if result.success?
        redirect_to admin_entity_path(current_customer.id, entity),
                    notice: t("admin_misc.entities.index_setting.updated")
      else
        redirect_to admin_entity_path(current_customer.id, entity),
                    alert: result.errors.full_messages.to_sentence
      end
    end
  end
end
```

- [ ] **Step 4: Routes** — inside existing `resources :entities, only: %i[index show] do` block:

```ruby
resource :index_setting, only: :update, controller: "entity_index_settings"
```

- [ ] **Step 5: Request specs** — admin success; member/anonymous denied; cross-tenant admin cannot update other customer; unknown keys rejected; empty array hides attribute columns on subsequent GET show.

---

### Task 4: Column picker UI + I18n

**Files:**
- Create: `app/components/admin/entities/column_picker_component.rb`
- Create: `app/components/admin/entities/column_picker_component.html.erb`
- Create: `spec/components/admin/entities/column_picker_component_spec.rb`
- Modify: `app/views/admin/entities/show.html.erb`
- Modify: `config/locales/admin_misc.en.yml`, `admin_misc.zh-CN.yml`
- Modify: `config/locales/comp_admin.en.yml`, `comp_admin.zh-CN.yml` as needed

**Interfaces:**
- `Admin::Entities::ColumnPickerComponent.new(entity:, setting:, update_path:)`
- Choices: locked system columns (checked, disabled) + one checkbox per `data_fields` slug
- Checked state for attributes: if `setting.visible_column_keys.nil?` then default selected set from ColumnsBuilder defaults; else `visible_column_keys.include?(slug)`
- Form: `form_with url: update_path, method: :patch`  
  Include `<input type="hidden" name="entity_index_setting[visible_column_keys][]" value="">` so uncheck-all submits empty array  
  Disabled locked checkboxes need matching hidden inputs if we ever persisted them — we do **not** submit system keys
- UI: wrap with `data-controller="dropdown"`; button toggles; menu hosts the form. No new Stimulus file.

- [ ] **Step 1: Locale keys (en byte-identical to intended English)**

```yaml
# admin_misc.en.yml under entities:
index_setting:
  updated: "Column preferences saved"
  errors:
    too_many: "too many columns selected"
    invalid_keys: "contains unknown attributes"
```

```yaml
# comp_admin (or admin_misc) for picker:
column_picker:
  button: "Columns"
  title: "Visible columns"
  apply: "Apply"
```

Reuse `comp_admin.shared.always_shown` for locked hint. Add zh-CN idiomatic matches.

- [ ] **Step 2: Component** — Tailwind popover panel (`absolute right-0 z-20 mt-2 w-72 max-h-80 overflow-y-auto ...`), checkbox grid matching Member surface form density, Apply button `variant: :primary` via `ButtonComponent` if available.

- [ ] **Step 3: Show view**

```erb
<%= render AdminPageComponent.new(...) do %>
  <div class="mb-3 flex justify-end">
    <%= render Admin::Entities::ColumnPickerComponent.new(
      entity: @entity,
      setting: @setting,
      update_path: admin_entity_index_setting_path(current_customer.id, @entity)
    ) %>
  </div>
  <%= render AdminTableComponent.new(...) %>
<% end %>
```

Controller must assign `@setting` in `#show`.

- [ ] **Step 4: Component + request smoke specs** — picker lists entity-specific attribute labels; Apply path present; locked system columns rendered disabled.

---

### Task 5: QA hardening + release verification

**Files:** touched specs only

- [ ] **Step 1: Run focused suite**

```bash
bundle exec rspec \
  spec/models/entity_index_setting_spec.rb \
  spec/services/admin/entities/columns_builder_spec.rb \
  spec/concepts/entity_index_settings/ \
  spec/requests/admin/entity_index_settings_spec.rb \
  spec/components/admin/entities/column_picker_component_spec.rb \
  spec/requests/admin/entities_spec.rb
```

Expected: all PASS

- [ ] **Step 2: If any new JS was added**, run `npx vitest run --coverage` and ensure 100% on touched files. If only `dropdown` was reused, skip.

- [ ] **Step 3: Manual smoke** (dev server)

```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Open `/81721200/admin/entities/2`, toggle columns, Apply, reload — columns persist; second entity unaffected.

- [ ] **Step 4: Dispatch parallel review** — `anysys-tech-lead` + `anysys-code-reviewer` on the branch diff; fix any blocking findings.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Per-customer per-entity persistence | 1, 3 |
| Default = searchable / first-3 fallback | 2 |
| System columns locked/always shown | 2, 4 |
| Chooser from resolved `data_fields` | 2, 4 |
| Stale keys ignored | 2 |
| Empty `[]` hides attribute columns | 1, 2, 3 |
| Admin auth / tenant isolation | 3 |
| I18n en+zh-CN | 4 |
| No global AdminTable redesign | 4 (page-local picker) |
| No reordering | (omitted) |

## Self-review notes

- Empty-array vs nil semantics differ from `Member::SurfaceSetting` on purpose — documented in Task 1.
- Attribute columns intentionally not SQL-searchable/sortable (JSON `data`).
- No commit steps — human commits after review.
