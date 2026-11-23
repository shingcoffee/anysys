# Entity Attribute Inline Grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the modal-driven (dead) grouping with an inline, list-driven grouping experience on the entity edit page, with first-class group metadata (name/description/icon/color), drag-and-drop ordering, and propagation to consumer surfaces.

**Architecture:** Add an `attribute_groups` JSONB column to `entities`; each attribute carries a `group_id` reference inside `property_schema`. Inline UI lives on the entity edit page driven by two new Stimulus managers (`group_manager`, `dnd_manager`) under `controllers/entity_form/`. Server-side validation enforces group shape, ID/name uniqueness, and `group_id` referential integrity. A one-time data migration converts legacy `group` strings to group records + `group_id` references. Consumer surfaces (show page, page-builder field picker, member surface, contract/model generators) read grouped data via a new `Entity#grouped_property_schema` method.

**Tech Stack:** Rails 8.1.2, ViewComponent (existing), TailwindCSS, StimulusJS, RSpec, Capybara.

**Reference spec:** `docs/superpowers/specs/2026-05-26-entity-attribute-inline-grouping-design.md`

---

## File Map

### New files
- `db/migrate/<ts>_add_attribute_groups_to_entities.rb`
- `db/migrate/<ts>_backfill_attribute_groups.rb`
- `app/services/entity_attribute_group_options.rb` (module with `ICONS` / `COLORS` / defaults)
- `app/helpers/entity_attribute_grouping_helper.rb`
- `app/views/admin/maintenance/entities/_group_edit_modal.html.erb`
- `app/javascript/controllers/entity_form/group_manager.js`
- `app/javascript/controllers/entity_form/dnd_manager.js`
- `spec/models/entity_grouped_schema_spec.rb`
- `spec/helpers/entity_attribute_grouping_helper_spec.rb`
- `spec/system/entities_attribute_grouping_spec.rb`
- `spec/migrations/backfill_attribute_groups_spec.rb`

### Modified files
- `app/models/entity.rb` — add `json_attribute :attribute_groups, default: []`, add `grouped_property_schema`
- `app/models/concerns/entity_schema_validation.rb` — validate group shape / uniqueness / dangling group_id
- `app/controllers/admin/maintenance/entities_controller.rb` — strong params include `attribute_groups`
- `app/views/admin/maintenance/entities/_attributes_table.html.erb` — restructure for grouped rendering, selection toolbar, hidden groups JSON input, color bars, kebab menus (editable + read-only modes)
- `app/views/admin/maintenance/entities/edit.html.erb` and `new.html.erb` — render the group edit modal partial once per form
- `app/javascript/controllers/entity_form/schema_manager.js` — read/write `group_id`, drive grouping off groups JSON, add `moveRowTo` / `moveGroupTo` / `syncAttributeGroups`
- `app/javascript/controllers/entity_form/attribute_manager.js` — drop `canonicalizeGroup` and `modalGroup` reads
- `app/javascript/controllers/entity_form/modal_manager.js` — drop `modalGroup` reset/prefill (no-op if not referenced)
- `app/javascript/controllers/entity_form/template_builder.js` — row HTML adds checkbox cell + drag grip; group header HTML adds color bar, kebab, drag grip, "Empty" badge support
- `app/javascript/controllers/entity_form/index.js` — export the two new managers
- `app/javascript/controllers/entity_form_controller.js` — register new targets and action delegations
- `app/services/member/entity_surface_builder.rb` — emit `groups` key in surface output (best-effort; member surface is index/detail, so groups land on the detail section)
- `app/services/entity_field_organizer.rb` — add `grouped_organized_fields`
- `app/services/page_field_populator.rb` — carry group metadata onto generated page fields when present
- `spec/models/entity_spec.rb` — extend with grouped_property_schema cases
- `spec/models/concerns/entity_schema_validation_spec.rb` — extend with group validation cases
- `spec/requests/maintenance/entities_spec.rb` — extend with PATCH round-trip case
- `spec/services/member/entity_surface_builder_spec.rb` — extend with grouped output case

### Worktree
Because this is a large, multi-commit feature, execute under `git worktree` at `.worktrees/entity-attribute-inline-grouping` (branch `worktree-entity-attribute-inline-grouping`). The user permits auto-commit on worktree branches.

---

## Task 1: Set up worktree

**Files:**
- Create: `.worktrees/entity-attribute-inline-grouping/` (via worktree)

- [ ] **Step 1: Create the worktree off current master**

```bash
git worktree add -b worktree-entity-attribute-inline-grouping .worktrees/entity-attribute-inline-grouping master
```

Expected: worktree created at the path, on a fresh branch from `master`.

- [ ] **Step 2: Copy the untracked spec into the worktree**

Run all subsequent tasks **inside the worktree directory** (`cd .worktrees/entity-attribute-inline-grouping`). The spec on master is untracked; copy it in and commit it as the first commit on the branch:

```bash
cp ../../docs/superpowers/specs/2026-05-26-entity-attribute-inline-grouping-design.md \
   docs/superpowers/specs/2026-05-26-entity-attribute-inline-grouping-design.md
cp ../../docs/superpowers/plans/2026-05-27-entity-attribute-inline-grouping.md \
   docs/superpowers/plans/2026-05-27-entity-attribute-inline-grouping.md
git add docs/superpowers/specs docs/superpowers/plans
git commit -m "docs(entity-grouping): import spec + plan"
```

---

## Task 2: Add the `attribute_groups` JSONB column

**Files:**
- Create: `db/migrate/<ts>_add_attribute_groups_to_entities.rb`
- Modify: `app/models/entity.rb` (add `json_attribute :attribute_groups, default: []`)

- [ ] **Step 1: Generate the migration**

```bash
bin/rails g migration AddAttributeGroupsToEntities
```

- [ ] **Step 2: Write the migration body**

Content of the new migration file:

```ruby
# frozen_string_literal: true

class AddAttributeGroupsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :attribute_groups, :jsonb, default: [], null: false
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs cleanly; `entities.attribute_groups` exists with default `[]`.

- [ ] **Step 4: Wire the json_attribute on the model**

In `app/models/entity.rb`, add the new declaration right after the existing `json_attribute` lines:

```ruby
json_attribute :property_schema,    default: []
json_attribute :default_properties, default: {}
json_attribute :associations,       default: []
json_attribute :attribute_groups,   default: []
```

- [ ] **Step 5: Add a model spec covering the new accessor**

Append to `spec/models/entity_spec.rb` (use the existing `describe Entity` block; add a new context):

```ruby
describe "#attribute_groups_json" do
  let(:entity) { create(:entity) }

  it "defaults to an empty array" do
    expect(entity.attribute_groups_json).to eq([])
  end

  it "round-trips an array of group hashes" do
    entity.update!(attribute_groups: [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }])
    expect(entity.reload.attribute_groups_json).to eq([
      { "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }
    ])
  end
end
```

- [ ] **Step 6: Run the spec**

```bash
bundle exec rspec spec/models/entity_spec.rb -e "#attribute_groups_json"
```

Expected: 2 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/entity.rb spec/models/entity_spec.rb
git commit -m "feat(entity-grouping): add attribute_groups jsonb column"
```

---

## Task 3: Add the `EntityAttributeGroupOptions` module

**Files:**
- Create: `app/services/entity_attribute_group_options.rb`
- Test: `spec/services/entity_attribute_group_options_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/services/entity_attribute_group_options_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityAttributeGroupOptions do
  it "exposes a non-empty ICONS map keyed by string slug" do
    expect(described_class::ICONS).to be_a(Hash)
    expect(described_class::ICONS).not_to be_empty
    expect(described_class::ICONS.keys).to all(be_a(String))
  end

  it "exposes a non-empty COLORS array of string tokens" do
    expect(described_class::COLORS).to be_an(Array)
    expect(described_class::COLORS).not_to be_empty
    expect(described_class::COLORS).to all(be_a(String))
  end

  it "exposes string defaults that appear in the catalogs" do
    expect(described_class::ICONS).to have_key(described_class::DEFAULT_ICON)
    expect(described_class::COLORS).to include(described_class::DEFAULT_COLOR)
  end

  it "freezes all catalog constants" do
    expect(described_class::ICONS).to be_frozen
    expect(described_class::COLORS).to be_frozen
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/services/entity_attribute_group_options_spec.rb
```

Expected: failure with `NameError: uninitialized constant EntityAttributeGroupOptions`.

- [ ] **Step 3: Implement the module**

Create `app/services/entity_attribute_group_options.rb`:

```ruby
# frozen_string_literal: true

# Catalog of allowed icon keys + color tokens for entity attribute groups.
# Shared by server-side rendering (helper) and client-side rendering (template_builder
# reads class lists from a `<template>` block, not hardcoded).
module EntityAttributeGroupOptions
  ICONS = {
    "folder"    => :folder,
    "user"      => :user,
    "briefcase" => :briefcase,
    "map-pin"   => :map_pin,
    "mail"      => :mail,
    "phone"     => :phone,
    "calendar"  => :calendar,
    "tag"       => :tag,
    "settings"  => :settings,
    "bell"      => :bell,
    "link"      => :link,
    "file"      => :file
  }.freeze

  COLORS = %w[slate indigo sky teal emerald amber rose violet].freeze

  DEFAULT_ICON  = "folder"
  DEFAULT_COLOR = "slate"
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/services/entity_attribute_group_options_spec.rb
```

Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/entity_attribute_group_options.rb spec/services/entity_attribute_group_options_spec.rb
git commit -m "feat(entity-grouping): add attribute group icon/color catalogs"
```

---

## Task 4: Validate group shape on `EntitySchemaValidation`

**Files:**
- Modify: `app/models/concerns/entity_schema_validation.rb`
- Modify: `spec/models/concerns/entity_schema_validation_spec.rb`

- [ ] **Step 1: Write the failing specs**

Append to `spec/models/concerns/entity_schema_validation_spec.rb` (inside the top-level `describe EntitySchemaValidation` block):

```ruby
describe "attribute group validation" do
  let(:entity) { build(:entity) }

  it "is valid with no groups and no group_ids" do
    entity.attribute_groups = []
    entity.property_schema  = [{ "name" => "a", "name_slug" => "a" }]
    expect(entity).to be_valid
  end

  it "is valid with a well-formed group + matching group_id" do
    entity.attribute_groups = [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }]
    entity.property_schema  = [{ "name" => "email", "name_slug" => "email", "group_id" => "g_1" }]
    expect(entity).to be_valid
  end

  it "rejects duplicate group ids" do
    entity.attribute_groups = [
      { "id" => "g_1", "name" => "A", "icon" => "folder", "color" => "slate" },
      { "id" => "g_1", "name" => "B", "icon" => "folder", "color" => "slate" }
    ]
    expect(entity).not_to be_valid
    expect(entity.errors[:attribute_groups].join).to match(/duplicate/i)
  end

  it "rejects duplicate group names case-insensitively" do
    entity.attribute_groups = [
      { "id" => "g_1", "name" => "Contact", "icon" => "folder", "color" => "slate" },
      { "id" => "g_2", "name" => "contact", "icon" => "folder", "color" => "slate" }
    ]
    expect(entity).not_to be_valid
    expect(entity.errors[:attribute_groups].join).to match(/duplicate/i)
  end

  it "rejects unknown icon" do
    entity.attribute_groups = [{ "id" => "g_1", "name" => "A", "icon" => "rocket", "color" => "slate" }]
    expect(entity).not_to be_valid
    expect(entity.errors[:attribute_groups].join).to match(/icon/i)
  end

  it "rejects unknown color" do
    entity.attribute_groups = [{ "id" => "g_1", "name" => "A", "icon" => "folder", "color" => "neon" }]
    expect(entity).not_to be_valid
    expect(entity.errors[:attribute_groups].join).to match(/color/i)
  end

  it "rejects blank group name" do
    entity.attribute_groups = [{ "id" => "g_1", "name" => "  ", "icon" => "folder", "color" => "slate" }]
    expect(entity).not_to be_valid
    expect(entity.errors[:attribute_groups].join).to match(/name/i)
  end

  it "rejects dangling group_id on an attribute" do
    entity.attribute_groups = [{ "id" => "g_1", "name" => "A", "icon" => "folder", "color" => "slate" }]
    entity.property_schema  = [{ "name" => "x", "name_slug" => "x", "group_id" => "g_missing" }]
    expect(entity).not_to be_valid
    expect(entity.errors[:property_schema].join).to match(/group_id/i)
  end
end
```

- [ ] **Step 2: Run the specs to confirm they fail**

```bash
bundle exec rspec spec/models/concerns/entity_schema_validation_spec.rb -e "attribute group validation"
```

Expected: 8 examples, 7 failing (the first "no groups" example may already pass).

- [ ] **Step 3: Implement validation**

Replace the body of `app/models/concerns/entity_schema_validation.rb` with:

```ruby
# frozen_string_literal: true

# Custom validations for Entity property schema, attribute groups, and associations.
module EntitySchemaValidation
  extend ActiveSupport::Concern

  included do
    validate :validate_unique_attribute_names
    validate :validate_unique_attribute_slugs
    validate :validate_attribute_groups_shape
    validate :validate_attribute_group_uniqueness
    validate :validate_attribute_group_references
    validate :validate_no_bridge_entity_conflicts
  end

  private

  def validate_unique_attribute_names
    duplicates = find_duplicates(attribute_values_for("name"))
    errors.add(:property_schema, "has duplicate attribute names: #{duplicates.join(', ')}") if duplicates.any?
  end

  def validate_unique_attribute_slugs
    duplicates = find_duplicates(attribute_values_for("name_slug"))
    errors.add(:property_schema, "has duplicate attribute slugs: #{duplicates.join(', ')}") if duplicates.any?
  end

  def attribute_values_for(key)
    (property_schema_json || []).filter_map { |attr| attr[key] }
  end

  def find_duplicates(array)
    array.group_by(&:itself).select { |_, v| v.size > 1 }.keys
  end

  def validate_attribute_groups_shape
    groups = attribute_groups_json || []
    groups.each_with_index do |g, i|
      label = "group ##{i + 1}"
      if !g.is_a?(Hash) || g["id"].to_s.strip.empty?
        errors.add(:attribute_groups, "#{label}: id is blank")
        next
      end
      if g["name"].to_s.strip.empty? || g["name"].to_s.length > 60
        errors.add(:attribute_groups, "#{label}: name must be 1..60 characters")
      end
      unless EntityAttributeGroupOptions::ICONS.key?(g["icon"].to_s)
        errors.add(:attribute_groups, "#{label}: icon '#{g["icon"]}' is not allowed")
      end
      unless EntityAttributeGroupOptions::COLORS.include?(g["color"].to_s)
        errors.add(:attribute_groups, "#{label}: color '#{g["color"]}' is not allowed")
      end
    end
  end

  def validate_attribute_group_uniqueness
    groups = attribute_groups_json || []
    ids   = find_duplicates(groups.map { |g| g["id"].to_s })
    names = find_duplicates(groups.map { |g| g["name"].to_s.strip.downcase })
    errors.add(:attribute_groups, "has duplicate ids: #{ids.join(', ')}") if ids.any?
    errors.add(:attribute_groups, "has duplicate names: #{names.join(', ')}") if names.any?
  end

  def validate_attribute_group_references
    known_ids = Set.new((attribute_groups_json || []).map { |g| g["id"].to_s })
    (property_schema_json || []).each do |attr|
      gid = attr["group_id"]
      next if gid.nil? || gid.to_s.empty?
      unless known_ids.include?(gid.to_s)
        errors.add(:property_schema, "attribute '#{attr["name"]}' has unknown group_id '#{gid}'")
      end
    end
  end

  def validate_no_bridge_entity_conflicts
    return if bridge_entity?

    associations = associations_list
    return if associations.empty?

    conflicts = []
    associations.each do |assoc|
      target_entity_id = assoc['target_entity_id']
      next unless target_entity_id

      target_entity = Entity.where(customer_id: customer_id).find_by(id: target_entity_id)
      next unless target_entity

      bridge_name      = generate_bridge_name(name, target_entity.name)
      bridge_name_slug = bridge_name.parameterize(separator: '_')
      existing_bridge_id = assoc['bridge_entity_id']
      conflicting_entity = Entity.unscope(:where)
                                 .where(customer_id: customer_id, name_slug: bridge_name_slug)
                                 .where.not(id: existing_bridge_id)
                                 .first
      next unless conflicting_entity

      status_info = conflicting_entity.inactive? ? " (in trash)" : ""
      conflicts << "Bridge entity '#{bridge_name}' for association with '#{target_entity.name}' conflicts with existing entity '#{conflicting_entity.name}'#{status_info}"
    end

    if conflicts.any?
      errors.add(:associations, "#{conflicts.join('. ')}. Please rename this entity or the conflicting entity before saving.")
    end
  end
end
```

- [ ] **Step 4: Run the specs to confirm they pass**

```bash
bundle exec rspec spec/models/concerns/entity_schema_validation_spec.rb
```

Expected: full file passes (existing examples unaffected; new group examples now pass).

- [ ] **Step 5: Commit**

```bash
git add app/models/concerns/entity_schema_validation.rb spec/models/concerns/entity_schema_validation_spec.rb
git commit -m "feat(entity-grouping): validate group shape, uniqueness, references"
```

---

## Task 5: Add `Entity#grouped_property_schema`

**Files:**
- Modify: `app/models/entity.rb`
- Test: `spec/models/entity_spec.rb`

- [ ] **Step 1: Write the failing specs**

Append to `spec/models/entity_spec.rb`:

```ruby
describe "#grouped_property_schema" do
  let(:entity) { create(:entity) }

  it "returns an empty array when no groups and no attributes" do
    entity.update!(attribute_groups: [], property_schema: [])
    expect(entity.grouped_property_schema).to eq([])
  end

  it "preserves group order and assigns matching attributes" do
    entity.update!(
      attribute_groups: [
        { "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" },
        { "id" => "g_2", "name" => "Job",     "icon" => "briefcase", "color" => "teal" }
      ],
      property_schema: [
        { "name" => "email", "name_slug" => "email", "group_id" => "g_1" },
        { "name" => "title", "name_slug" => "title", "group_id" => "g_2" },
        { "name" => "phone", "name_slug" => "phone", "group_id" => "g_1" }
      ]
    )

    result = entity.grouped_property_schema
    expect(result.size).to eq(2)
    expect(result[0][:group]["id"]).to eq("g_1")
    expect(result[0][:attributes].map { |a| a["name"] }).to eq(%w[email phone])
    expect(result[1][:group]["id"]).to eq("g_2")
    expect(result[1][:attributes].map { |a| a["name"] }).to eq(%w[title])
  end

  it "appends ungrouped attributes as the last section with group: nil" do
    entity.update!(
      attribute_groups: [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }],
      property_schema: [
        { "name" => "email", "name_slug" => "email", "group_id" => "g_1" },
        { "name" => "notes", "name_slug" => "notes" }
      ]
    )

    result = entity.grouped_property_schema
    expect(result.last[:group]).to be_nil
    expect(result.last[:attributes].map { |a| a["name"] }).to eq(%w[notes])
  end

  it "still includes a group with no attributes (empty groups persist)" do
    entity.update!(
      attribute_groups: [{ "id" => "g_1", "name" => "Empty", "icon" => "folder", "color" => "slate" }],
      property_schema: []
    )
    result = entity.grouped_property_schema
    expect(result.size).to eq(1)
    expect(result[0][:attributes]).to eq([])
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/models/entity_spec.rb -e "#grouped_property_schema"
```

Expected: 4 examples, 4 failing.

- [ ] **Step 3: Implement the method**

In `app/models/entity.rb`, add inside the `# Public Methods` block (after `data_fields`):

```ruby
# Returns [{ group: <hash or nil>, attributes: [...] }, ...] preserving group order.
# Ungrouped attributes appear last as a section with group: nil.
def grouped_property_schema
  groups = attribute_groups_json || []
  attrs  = property_schema_json  || []
  by_id  = attrs.group_by { |a| a["group_id"].presence }

  sections = groups.map { |g| { group: g, attributes: by_id[g["id"]] || [] } }
  ungrouped = by_id[nil]
  sections << { group: nil, attributes: ungrouped } if ungrouped.present?
  sections
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/models/entity_spec.rb -e "#grouped_property_schema"
```

Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/entity.rb spec/models/entity_spec.rb
git commit -m "feat(entity-grouping): add Entity#grouped_property_schema"
```

---

## Task 6: Backfill legacy `group` strings into `attribute_groups`

**Files:**
- Create: `db/migrate/<ts>_backfill_attribute_groups.rb`
- Test: `spec/migrations/backfill_attribute_groups_spec.rb`

- [ ] **Step 1: Generate the migration scaffold**

```bash
bin/rails g migration BackfillAttributeGroups
```

- [ ] **Step 2: Write the migration body**

```ruby
# frozen_string_literal: true

# Idempotent backfill: convert legacy `group` string keys on each attribute into
# first-class `attribute_groups` rows + `group_id` references on the attribute.
class BackfillAttributeGroups < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Entity.unscoped.find_each(batch_size: 200) do |entity|
      attrs  = entity.read_attribute(:property_schema) || []
      groups = entity.read_attribute(:attribute_groups) || []

      # Skip if attributes already use group_id (idempotent).
      next if attrs.any? { |a| a["group_id"].present? } && attrs.none? { |a| a["group"].present? }

      legacy_names = attrs.filter_map { |a| a["group"].to_s.strip.presence }.uniq.sort
      next if legacy_names.empty?

      name_to_group = legacy_names.each_with_index.to_h do |name, i|
        slug = "g_legacy_#{i + 1}"
        [name, {
          "id"          => slug,
          "name"        => name,
          "description" => nil,
          "icon"        => EntityAttributeGroupOptions::DEFAULT_ICON,
          "color"       => EntityAttributeGroupOptions::DEFAULT_COLOR
        }]
      end

      new_attrs = attrs.map do |a|
        new_a = a.except("group")
        if (g = a["group"].to_s.strip.presence)
          new_a["group_id"] = name_to_group[g]["id"]
        end
        new_a
      end

      new_groups = groups + name_to_group.values

      entity.update_columns(
        property_schema:  new_attrs,
        attribute_groups: new_groups
      )
    end
  end

  def down
    # Reverse: drop group_ids; do not attempt to restore legacy group strings
    # (would require tracking original keys). Safe because backfill is idempotent.
    Entity.unscoped.find_each(batch_size: 200) do |entity|
      attrs = entity.read_attribute(:property_schema) || []
      next if attrs.none? { |a| a["group_id"].present? }
      new_attrs = attrs.map { |a| a.except("group_id") }
      entity.update_columns(property_schema: new_attrs, attribute_groups: [])
    end
  end
end
```

- [ ] **Step 3: Write the migration spec**

Create `spec/migrations/backfill_attribute_groups_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", Dir["db/migrate/*backfill_attribute_groups*.rb"].first.split("/").last)

RSpec.describe BackfillAttributeGroups do
  let(:migration) { described_class.new }

  it "converts legacy `group` strings into attribute_groups + group_id references" do
    entity = create(:entity)
    entity.update_columns(
      property_schema: [
        { "name" => "a", "name_slug" => "a", "group" => "Contact" },
        { "name" => "b", "name_slug" => "b", "group" => "Contact" },
        { "name" => "c", "name_slug" => "c", "group" => "Job"     },
        { "name" => "d", "name_slug" => "d" }
      ],
      attribute_groups: []
    )

    silence_stream($stdout) { migration.up }

    entity.reload
    expect(entity.attribute_groups_json.map { |g| g["name"] }).to contain_exactly("Contact", "Job")
    contact_id = entity.attribute_groups_json.find { |g| g["name"] == "Contact" }["id"]
    job_id     = entity.attribute_groups_json.find { |g| g["name"] == "Job" }["id"]
    expect(entity.property_schema_json.map { |a| a["group_id"] }).to eq([contact_id, contact_id, job_id, nil])
    expect(entity.property_schema_json).to all(satisfy { |a| !a.key?("group") })
  end

  it "is idempotent" do
    entity = create(:entity)
    entity.update_columns(
      property_schema:  [{ "name" => "a", "name_slug" => "a", "group" => "Contact" }],
      attribute_groups: []
    )

    silence_stream($stdout) { migration.up }
    snapshot_attrs  = entity.reload.property_schema_json
    snapshot_groups = entity.attribute_groups_json

    silence_stream($stdout) { migration.up }
    expect(entity.reload.property_schema_json).to eq(snapshot_attrs)
    expect(entity.attribute_groups_json).to eq(snapshot_groups)
  end

  it "leaves entities with no legacy group untouched" do
    entity = create(:entity)
    entity.update_columns(
      property_schema: [{ "name" => "a", "name_slug" => "a" }],
      attribute_groups: []
    )
    silence_stream($stdout) { migration.up }
    expect(entity.reload.attribute_groups_json).to eq([])
  end
end
```

If `silence_stream` is not in scope, add `require "active_support/testing/stream"` at the top and `include ActiveSupport::Testing::Stream` in the example group.

- [ ] **Step 4: Run the migration spec**

```bash
bundle exec rspec spec/migrations/backfill_attribute_groups_spec.rb
```

Expected: 3 examples, 0 failures.

- [ ] **Step 5: Run the migration against dev DB**

```bash
bin/rails db:migrate
```

Expected: clean run; existing entities (production today has near-zero usage) are unchanged or backfilled.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb spec/migrations
git commit -m "feat(entity-grouping): backfill legacy `group` strings into attribute_groups"
```

---

## Task 7: Add the grouping helper module

**Files:**
- Create: `app/helpers/entity_attribute_grouping_helper.rb`
- Test: `spec/helpers/entity_attribute_grouping_helper_spec.rb`

- [ ] **Step 1: Write the failing specs**

Create `spec/helpers/entity_attribute_grouping_helper_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityAttributeGroupingHelper, type: :helper do
  let(:group) { { "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo", "description" => "Primary contact" } }

  describe "#attribute_group_color_classes" do
    it "returns a bar class string for a known color" do
      classes = helper.attribute_group_color_classes("indigo", variant: :bar)
      expect(classes).to be_a(String)
      expect(classes).to include("indigo")
    end

    it "falls back to the default color when given an unknown token" do
      expect(helper.attribute_group_color_classes("neon", variant: :bar))
        .to eq(helper.attribute_group_color_classes(EntityAttributeGroupOptions::DEFAULT_COLOR, variant: :bar))
    end
  end

  describe "#attribute_group_icon" do
    it "renders an SVG element with the css class applied" do
      html = helper.attribute_group_icon("mail", css_class: "w-4 h-4")
      expect(html).to include("<svg")
      expect(html).to include("w-4 h-4")
    end

    it "falls back to the default icon when key is unknown" do
      unknown = helper.attribute_group_icon("not-an-icon", css_class: "w-4 h-4")
      default = helper.attribute_group_icon(EntityAttributeGroupOptions::DEFAULT_ICON, css_class: "w-4 h-4")
      expect(unknown).to eq(default)
    end
  end

  describe "#iterate_grouped_attributes" do
    let(:entity) do
      e = build_stubbed(:entity)
      allow(e).to receive(:grouped_property_schema).and_return([
        { group: group, attributes: [{ "name" => "email" }] },
        { group: nil,   attributes: [{ "name" => "notes" }] }
      ])
      e
    end

    it "yields each section in order" do
      sections = []
      helper.iterate_grouped_attributes(entity) { |g, a| sections << [g && g["name"], a.map { |x| x["name"] }] }
      expect(sections).to eq([["Contact", ["email"]], [nil, ["notes"]]])
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/helpers/entity_attribute_grouping_helper_spec.rb
```

Expected: NameError on `EntityAttributeGroupingHelper`.

- [ ] **Step 3: Implement the helper**

Create `app/helpers/entity_attribute_grouping_helper.rb`:

```ruby
# frozen_string_literal: true

module EntityAttributeGroupingHelper
  COLOR_CLASS_MAP = {
    "slate"   => { bar: "bg-slate-500",   text: "text-slate-700",   icon: "text-slate-500"   },
    "indigo"  => { bar: "bg-indigo-500",  text: "text-indigo-700",  icon: "text-indigo-500"  },
    "sky"     => { bar: "bg-sky-500",     text: "text-sky-700",     icon: "text-sky-500"     },
    "teal"    => { bar: "bg-teal-500",    text: "text-teal-700",    icon: "text-teal-500"    },
    "emerald" => { bar: "bg-emerald-500", text: "text-emerald-700", icon: "text-emerald-500" },
    "amber"   => { bar: "bg-amber-500",   text: "text-amber-700",   icon: "text-amber-500"   },
    "rose"    => { bar: "bg-rose-500",    text: "text-rose-700",    icon: "text-rose-500"    },
    "violet"  => { bar: "bg-violet-500",  text: "text-violet-700",  icon: "text-violet-500"  }
  }.freeze

  ICON_PATHS = {
    "folder"    => "M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V7z",
    "user"      => "M16 11a4 4 0 11-8 0 4 4 0 018 0zM4 21a8 8 0 0116 0",
    "briefcase" => "M6 7V6a2 2 0 012-2h8a2 2 0 012 2v1m2 0H4v12a2 2 0 002 2h12a2 2 0 002-2V7z",
    "map-pin"   => "M12 21s-7-7.05-7-12a7 7 0 1114 0c0 4.95-7 12-7 12zm0-9a3 3 0 100-6 3 3 0 000 6z",
    "mail"      => "M3 8l9 6 9-6M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
    "phone"     => "M3 5a2 2 0 012-2h2l2 5-3 2a11 11 0 006 6l2-3 5 2v2a2 2 0 01-2 2A17 17 0 013 5z",
    "calendar"  => "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
    "tag"       => "M7 7h.01M21 12l-9 9-9-9V3h9l9 9z",
    "settings"  => "M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.7 1.7 0 00.34 1.87l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.7 1.7 0 00-1.87-.34 1.7 1.7 0 00-1 1.55V21a2 2 0 11-4 0v-.09a1.7 1.7 0 00-1-1.55 1.7 1.7 0 00-1.87.34l-.06.06A2 2 0 113.27 16.93l.06-.06A1.7 1.7 0 003.67 15a1.7 1.7 0 00-1.55-1H2a2 2 0 110-4h.09A1.7 1.7 0 003.67 9a1.7 1.7 0 00-.34-1.87l-.06-.06A2 2 0 116.1 4.24l.06.06a1.7 1.7 0 001.87.34h.07a1.7 1.7 0 001-1.55V3a2 2 0 014 0v.09a1.7 1.7 0 001 1.55 1.7 1.7 0 001.87-.34l.06-.06a2 2 0 112.83 2.83l-.06.06a1.7 1.7 0 00-.34 1.87v.07a1.7 1.7 0 001.55 1H22a2 2 0 010 4h-.09a1.7 1.7 0 00-1.55 1z",
    "bell"      => "M15 17h5l-1.4-1.4A2 2 0 0118 14.2V11a6 6 0 10-12 0v3.2a2 2 0 01-.6 1.4L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9",
    "link"      => "M10 14a5 5 0 007.07 0l3-3a5 5 0 00-7.07-7.07l-1 1m-4 12a5 5 0 01-7.07 0 5 5 0 010-7.07l3-3a5 5 0 017.07 0l1 1",
    "file"      => "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z M14 2v6h6"
  }.freeze

  def attribute_group_color_classes(color, variant: :bar)
    token = COLOR_CLASS_MAP.key?(color.to_s) ? color.to_s : EntityAttributeGroupOptions::DEFAULT_COLOR
    COLOR_CLASS_MAP[token][variant] || COLOR_CLASS_MAP[token][:bar]
  end

  def attribute_group_icon(icon_key, css_class:)
    key  = ICON_PATHS.key?(icon_key.to_s) ? icon_key.to_s : EntityAttributeGroupOptions::DEFAULT_ICON
    path = ICON_PATHS[key]
    tag.svg(class: css_class, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 2) do
      tag.path(d: path, "stroke-linecap": "round", "stroke-linejoin": "round")
    end
  end

  def iterate_grouped_attributes(entity)
    entity.grouped_property_schema.each { |section| yield section[:group], section[:attributes] }
  end
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/helpers/entity_attribute_grouping_helper_spec.rb
```

Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/entity_attribute_grouping_helper.rb spec/helpers/entity_attribute_grouping_helper_spec.rb
git commit -m "feat(entity-grouping): add helper for color classes + inline icons"
```

---

## Task 8: Strong params accept `attribute_groups`

**Files:**
- Modify: `app/controllers/admin/maintenance/entities_controller.rb`
- Modify: `spec/requests/maintenance/entities_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Append to `spec/requests/maintenance/entities_spec.rb` inside the existing `describe`:

```ruby
describe "PATCH /admin/maintenance/entities/:id with attribute_groups" do
  let(:customer) { create(:customer) }
  let!(:owner_user) { create_authenticated_user(role: :admin, customer: customer) }
  let(:entity) { create(:entity, customer: customer) }

  it "persists groups and group_id references" do
    patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}", params: {
      entity: {
        name: entity.name,
        attribute_groups: [
          { id: "g_1", name: "Contact", description: "", icon: "mail",  color: "indigo" }
        ].to_json,
        property_schema: [
          { name: "email", name_slug: "email", html_type: "email", group_id: "g_1" }
        ].to_json
      }
    }

    expect(response).to redirect_to(admin_maintenance_entity_path(customer.id, entity))
    entity.reload
    expect(entity.attribute_groups_json.map { |g| g["id"] }).to eq(["g_1"])
    expect(entity.property_schema_json.first["group_id"]).to eq("g_1")
  end
end
```

(Adapt to the actual auth helper in `spec/requests/maintenance/entities_spec.rb`; if a helper like `sign_in_as_admin` already exists, reuse it.)

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/maintenance/entities_spec.rb -e "with attribute_groups"
```

Expected: failure (likely `attribute_groups_json` is empty because params were filtered).

- [ ] **Step 3: Permit `attribute_groups` in strong params**

In `app/controllers/admin/maintenance/entities_controller.rb`, update `entity_params`:

```ruby
def entity_params
  params.require(:entity).permit(
    :name, :name_slug, :element_type, :icon, :color, :description,
    :default_properties, :property_schema, :associations,
    :attribute_groups, :referenced_template
  )
end
```

(The existing `:property_schema` was already permitted as a scalar JSON string; mirror that for `:attribute_groups`.)

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/requests/maintenance/entities_spec.rb -e "with attribute_groups"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/entities_controller.rb spec/requests/maintenance/entities_spec.rb
git commit -m "feat(entity-grouping): permit attribute_groups in strong params"
```

---

## Task 9: Restructure the attributes table partial (server-side grouped rendering + hidden inputs)

**Files:**
- Modify: `app/views/admin/maintenance/entities/_attributes_table.html.erb`
- Create: `app/views/admin/maintenance/entities/_group_edit_modal.html.erb`
- Modify: `app/views/admin/maintenance/entities/_form.html.erb` to render the group edit modal once

This is a large structural edit; treat each step as a separate read/edit pass.

- [ ] **Step 1: Add the hidden `attribute_groups` JSON input + selection toolbar near the top of the partial**

At the top of `_attributes_table.html.erb` (after the existing `<% editable = ... %>` lines), prepend the toolbar + hidden input markup (only when `editable`):

```erb
<% if editable %>
  <input type="hidden" name="entity[attribute_groups]"
         data-entity-form-target="attributeGroupsInput"
         value="<%= (entity.attribute_groups_json || []).to_json %>">

  <div class="hidden mb-2 flex items-center gap-3 px-3 py-2 rounded-md bg-accent-subtle"
       data-entity-form-target="groupingToolbar">
    <span class="text-sm text-text-primary">
      <span data-entity-form-target="selectionCount">0</span> selected
    </span>
    <div class="relative" data-entity-form-target="moveToGroupMenu">
      <button type="button" class="btn btn-secondary btn-sm"
              data-action="click->entity-form#openMoveToGroup"
              data-entity-form-target="moveToGroupBtn">
        Move to group ▾
      </button>
    </div>
    <button type="button" class="btn btn-tertiary btn-sm"
            data-action="click->entity-form#clearAttributeSelection">
      Clear selection
    </button>
  </div>
<% end %>
```

Add `entity:` to the partial's `locals:` line:

```erb
<%# locals: (entity:, attributes:, editable: true, show_view_action: false) %>
```

Update existing call sites (`edit.html.erb`, `show.html.erb`, `new.html.erb`, `_form.html.erb` — find them with `grep -rn "_attributes_table" app/views`) to pass `entity:`.

- [ ] **Step 2: Replace the flat `each_with_index` body with a grouped iteration**

Inside `<tbody>`, replace the existing `<% attributes.each_with_index do |attr, index| %>...<% end %>` block with:

```erb
<%
  index_counter = 0
  iterate_grouped_attributes(entity) do |group, group_attrs|
    next if group.nil? && group_attrs.empty?
%>
  <% if group %>
    <tr data-attribute-group-header
        data-group-id="<%= group["id"] %>"
        class="bg-accent-subtle/50 cursor-pointer select-none">
      <td colspan="<%= editable ? 10 : 8 %>" class="px-0 py-2">
        <div class="flex items-center gap-2">
          <span class="inline-block w-1 h-6 rounded <%= attribute_group_color_classes(group["color"], variant: :bar) %>"></span>
          <% if editable %>
            <span class="cursor-grab text-text-muted px-1" data-action="dragstart->entity-form#dragStartGroup" draggable="true" title="Drag to reorder">⋮⋮</span>
          <% end %>
          <span class="<%= attribute_group_color_classes(group["color"], variant: :icon) %>">
            <%= attribute_group_icon(group["icon"], css_class: "w-4 h-4 inline") %>
          </span>
          <span class="font-semibold text-sm <%= attribute_group_color_classes(group["color"], variant: :text) %>">
            <%= group["name"] %>
          </span>
          <% if group["description"].present? %>
            <span class="text-xs text-text-muted truncate max-w-xs"><%= group["description"] %></span>
          <% end %>
          <span class="text-xs text-text-muted normal-case">
            <%= group_attrs.size %> <%= "attribute".pluralize(group_attrs.size) %>
            <% if group_attrs.empty? %>
              <span class="ml-1 px-1.5 py-0.5 text-xs rounded bg-text-muted/10">Empty</span>
            <% end %>
          </span>
          <% if editable %>
            <div class="ml-auto relative">
              <button type="button" class="action-icon"
                      data-action="click->entity-form#openGroupMenu"
                      data-group-id="<%= group["id"] %>"
                      title="Group actions">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <circle cx="12" cy="5" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="12" cy="19" r="1.5"/>
                </svg>
              </button>
            </div>
          <% end %>
        </div>
      </td>
    </tr>
  <% end %>

  <% group_attrs.each do |attr| %>
    <% index = index_counter %>
    <% index_counter += 1 %>
    <% validators = attr["validators"] || [] %>
    <% visibility = normalize_attribute_visibility(attr["visibility"]) %>
    <% display_label = attr["display_label"].presence || attr["name"] %>
    <tr <%= 'data-attribute-item=""' if editable || show_view_action %>
        class="attribute-item"
        draggable="<%= editable ? 'true' : 'false' %>"
        data-action="<%= 'dragstart->entity-form#dragStartRow dragover->entity-form#dragOverRow drop->entity-form#dropRow dragend->entity-form#dragEndRow' if editable %>"
        data-attr-name="<%= attr["name"] %>"
        data-attr-name-slug="<%= attr["name_slug"] %>"
        data-attr-display-label="<%= display_label %>"
        data-attr-html-type="<%= attr["html_type"] || "text" %>"
        data-attr-description="<%= attr["description"] %>"
        data-attr-validators="<%= Array(validators).to_json %>"
        data-attr-visibility="<%= visibility.to_json %>"
        data-attr-group-id="<%= attr["group_id"] %>"
        data-attr-config="<%= attr["config"]&.to_json.presence || "null" %>">

      <% if editable %>
        <td class="px-1 py-3 w-6">
          <span class="inline-block w-1 h-6 rounded <%= group ? attribute_group_color_classes(group["color"], variant: :bar) + " opacity-30" : "bg-transparent" %>"></span>
        </td>
        <td class="px-1 py-3 w-6">
          <input type="checkbox" data-action="change->entity-form#toggleAttributeSelection" class="rounded">
        </td>
        <td class="px-1 py-3 w-6 cursor-grab text-text-muted" title="Drag">⋮⋮</td>
      <% end %>

      <%# remaining existing <td> cells unchanged %>
      <td class="px-3 py-3 text-sm font-medium text-text-primary" data-field="name"><%= attr["name"] %></td>
      <td class="px-3 py-3" data-field="name_slug"><code class="text-code text-accent-text bg-accent-subtle"><%= attr["name_slug"] %></code></td>
      <td class="px-3 py-3 text-body-sm text-text-primary" data-field="display_label"><%= display_label %></td>
      <td class="px-3 py-3"><span class="badge badge-success" data-field="html_type"><%= HtmlTypeOptions.label_for(attr["html_type"]) %></span></td>
      <td class="px-3 py-3" data-field="validators"><%= render_validator_badges(validators) %></td>
      <td class="px-3 py-3" data-field="visibility"><%= render_attribute_visibility_badges(visibility) %></td>
      <td class="px-3 py-3 text-body-sm" data-field="description"><%= truncate_with_tooltip(attr["description"], length: 40) %></td>

      <% if editable || show_view_action %>
        <td class="px-3 py-3 text-right">
          <%# (unchanged buttons + hidden inputs from prior version) %>
          <%# ... keep the existing inline-flex action button block here ... %>
          <% if editable %>
            <input type="hidden" name="attributes[<%= index %>][name]" value="<%= attr["name"] %>" data-input="name">
            <input type="hidden" name="attributes[<%= index %>][name_slug]" value="<%= attr["name_slug"] %>" data-input="name_slug">
            <input type="hidden" name="attributes[<%= index %>][display_label]" value="<%= display_label %>" data-input="display_label">
            <input type="hidden" name="attributes[<%= index %>][html_type]" value="<%= attr["html_type"] || "text" %>" data-input="html_type">
            <input type="hidden" name="attributes[<%= index %>][description]" value="<%= attr["description"] %>" data-input="description">
            <input type="hidden" name="attributes[<%= index %>][validators]" value="<%= Array(validators).to_json %>" data-input="validators">
            <input type="hidden" name="attributes[<%= index %>][visibility]" value="<%= visibility.to_json %>" data-input="visibility">
            <input type="hidden" name="attributes[<%= index %>][group_id]" value="<%= attr["group_id"] %>" data-input="group_id">
            <input type="hidden" name="attributes[<%= index %>][config]" value="<%= attr["config"]&.to_json.presence || "null" %>" data-input="config">
          <% end %>
        </td>
      <% end %>
    </tr>
  <% end %>
<% end %>
```

(Carry forward the existing action button block exactly — don't re-derive its markup.)

- [ ] **Step 3: Update column widths in `<thead>`**

Adjust column widths to make room for the new color-bar / checkbox / grip cells when `editable`. Replace the existing `<thead>`:

```erb
<thead class="table-header">
  <tr>
    <% if editable %>
      <th scope="col" class="w-6"></th>
      <th scope="col" class="w-6"></th>
      <th scope="col" class="w-6"></th>
    <% end %>
    <th scope="col" class="px-3 py-3 text-left">Name</th>
    <th scope="col" class="px-3 py-3 text-left">Name Slug</th>
    <th scope="col" class="px-3 py-3 text-left">Display Label</th>
    <th scope="col" class="px-3 py-3 text-left">HTML Type</th>
    <th scope="col" class="px-3 py-3 text-left">Validators</th>
    <th scope="col" class="px-3 py-3 text-left">Visibility</th>
    <th scope="col" class="px-3 py-3 text-left">Description</th>
    <% if editable || show_view_action %>
      <th scope="col" class="px-3 py-3 text-right w-32">Actions</th>
    <% end %>
  </tr>
</thead>
```

- [ ] **Step 4: Render the group edit modal once per form**

Create `app/views/admin/maintenance/entities/_group_edit_modal.html.erb`:

```erb
<div data-entity-form-target="groupEditModal"
     class="hidden fixed inset-0 z-50 flex items-center justify-center bg-black/40"
     data-action="click->entity-form#closeGroupEditModalOnBackdrop">
  <div class="bg-surface rounded-lg shadow-xl w-full max-w-md p-5"
       data-action="click->entity-form#stopPropagation">
    <h3 class="text-base font-semibold mb-3">Edit Group</h3>

    <label class="block text-sm font-medium mb-1">Name</label>
    <input type="text" data-entity-form-target="groupEditName"
           class="w-full border rounded-md px-3 py-2 mb-3">

    <label class="block text-sm font-medium mb-1">Description</label>
    <input type="text" data-entity-form-target="groupEditDescription"
           class="w-full border rounded-md px-3 py-2 mb-3">

    <label class="block text-sm font-medium mb-1">Icon</label>
    <div class="grid grid-cols-4 gap-2 mb-3" data-entity-form-target="groupEditIcon">
      <% EntityAttributeGroupOptions::ICONS.each_key do |key| %>
        <button type="button" data-icon-key="<%= key %>"
                data-action="click->entity-form#selectGroupIcon"
                class="p-2 border rounded hover:bg-accent-subtle">
          <%= attribute_group_icon(key, css_class: "w-4 h-4 inline") %>
        </button>
      <% end %>
    </div>

    <label class="block text-sm font-medium mb-1">Color</label>
    <div class="flex flex-wrap gap-2 mb-3" data-entity-form-target="groupEditColor">
      <% EntityAttributeGroupOptions::COLORS.each do |color| %>
        <button type="button" data-color-key="<%= color %>"
                data-action="click->entity-form#selectGroupColor"
                class="w-6 h-6 rounded-full border <%= attribute_group_color_classes(color, variant: :bar) %>">
        </button>
      <% end %>
    </div>

    <div class="flex justify-end gap-2 mt-4">
      <button type="button" class="btn btn-tertiary" data-action="click->entity-form#closeGroupEditModal">Cancel</button>
      <button type="button" class="btn btn-primary" data-action="click->entity-form#saveGroupEdit">Save</button>
    </div>
  </div>
</div>
```

Render the modal once from `_form.html.erb` (find a suitable bottom-of-form location):

```erb
<%= render "group_edit_modal" %>
```

- [ ] **Step 5: Visual smoke test**

```bash
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Visit `/<cid>/admin/maintenance/entities/<id>/edit` and confirm:
- Existing attribute rows render without errors.
- A color bar / grip / checkbox cell appears on the far left when there are attributes.
- (Groups won't appear yet because no groups exist — that's expected.)

- [ ] **Step 6: Commit**

```bash
git add app/views/admin/maintenance/entities
git commit -m "feat(entity-grouping): grouped attributes table + group edit modal partial"
```

---

## Task 10: Update `schema_manager.js` to use `group_id`

**Files:**
- Modify: `app/javascript/controllers/entity_form/schema_manager.js`

- [ ] **Step 1: Replace `data-attr-group` with `data-attr-group-id`**

In `updateAttributeRow(...)`, change the destructured param `group` → `group_id`, and replace:

```js
const normalizedGroup = this.normalizeGroupName(group)
row.setAttribute("data-attr-group", normalizedGroup)
```

with:

```js
row.setAttribute("data-attr-group-id", group_id || "")
```

Replace `setInput("group", normalizedGroup)` with `setInput("group_id", group_id || "")`.

- [ ] **Step 2: Update `extractAttributeFromRow`**

Replace the `group` line with:

```js
const groupId = getValue("group_id")
```

Return `group_id: groupId || null` instead of `group`. Remove `normalizeGroupName` from the return.

- [ ] **Step 3: Replace `regroupAttributeRows` to drive off the groups JSON input**

Replace the entire `regroupAttributeRows` method:

```js
regroupAttributeRows() {
  if (!this.c.hasAttributesContainerTarget) return
  const table = this.c.attributesContainerTarget.querySelector("table")
  if (!table) return
  const tbody = table.querySelector("tbody")
  if (!tbody) return

  const groups = this.readAttributeGroups()
  const rows = Array.from(tbody.querySelectorAll("[data-attribute-item]"))

  // Remove existing group headers; we'll re-insert
  tbody.querySelectorAll("[data-attribute-group-header]").forEach(h => h.remove())

  const groupedRows = new Map()
  groups.forEach(g => groupedRows.set(g.id, []))
  groupedRows.set(null, [])

  rows.forEach(row => {
    const gid = row.getAttribute("data-attr-group-id") || null
    const key = groupedRows.has(gid) ? gid : null
    groupedRows.get(key).push(row)
  })

  groups.forEach(g => {
    const items = groupedRows.get(g.id) || []
    const headerHtml = this.c.templateBuilder.buildAttributeGroupHeaderHtml(g, items.length)
    tbody.insertAdjacentHTML("beforeend", headerHtml)
    items.forEach(row => tbody.appendChild(row))
  })

  const ungrouped = groupedRows.get(null) || []
  if (ungrouped.length > 0) {
    const headerHtml = this.c.templateBuilder.buildAttributeGroupHeaderHtml(null, ungrouped.length)
    tbody.insertAdjacentHTML("beforeend", headerHtml)
    ungrouped.forEach(row => tbody.appendChild(row))
  }
}

readAttributeGroups() {
  if (!this.c.hasAttributeGroupsInputTarget) return []
  try { const parsed = JSON.parse(this.c.attributeGroupsInputTarget.value || "[]"); return Array.isArray(parsed) ? parsed : [] }
  catch { return [] }
}

writeAttributeGroups(groups) {
  if (!this.c.hasAttributeGroupsInputTarget) return
  this.c.attributeGroupsInputTarget.value = JSON.stringify(groups)
}

syncAttributeGroups() {
  // No DOM-derived state for groups; writes are driven by GroupManager. This is
  // present so other callers can opt in symmetrically with syncPropertySchema.
}
```

- [ ] **Step 4: Add `moveRowTo` and `moveGroupTo`**

Append to the class:

```js
moveRowTo(rowEl, { groupId, beforeRow }) {
  if (!rowEl) return
  rowEl.setAttribute("data-attr-group-id", groupId || "")
  const groupIdInput = rowEl.querySelector('input[data-input="group_id"]')
  if (groupIdInput) groupIdInput.value = groupId || ""

  if (beforeRow) {
    beforeRow.parentElement.insertBefore(rowEl, beforeRow)
  } else {
    const tbody = this.c.attributesContainerTarget.querySelector("table tbody")
    if (tbody) tbody.appendChild(rowEl)
  }
  this.regroupAttributeRows()
  this.syncPropertySchema()
}

moveGroupTo(groupId, beforeGroupId) {
  const groups = this.readAttributeGroups()
  const moving = groups.find(g => g.id === groupId)
  if (!moving) return
  const remaining = groups.filter(g => g.id !== groupId)
  const insertAt = beforeGroupId
    ? remaining.findIndex(g => g.id === beforeGroupId)
    : remaining.length
  remaining.splice(insertAt < 0 ? remaining.length : insertAt, 0, moving)
  this.writeAttributeGroups(remaining)
  this.regroupAttributeRows()
}
```

- [ ] **Step 5: Drop legacy `normalizeGroupName` / `collectAttributeGroups`**

Remove the two unused helpers. (If grep shows callers still reference them, update those callers first.)

```bash
grep -n "normalizeGroupName\|collectAttributeGroups" app/javascript
```

Fix any remaining references before removing.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/entity_form/schema_manager.js
git commit -m "feat(entity-grouping): schema_manager reads/writes group_id"
```

---

## Task 11: Update `template_builder.js` for grouped rows + group headers

**Files:**
- Modify: `app/javascript/controllers/entity_form/template_builder.js`

- [ ] **Step 1: Replace `buildAttributeRowHtml` to use `group_id` + add color bar / checkbox / grip cells**

In `buildAttributeRowHtml({ ..., group_id, config })`:

- Destructure `group_id` instead of `group`.
- Replace the `<tr>` data attribute `data-attr-group="..."` with `data-attr-group-id="${escapeHtml(group_id || "")}"`.
- Prepend three new `<td>` cells inside the row (only when `editable` — but `template_builder` is always inside the editable form, so just emit them):

```html
<td class="px-1 py-3 w-6"><span class="inline-block w-1 h-6 rounded bg-transparent"></span></td>
<td class="px-1 py-3 w-6"><input type="checkbox" data-action="change->entity-form#toggleAttributeSelection" class="rounded"></td>
<td class="px-1 py-3 w-6 cursor-grab text-gray-400" title="Drag">⋮⋮</td>
```

Replace the existing hidden `name="...[group]"` input with:

```html
<input type="hidden" name="attributes[${index}][group_id]" value="${escapeHtml(group_id || "")}" data-input="group_id">
```

Set `<tr draggable="true" data-action="dragstart->entity-form#dragStartRow dragover->entity-form#dragOverRow drop->entity-form#dropRow dragend->entity-form#dragEndRow">`.

- [ ] **Step 2: Update `buildTableHtml` colspan / column structure**

Add the same three leading `<th class="w-6"></th>` slots in `<thead>` so column counts match.

- [ ] **Step 3: Replace `buildAttributeGroupHeaderHtml` to take a group object**

```js
buildAttributeGroupHeaderHtml(group, count) {
  const isUngrouped = !group
  const safeName = escapeHtml(isUngrouped ? "Ungrouped" : group.name)
  const colorBar = isUngrouped
    ? '<span class="inline-block w-1 h-6 rounded bg-gray-300"></span>'
    : `<span class="inline-block w-1 h-6 rounded ${this.c.colorBarClassFor(group.color)}"></span>`
  const groupId = isUngrouped ? "" : escapeHtml(group.id)
  const descHtml = !isUngrouped && group.description
    ? `<span class="text-xs text-gray-500 truncate max-w-xs">${escapeHtml(group.description)}</span>` : ""
  const emptyBadge = count === 0
    ? '<span class="ml-1 px-1.5 py-0.5 text-xs rounded bg-gray-200">Empty</span>' : ""

  return `
    <tr data-attribute-group-header
        data-group-id="${groupId}"
        draggable="${isUngrouped ? "false" : "true"}"
        ${isUngrouped ? "" : 'data-action="dragstart->entity-form#dragStartGroup"'}
        class="bg-gray-50/70 select-none">
      <td colspan="10" class="px-3 py-2">
        <div class="flex items-center gap-2 text-xs font-semibold tracking-wide text-gray-700">
          ${colorBar}
          <span>${safeName}</span>
          ${descHtml}
          <span class="text-gray-400 normal-case font-normal">${count} ${count === 1 ? "attribute" : "attributes"}</span>
          ${emptyBadge}
          ${isUngrouped ? "" : `
            <button type="button" class="ml-auto p-1 text-gray-400 hover:text-gray-600"
                    data-action="click->entity-form#openGroupMenu"
                    data-group-id="${groupId}" title="Group actions">⋯</button>`}
        </div>
      </td>
    </tr>
  `
}
```

Add a helper on the controller (called from above) to map color tokens to tailwind class strings — see Task 13.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/entity_form/template_builder.js
git commit -m "feat(entity-grouping): template_builder emits grouped row + header markup"
```

---

## Task 12: Drop dead group references from `attribute_manager.js` + `modal_manager.js`

**Files:**
- Modify: `app/javascript/controllers/entity_form/attribute_manager.js`
- Modify: `app/javascript/controllers/entity_form/modal_manager.js`

- [ ] **Step 1: Remove `canonicalizeGroup` and the `modalGroup` read**

In `attribute_manager.js`:

- In `collectModalData`, drop the `group` line and remove `group` from the return value. Replace with `group_id: this.c.modalManager.editingGroupId || null` (the manager carries a `editingGroupId` while editing a row; for the create flow this is null and a Move-to-group action assigns it afterwards).
- Remove the `canonicalizeGroup` method entirely.

- [ ] **Step 2: Grep modal_manager for any `modalGroup` references**

```bash
grep -n "modalGroup\|group" app/javascript/controllers/entity_form/modal_manager.js
```

If any reference exists, delete it. (If grep returns no matches, this step is a no-op.)

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form/attribute_manager.js app/javascript/controllers/entity_form/modal_manager.js
git commit -m "refactor(entity-grouping): drop dead modal group field references"
```

---

## Task 13: Add `group_manager.js` (selection, move-to-group, rename, delete, edit metadata)

**Files:**
- Create: `app/javascript/controllers/entity_form/group_manager.js`
- Modify: `app/javascript/controllers/entity_form/index.js`

- [ ] **Step 1: Write `group_manager.js`**

```js
import { BaseManager } from "controllers/entity_form/base_manager"

const COLOR_CLASSES = {
  slate: "bg-slate-500", indigo: "bg-indigo-500", sky: "bg-sky-500", teal: "bg-teal-500",
  emerald: "bg-emerald-500", amber: "bg-amber-500", rose: "bg-rose-500", violet: "bg-violet-500"
}

export class GroupManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.selected = new Set()
    this.editingGroupId = null
    this.iconChoice = "folder"
    this.colorChoice = "slate"
  }

  colorBarClassFor(color) { return COLOR_CLASSES[color] || COLOR_CLASSES.slate }

  toggleAttributeSelection(event) {
    const row = event.target.closest("[data-attribute-item]")
    if (!row) return
    const key = row.getAttribute("data-attr-name-slug") || row.getAttribute("data-attr-name") || ""
    if (event.target.checked) this.selected.add(key); else this.selected.delete(key)
    this.refreshSelectionUI()
  }

  clearAttributeSelection() {
    this.selected.clear()
    this.c.attributesContainerTarget.querySelectorAll('input[type="checkbox"]').forEach(cb => cb.checked = false)
    this.refreshSelectionUI()
  }

  refreshSelectionUI() {
    if (!this.c.hasGroupingToolbarTarget) return
    if (this.selected.size > 0) {
      this.c.groupingToolbarTarget.classList.remove("hidden")
      if (this.c.hasSelectionCountTarget) this.c.selectionCountTarget.textContent = this.selected.size.toString()
    } else {
      this.c.groupingToolbarTarget.classList.add("hidden")
    }
  }

  openMoveToGroup(event) {
    event.preventDefault()
    const groups = this.c.schemaManager.readAttributeGroups()
    const items = [
      ...groups.map(g => `<li><button type="button" class="block w-full text-left px-3 py-1.5 hover:bg-gray-100"
              data-action="click->entity-form#chooseGroup" data-group-id="${g.id}">
              <span class="inline-block w-2 h-2 rounded-full ${this.colorBarClassFor(g.color)} mr-2"></span>${this.escapeHtml(g.name)}
            </button></li>`).join(""),
      `<li><button type="button" class="block w-full text-left px-3 py-1.5 hover:bg-gray-100"
              data-action="click->entity-form#chooseGroup" data-group-id="">Ungrouped</button></li>`,
      `<li><button type="button" class="block w-full text-left px-3 py-1.5 text-accent hover:bg-gray-100"
              data-action="click->entity-form#startNewGroupInline">+ New group…</button></li>`
    ].join("")
    this.showFloater(event.currentTarget, `<ul class="py-1 min-w-[180px] bg-surface border rounded-md shadow-lg">${items}</ul>`)
  }

  chooseGroup(event) {
    const gid = event.currentTarget.getAttribute("data-group-id") || ""
    this.assignSelectedToGroup(gid || null)
    this.closeFloater()
  }

  startNewGroupInline(event) {
    event.preventDefault()
    const html = `
      <form class="p-2 bg-surface border rounded-md shadow-lg flex gap-2"
            data-action="submit->entity-form#commitNewGroupInline">
        <input type="text" data-entity-form-target="newGroupInlineName"
               placeholder="Group name" class="border rounded px-2 py-1 text-sm" autofocus required>
        <button type="submit" class="btn btn-primary btn-sm">Create</button>
        <button type="button" class="btn btn-tertiary btn-sm" data-action="click->entity-form#closeFloater">Cancel</button>
      </form>
    `
    this.showFloater(event.currentTarget, html)
  }

  commitNewGroupInline(event) {
    event.preventDefault()
    const input = event.currentTarget.querySelector('input[type="text"]')
    const name = (input?.value || "").trim()
    if (!name) return
    if (this.nameInUse(name)) { input.setCustomValidity("Group name must be unique"); input.reportValidity(); return }
    const newGroup = this.buildGroup({ name })
    const groups = this.c.schemaManager.readAttributeGroups()
    this.c.schemaManager.writeAttributeGroups([...groups, newGroup])
    this.assignSelectedToGroup(newGroup.id)
    this.closeFloater()
  }

  openGroupMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    const gid = event.currentTarget.getAttribute("data-group-id")
    const html = `
      <ul class="py-1 min-w-[160px] bg-surface border rounded-md shadow-lg">
        <li><button type="button" class="block w-full text-left px-3 py-1.5 hover:bg-gray-100"
                data-action="click->entity-form#editGroup" data-group-id="${gid}">Edit…</button></li>
        <li><button type="button" class="block w-full text-left px-3 py-1.5 text-red-600 hover:bg-red-50"
                data-action="click->entity-form#deleteGroup" data-group-id="${gid}">Delete</button></li>
      </ul>
    `
    this.showFloater(event.currentTarget, html)
  }

  editGroup(event) {
    const gid = event.currentTarget.getAttribute("data-group-id")
    const groups = this.c.schemaManager.readAttributeGroups()
    const group = groups.find(g => g.id === gid)
    if (!group) return
    this.editingGroupId = gid
    this.c.groupEditNameTarget.value = group.name
    this.c.groupEditDescriptionTarget.value = group.description || ""
    this.iconChoice = group.icon
    this.colorChoice = group.color
    this.c.groupEditModalTarget.classList.remove("hidden")
    this.closeFloater()
  }

  closeGroupEditModal() { this.c.groupEditModalTarget.classList.add("hidden"); this.editingGroupId = null }
  closeGroupEditModalOnBackdrop(event) { if (event.target === event.currentTarget) this.closeGroupEditModal() }

  selectGroupIcon(event) { this.iconChoice = event.currentTarget.getAttribute("data-icon-key") }
  selectGroupColor(event) { this.colorChoice = event.currentTarget.getAttribute("data-color-key") }

  saveGroupEdit() {
    const name = (this.c.groupEditNameTarget.value || "").trim()
    if (!name) return
    if (this.nameInUse(name, this.editingGroupId)) {
      this.c.groupEditNameTarget.setCustomValidity("Group name must be unique"); this.c.groupEditNameTarget.reportValidity(); return
    }
    const description = (this.c.groupEditDescriptionTarget.value || "").trim()
    const groups = this.c.schemaManager.readAttributeGroups().map(g =>
      g.id === this.editingGroupId
        ? { ...g, name, description, icon: this.iconChoice, color: this.colorChoice }
        : g
    )
    this.c.schemaManager.writeAttributeGroups(groups)
    this.c.schemaManager.regroupAttributeRows()
    this.closeGroupEditModal()
  }

  deleteGroup(event) {
    const gid = event.currentTarget.getAttribute("data-group-id")
    if (!gid) return
    const groups = this.c.schemaManager.readAttributeGroups().filter(g => g.id !== gid)
    this.c.schemaManager.writeAttributeGroups(groups)
    this.c.attributesContainerTarget.querySelectorAll(`[data-attr-group-id="${gid}"]`).forEach(row => {
      row.setAttribute("data-attr-group-id", "")
      const input = row.querySelector('input[data-input="group_id"]')
      if (input) input.value = ""
    })
    this.c.schemaManager.regroupAttributeRows()
    this.c.schemaManager.syncPropertySchema()
    this.closeFloater()
  }

  assignSelectedToGroup(groupId) {
    const slugs = this.selected
    this.c.attributesContainerTarget.querySelectorAll("[data-attribute-item]").forEach(row => {
      const slug = row.getAttribute("data-attr-name-slug") || row.getAttribute("data-attr-name") || ""
      if (!slugs.has(slug)) return
      row.setAttribute("data-attr-group-id", groupId || "")
      const input = row.querySelector('input[data-input="group_id"]')
      if (input) input.value = groupId || ""
    })
    this.clearAttributeSelection()
    this.c.schemaManager.regroupAttributeRows()
    this.c.schemaManager.syncPropertySchema()
  }

  buildGroup({ name }) {
    return {
      id: `g_${Math.random().toString(36).slice(2, 9)}`,
      name,
      description: "",
      icon: "folder",
      color: "slate"
    }
  }

  nameInUse(name, excludingId = null) {
    const target = name.trim().toLowerCase()
    return this.c.schemaManager.readAttributeGroups().some(g => g.id !== excludingId && g.name.trim().toLowerCase() === target)
  }

  // Floater (positioned dropdown) helpers
  showFloater(anchor, html) {
    this.closeFloater()
    const f = document.createElement("div")
    f.className = "absolute z-40"
    f.setAttribute("data-entity-form-floater", "")
    f.innerHTML = html
    const rect = anchor.getBoundingClientRect()
    f.style.top = `${window.scrollY + rect.bottom + 4}px`
    f.style.left = `${window.scrollX + rect.left}px`
    document.body.appendChild(f)
    this._closeFloaterHandler = (e) => { if (!f.contains(e.target)) this.closeFloater() }
    setTimeout(() => document.addEventListener("click", this._closeFloaterHandler), 0)
  }

  closeFloater() {
    document.querySelectorAll("[data-entity-form-floater]").forEach(el => el.remove())
    if (this._closeFloaterHandler) document.removeEventListener("click", this._closeFloaterHandler)
  }

  escapeHtml(s) { return String(s).replace(/[&<>"']/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c])) }
}
```

- [ ] **Step 2: Export from `index.js`**

```js
export { GroupManager } from "controllers/entity_form/group_manager"
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form
git commit -m "feat(entity-grouping): group_manager (selection, move-to-group, edit, delete)"
```

---

## Task 14: Add `dnd_manager.js` (HTML5 drag-and-drop)

**Files:**
- Create: `app/javascript/controllers/entity_form/dnd_manager.js`
- Modify: `app/javascript/controllers/entity_form/index.js`

- [ ] **Step 1: Write `dnd_manager.js`**

```js
import { BaseManager } from "controllers/entity_form/base_manager"

export class DndManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.dragKind = null
    this.dragRowEl = null
    this.dragGroupId = null
  }

  dragStartRow(event) {
    const row = event.currentTarget
    if (!row || !row.matches("[data-attribute-item]")) return
    this.dragKind = "row"
    this.dragRowEl = row
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", row.getAttribute("data-attr-name-slug") || "")
    row.classList.add("opacity-50")
  }

  dragOverRow(event) {
    if (this.dragKind !== "row") return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dropRow(event) {
    if (this.dragKind !== "row") return
    event.preventDefault()
    const targetRow = event.currentTarget
    const groupId   = targetRow.getAttribute("data-attr-group-id") || null
    this.c.schemaManager.moveRowTo(this.dragRowEl, { groupId, beforeRow: targetRow })
  }

  dragEndRow(event) {
    if (this.dragRowEl) this.dragRowEl.classList.remove("opacity-50")
    this.dragKind = null; this.dragRowEl = null
  }

  dragStartGroup(event) {
    const header = event.currentTarget.closest("[data-attribute-group-header]")
    if (!header) return
    this.dragKind = "group"
    this.dragGroupId = header.getAttribute("data-group-id")
    event.dataTransfer.effectAllowed = "move"
  }

  dragOverGroupHeader(event) {
    if (this.dragKind !== "group") return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dropGroup(event) {
    if (this.dragKind !== "group") return
    event.preventDefault()
    const header = event.currentTarget.closest("[data-attribute-group-header]")
    const targetGroupId = header.getAttribute("data-group-id") || null
    if (!targetGroupId || targetGroupId === this.dragGroupId) return
    this.c.schemaManager.moveGroupTo(this.dragGroupId, targetGroupId)
  }
}
```

- [ ] **Step 2: Export from `index.js`** and **wire the action attributes on group headers in `template_builder.js`** (`dragover->entity-form#dragOverGroupHeader drop->entity-form#dropGroup`).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/entity_form
git commit -m "feat(entity-grouping): dnd_manager (HTML5 drag-and-drop)"
```

---

## Task 15: Wire targets + action delegations on `entity_form_controller.js`

**Files:**
- Modify: `app/javascript/controllers/entity_form_controller.js`

- [ ] **Step 1: Add targets to the `static targets` array**

```js
"attributeGroupsInput",
"groupingToolbar",
"selectionCount",
"moveToGroupMenu",
"moveToGroupBtn",
"groupEditModal",
"groupEditName",
"groupEditDescription",
"groupEditIcon",
"groupEditColor",
"newGroupInlineName"
```

- [ ] **Step 2: Import + instantiate the new managers in `connect()`**

```js
import { GroupManager } from "controllers/entity_form/group_manager"
import { DndManager   } from "controllers/entity_form/dnd_manager"

// ... inside connect():
this.groupManager = new GroupManager(this)
this.dndManager   = new DndManager(this)
```

- [ ] **Step 3: Add delegation methods near the bottom**

```js
// Group selection / move-to-group / lifecycle
toggleAttributeSelection(event) { this.groupManager.toggleAttributeSelection(event) }
clearAttributeSelection(event)  { this.groupManager.clearAttributeSelection(event) }
openMoveToGroup(event)          { this.groupManager.openMoveToGroup(event) }
chooseGroup(event)              { this.groupManager.chooseGroup(event) }
startNewGroupInline(event)      { this.groupManager.startNewGroupInline(event) }
commitNewGroupInline(event)     { this.groupManager.commitNewGroupInline(event) }
openGroupMenu(event)            { this.groupManager.openGroupMenu(event) }
editGroup(event)                { this.groupManager.editGroup(event) }
deleteGroup(event)              { this.groupManager.deleteGroup(event) }
selectGroupIcon(event)          { this.groupManager.selectGroupIcon(event) }
selectGroupColor(event)         { this.groupManager.selectGroupColor(event) }
saveGroupEdit(event)            { this.groupManager.saveGroupEdit(event) }
closeGroupEditModal(event)      { this.groupManager.closeGroupEditModal(event) }
closeGroupEditModalOnBackdrop(event) { this.groupManager.closeGroupEditModalOnBackdrop(event) }
closeFloater(event)             { this.groupManager.closeFloater(event) }
stopPropagation(event)          { event.stopPropagation() }

// DnD
dragStartRow(event)        { this.dndManager.dragStartRow(event) }
dragOverRow(event)         { this.dndManager.dragOverRow(event) }
dropRow(event)             { this.dndManager.dropRow(event) }
dragEndRow(event)          { this.dndManager.dragEndRow(event) }
dragStartGroup(event)      { this.dndManager.dragStartGroup(event) }
dragOverGroupHeader(event) { this.dndManager.dragOverGroupHeader(event) }
dropGroup(event)           { this.dndManager.dropGroup(event) }
```

- [ ] **Step 4: Expose color-bar helper used by `template_builder`**

Add to the controller body:

```js
colorBarClassFor(color) { return this.groupManager?.colorBarClassFor(color) || "bg-slate-500" }
```

- [ ] **Step 5: Remove `toggleAttributeGroup`**

The collapsed/expanded group state is no longer used (the new design has no collapse affordance). Delete the method.

- [ ] **Step 6: Smoke test in browser**

```bash
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Open `/<cid>/admin/maintenance/entities/<id>/edit`. Verify:
- Select a row's checkbox → toolbar appears with count.
- Click "Move to group ▾" → dropdown lists existing groups (none yet) + "Ungrouped" + "+ New group…".
- Create a new group → row moves into it, header appears with default color/icon.
- Open kebab → Edit → change color/icon/description → Save → header updates.
- Delete group → rows become Ungrouped.
- Drag a row across groups → assignment changes; drag group header onto another group header → reorder.
- Submit → reload → state persists.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/entity_form_controller.js
git commit -m "feat(entity-grouping): wire group + DnD targets/actions on entity_form_controller"
```

---

## Task 16: Update read-only consumers (entity show, surface builder, field organizer, page populator)

**Files:**
- Modify: `app/views/admin/maintenance/entities/show.html.erb` (pass `entity:` to the partial)
- Modify: `app/services/entity_field_organizer.rb`
- Modify: `app/services/page_field_populator.rb`
- Modify: `app/services/member/entity_surface_builder.rb`
- Modify: `spec/services/member/entity_surface_builder_spec.rb`

- [ ] **Step 1: Pass `entity:` to `_attributes_table` from the show page**

In `show.html.erb`, find the existing `render "attributes_table"` and add `entity: @entity` to the locals.

- [ ] **Step 2: Add `EntityFieldOrganizer#grouped_organized_fields`**

```ruby
def grouped_organized_fields
  return [] unless @entity
  @entity.grouped_property_schema.map do |section|
    { group: section[:group], fields: section[:attributes] }
  end
end
```

Expose at the class level:

```ruby
def self.grouped(entity)
  new(entity).grouped_organized_fields
end
```

- [ ] **Step 3: Carry group metadata into page-builder fields**

In `PageFieldPopulator#build_field`, after the `field = { ... }` hash, append:

```ruby
field["group_id"] = prop["group_id"] if prop["group_id"].present?
```

This is enough for the field picker to filter/group later; rendering changes downstream are out of scope.

- [ ] **Step 4: Add a `groups` key to the member surface output**

In `Member::EntitySurfaceBuilder.call`, replace the `data_fields` line with:

```ruby
grouped     = entity.grouped_property_schema
data_fields = grouped.flat_map { |s| s[:attributes] }.reject { |f| f["type"] == "Calculated" }
```

Add a new keyword to the returned `Member::Surface.new(...)` block:

```ruby
groups: grouped.map { |s| { group: s[:group], attributes: s[:attributes].reject { |f| f["type"] == "Calculated" } } }
```

If `Member::Surface` doesn't accept `groups`, add it as a `attr_accessor` on the surface struct. (Check the struct first; if accepted via kwargs, just pass through. Otherwise add the accessor in `app/services/member/surface.rb`.)

- [ ] **Step 5: Spec round-trip for the member surface**

Append to `spec/services/member/entity_surface_builder_spec.rb`:

```ruby
describe "grouped output" do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer,
      attribute_groups: [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }],
      property_schema: [{ "name" => "email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_1" }]
    )
  end

  it "exposes grouped attribute sections via #groups" do
    surface = described_class.call(entity: entity)
    expect(surface.respond_to?(:groups) ? surface.groups : surface.instance_variable_get(:@groups)).to be_present
  end
end
```

- [ ] **Step 6: Run the affected specs**

```bash
bundle exec rspec spec/services/member/entity_surface_builder_spec.rb spec/services/entity_field_organizer_spec.rb
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/views app/services spec/services
git commit -m "feat(entity-grouping): propagate groups to show page + surface + field organizer + page populator"
```

---

## Task 17: Add system spec for the end-to-end grouping flow

**Files:**
- Create: `spec/system/entities_attribute_grouping_spec.rb`

- [ ] **Step 1: Write the system spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entity Attribute Inline Grouping", type: :system, js: true do
  let(:customer) { create(:customer) }
  let(:admin)    { create_authenticated_user(role: :admin, customer: customer) }
  let!(:entity)  do
    create(:entity, customer: customer,
      attribute_groups: [],
      property_schema: [
        { "name" => "Email",   "name_slug" => "email",   "html_type" => "email", "display_label" => "Email"   },
        { "name" => "Phone",   "name_slug" => "phone",   "html_type" => "tel",   "display_label" => "Phone"   },
        { "name" => "Address", "name_slug" => "address", "html_type" => "text",  "display_label" => "Address" }
      ]
    )
  end

  before { sign_in_as(admin) }

  it "lets the admin create a group via inline 'New group', assigns rows, persists across reload" do
    visit edit_admin_maintenance_entity_path(customer.id, entity)

    find("tr[data-attr-name-slug='email'] input[type=checkbox]").set(true)
    find("tr[data-attr-name-slug='phone'] input[type=checkbox]").set(true)

    expect(page).to have_text("2 selected")
    click_button "Move to group ▾"
    click_button "+ New group…"

    fill_in placeholder: "Group name", with: "Contact"
    click_button "Create"

    expect(page).to have_css("[data-attribute-group-header] span", text: "Contact")
    expect(find("tr[data-attr-name-slug='email']")["data-attr-group-id"]).not_to eq("")

    click_button "Update Entity"
    expect(page).to have_text("successfully updated")
    visit edit_admin_maintenance_entity_path(customer.id, entity)
    expect(page).to have_css("[data-attribute-group-header] span", text: "Contact")
  end
end
```

(Adapt `sign_in_as` / `create_authenticated_user` / button text to the existing test helpers.)

- [ ] **Step 2: Run the system spec**

```bash
bundle exec rspec spec/system/entities_attribute_grouping_spec.rb
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/entities_attribute_grouping_spec.rb
git commit -m "test(entity-grouping): system spec for inline grouping flow"
```

---

## Task 18: Final full-suite check + merge

**Files:** none — verification only.

- [ ] **Step 1: Run the full spec suite**

```bash
bundle exec rspec
```

Expected: green. If a previously-passing spec asserted on the old `data-attr-group` attribute or the old hidden `group` input, rewrite it per the stale-test policy in `feedback_stale_test_policy.md` (update the spec, do not revert production code).

- [ ] **Step 2: Browser smoke pass**

Visit edit + show + the page-builder field picker for an entity with groups. Confirm:
- Edit page renders groups, color bars, descriptions; DnD across rows + groups works; deleting a group moves its rows to Ungrouped.
- Show page renders groups read-only.

- [ ] **Step 3: Merge the worktree branch back into master**

```bash
cd ../..   # back to /home/ec2-user/anysys
git fetch
git merge --no-ff worktree-entity-attribute-inline-grouping
git worktree remove .worktrees/entity-attribute-inline-grouping
```

(Per user preference: no PR; direct merge to master.)

- [ ] **Step 4: Confirm the merge commit**

```bash
git log -5 --oneline
```

Expected: a merge commit at the tip with the grouping feature commits underneath.
