# Versioning Dedup Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate both kinds of versioning duplication for `Entity`, `Flowchart`, and `Page` — the live↔current-version copy (A) and the full-snapshot-per-version redundancy (B) — by making each parent a *head pointer* whose definition body lives only in immutable, content-addressed version rows.

**Architecture:** The parent keeps its queryable identity columns (`name`, `type`, `status`, …) and a `current_version_id` head pointer; its definition body becomes **virtual `attribute`s** loaded from `current_version.content` on `after_find`. Version rows lose their payload column and gain a `content_id` FK into a per-resource content-addressed table (`*_contents`), where each unique payload is stored once keyed by SHA-256 of its canonical JSON. Shared behavior lives in three concerns: `ContentAddressable` (content models), `VersionRecord` (version rows), `Versionable` (parents).

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, SQLite (dev/test). No custom CSS/JS in scope (backend + data-model refactor only).

---

## Why virtual attributes (read this before starting)

Dropping the body columns would normally break three things that read them as *columns*:
1. `JsonSerializable#json_attribute` (`property_schema_json` calls `send(:property_schema)`).
2. `BridgeEntityManagement` dirty-tracking (`will_save_change_to_associations?`, `name_changed?`).
3. The controllers' change detection (`saved_change_to_configuration?`, `saved_changes.keys.intersect?(VERSIONED_COLUMNS)`).

Declaring each dropped body field as a Rails **virtual attribute** (`attribute :property_schema, :text`) keeps all three working, because `ActiveModel::Dirty` tracks *declared attributes*, not just DB columns. The value is populated from `current_version.content.payload` in `after_find`, and packed back into a new content row on commit. On disk the definition is stored exactly once (the content row); the virtual attribute is only a per-request in-memory mirror — so duplication (A) is gone.

**Correctness safety net:** `commit_version!` compares the new payload's content hash to the current head's and *no-ops when equal*. So even if dirty-tracking ever mis-fires, a redundant commit is silently skipped — never a duplicate row.

## File map

**New files**
- `db/migrate/20260704120000_add_content_addressed_versioning.rb` — additive schema (Task 1)
- `app/models/concerns/content_addressable.rb` — canonical-JSON hashing, find-or-create, orphan GC (Task 2)
- `app/models/entity_definition_content.rb` (Task 3)
- `app/models/flowchart_configuration_content.rb` (Task 3)
- `app/models/page_configuration_content.rb` (Task 3)
- `db/migrate/20260704130000_migrate_versions_to_content_store.rb` — data backfill + destructive column drops (Task 13)
- Spec files listed per task.

**Modified files**
- `app/models/concerns/version_record.rb` — content-backed payload (Task 4)
- `app/models/entity_version.rb`, `flowchart_version.rb`, `page_version.rb` — `acts_as_version content_class:` (Task 5)
- `app/models/concerns/versionable.rb` — head pointer, `commit_version!`, restore/set-current, prune+GC (Task 6)
- `app/models/entity.rb` + `app/models/concerns/bridge_entity_management.rb` — virtual attrs + head load (Task 7)
- `app/models/flowchart.rb`, `app/models/page.rb` — virtual `configuration` + head load (Task 8, 9)
- `app/controllers/admin/maintenance/base_versions_controller.rb` (Task 10)
- `app/controllers/admin/maintenance/entities_controller.rb` (Task 11)
- `app/controllers/admin/maintenance/flowcharts_controller.rb`, `pages_controller.rb` (Task 12)

## Task ordering rationale

Additive migration first (Task 1) so every subsequent model spec runs against the new tables while the *old* payload columns still exist. The destructive migration (Task 13) runs last, after all models/controllers read through content, and reads the old columns one final time to backfill before dropping them.

---

### Task 1: Additive schema migration

**Files:**
- Create: `db/migrate/20260704120000_add_content_addressed_versioning.rb`

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

# Additive-only. Creates the three content-addressed tables, adds a nullable
# content_id to each version table, and renames default_version_id ->
# current_version_id on each parent. No data is moved here — the destructive
# backfill (20260704130000) runs after the models read through content.
class AddContentAddressedVersioning < ActiveRecord::Migration[8.1]
  CONTENT_TABLES = {
    entity_definition_contents:      :entity_versions,
    flowchart_configuration_contents: :flowchart_versions,
    page_configuration_contents:      :page_versions
  }.freeze

  def up
    CONTENT_TABLES.each_key do |table|
      create_table table do |t|
        t.integer  :customer_id                       # nullable: NULL for shared resources
        t.string   :content_hash, null: false         # SHA-256 hex of canonical JSON
        t.text     :payload,      null: false
        t.datetime :created_at,   null: false
      end
      add_index table, %i[customer_id content_hash], unique: true,
                name: "index_#{table}_on_customer_and_hash"
      add_index table, :customer_id
    end

    CONTENT_TABLES.each_value do |versions_table|
      add_column versions_table, :content_id, :integer   # nullable until backfill
      add_index  versions_table, :content_id
    end

    rename_column :entities,   :default_version_id, :current_version_id
    rename_column :flowcharts, :default_version_id, :current_version_id
    rename_column :pages,      :default_version_id, :current_version_id
  end

  def down
    rename_column :pages,      :current_version_id, :default_version_id
    rename_column :flowcharts, :current_version_id, :default_version_id
    rename_column :entities,   :current_version_id, :default_version_id
    CONTENT_TABLES.each_value { |vt| remove_column vt, :content_id }
    CONTENT_TABLES.each_key   { |t|  drop_table t }
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate` then `RAILS_ENV=test bin/rails db:migrate`
Expected: three `*_contents` tables created; `content_id` present on the three version tables; `current_version_id` on the three parents. No errors.

- [ ] **Step 3: Verify schema**

Run: `grep -n "current_version_id\|_contents\|content_id" db/schema.rb | head -30`
Expected: index/column lines for `current_version_id` on entities/flowcharts/pages and the new content tables.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260704120000_add_content_addressed_versioning.rb db/schema.rb
git commit -m "feat(versioning): additive schema for content-addressed version storage"
```

---

### Task 2: `ContentAddressable` concern

**Files:**
- Create: `app/models/concerns/content_addressable.rb`
- Test: `spec/models/concerns/content_addressable_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/concerns/content_addressable_spec.rb
require "rails_helper"

RSpec.describe ContentAddressable do
  # EntityDefinitionContent includes the concern; use it as the concrete subject.
  subject(:model) { EntityDefinitionContent }

  describe ".canonical_json" do
    it "is independent of key order and nesting order" do
      a = { "b" => 1, "a" => { "y" => 2, "x" => 3 } }
      b = { "a" => { "x" => 3, "y" => 2 }, "b" => 1 }
      expect(model.canonical_json(a)).to eq(model.canonical_json(b))
    end
  end

  describe ".store!" do
    it "stores a payload once and reuses it for an equal payload" do
      payload = { "fields" => [{ "k" => "v" }] }
      c1 = model.store!(customer_id: 7, payload: payload)
      c2 = model.store!(customer_id: 7, payload: payload.deep_dup)
      expect(c2.id).to eq(c1.id)
      expect(model.where(customer_id: 7).count).to eq(1)
    end

    it "creates distinct rows for different payloads" do
      c1 = model.store!(customer_id: 7, payload: { "a" => 1 })
      c2 = model.store!(customer_id: 7, payload: { "a" => 2 })
      expect(c2.id).not_to eq(c1.id)
    end

    it "scopes dedup per tenant (no cross-tenant sharing)" do
      p = { "a" => 1 }
      c1 = model.store!(customer_id: 7, payload: p)
      c2 = model.store!(customer_id: 9, payload: p.deep_dup)
      expect(c2.id).not_to eq(c1.id)
    end

    it "handles shared resources with a nil customer_id" do
      c1 = model.store!(customer_id: nil, payload: { "a" => 1 })
      c2 = model.store!(customer_id: nil, payload: { "a" => 1 })
      expect(c2.id).to eq(c1.id)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/concerns/content_addressable_spec.rb`
Expected: FAIL — `uninitialized constant ContentAddressable` / `EntityDefinitionContent`.

- [ ] **Step 3: Write the concern**

```ruby
# app/models/concerns/content_addressable.rb
# frozen_string_literal: true

# Immutable, content-addressed payload store shared by the three *_contents
# models. A payload is stored once, keyed by (customer_id, SHA-256 of its
# canonical JSON). Rows are never updated — only created (find-or-create) and
# garbage-collected when no version references them.
module ContentAddressable
  extend ActiveSupport::Concern

  class_methods do
    # Deterministic serialization: keys sorted recursively so that two equal
    # definitions hash identically regardless of key order.
    def canonical_json(value)
      JSON.generate(deep_sort(value))
    end

    def digest(payload)
      Digest::SHA256.hexdigest(canonical_json(payload))
    end

    # Find-or-create the content row for this payload. Idempotent; retries the
    # narrow unique-index race (matches Versionable's RecordNotUnique handling).
    def store!(customer_id:, payload:)
      hash = digest(payload)
      attempts = 0
      begin
        attempts += 1
        where(customer_id: customer_id, content_hash: hash).first ||
          create!(customer_id: customer_id, content_hash: hash,
                  payload: canonical_json(payload))
      rescue ActiveRecord::RecordNotUnique
        retry if attempts < 3
        where(customer_id: customer_id, content_hash: hash).first!
      end
    end

    # Delete content rows for this tenant no longer referenced by any version.
    # `version_relation_name` is the has_many declared by the including model.
    def sweep_orphans!(customer_id:)
      referenced = reflect_on_association(version_association)
                     .klass.where(customer_id: customer_id).select(:content_id)
      where(customer_id: customer_id).where.not(id: referenced).delete_all
    end

    private

    def deep_sort(value)
      case value
      when Hash  then value.keys.sort.to_h { |k| [k, deep_sort(value[k])] }
      when Array then value.map { |v| deep_sort(v) }
      else value
      end
    end
  end
end
```

> Note: `version_association` and `version_content_class` wiring is added in Task 3 when the concrete models declare `has_many`. `sweep_orphans!` relies on the including model exposing a `version_association` class method — Task 3 defines it.

- [ ] **Step 4: Run test to verify it passes** (after Task 3 defines `EntityDefinitionContent`)

The concern spec depends on `EntityDefinitionContent`; run it at the end of Task 3.
Run: `bundle exec rspec spec/models/concerns/content_addressable_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit** (combined with Task 3)

---

### Task 3: Three content models

**Files:**
- Create: `app/models/entity_definition_content.rb`
- Create: `app/models/flowchart_configuration_content.rb`
- Create: `app/models/page_configuration_content.rb`
- Test: `spec/models/entity_definition_content_spec.rb`

- [ ] **Step 1: Write the models**

```ruby
# app/models/entity_definition_content.rb
# frozen_string_literal: true

class EntityDefinitionContent < ApplicationRecord
  include ContentAddressable

  has_many :entity_versions, foreign_key: :content_id, dependent: :restrict_with_exception,
                             inverse_of: :content

  def self.version_association = :entity_versions
end
```

```ruby
# app/models/flowchart_configuration_content.rb
# frozen_string_literal: true

class FlowchartConfigurationContent < ApplicationRecord
  include ContentAddressable

  has_many :flowchart_versions, foreign_key: :content_id, dependent: :restrict_with_exception,
                                inverse_of: :content

  def self.version_association = :flowchart_versions
end
```

```ruby
# app/models/page_configuration_content.rb
# frozen_string_literal: true

class PageConfigurationContent < ApplicationRecord
  include ContentAddressable

  has_many :page_versions, foreign_key: :content_id, dependent: :restrict_with_exception,
                           inverse_of: :content

  def self.version_association = :page_versions
end
```

- [ ] **Step 2: Write the orphan-sweep test**

```ruby
# spec/models/entity_definition_content_spec.rb
require "rails_helper"

RSpec.describe EntityDefinitionContent do
  it "sweeps rows no longer referenced by a version" do
    referenced   = described_class.store!(customer_id: 1, payload: { "a" => 1 })
    unreferenced = described_class.store!(customer_id: 1, payload: { "a" => 2 })
    entity = Entity.create!(customer_id: 1, name: "E1", type: :customer_specific)
    EntityVersion.create!(entity: entity, customer_id: 1, version_number: 1, content: referenced)

    described_class.sweep_orphans!(customer_id: 1)

    expect(described_class.exists?(referenced.id)).to be(true)
    expect(described_class.exists?(unreferenced.id)).to be(false)
  end
end
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/concerns/content_addressable_spec.rb spec/models/entity_definition_content_spec.rb`
Expected: PASS (EntityVersion already `belongs_to :content` after Task 4 — if running this task first, add `belongs_to :content, class_name: "EntityDefinitionContent", optional: true` to `EntityVersion` temporarily; Task 5 formalizes it).

- [ ] **Step 4: Commit**

```bash
git add app/models/concerns/content_addressable.rb app/models/*_content.rb \
        spec/models/concerns/content_addressable_spec.rb spec/models/entity_definition_content_spec.rb
git commit -m "feat(versioning): content-addressable store + three content models"
```

---

### Task 4: `VersionRecord` — content-backed payload

**Files:**
- Modify: `app/models/concerns/version_record.rb`
- Test: `spec/models/concerns/version_record_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/concerns/version_record_spec.rb
require "rails_helper"

RSpec.describe VersionRecord do
  it "reads its payload through the referenced content row" do
    entity  = Entity.create!(customer_id: 1, name: "E", type: :customer_specific)
    content = EntityDefinitionContent.store!(customer_id: 1, payload: { "name" => "E" })
    v = EntityVersion.create!(entity: entity, customer_id: 1, version_number: 1, content: content)
    expect(v.payload).to eq(content.payload)
  end

  it "requires a content association" do
    entity = Entity.create!(customer_id: 1, name: "E", type: :customer_specific)
    v = EntityVersion.new(entity: entity, customer_id: 1, version_number: 1)
    expect(v).not_to be_valid
    expect(v.errors[:content]).to be_present
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/concerns/version_record_spec.rb`
Expected: FAIL — `payload` still points at a dropped column / no `content` association.

- [ ] **Step 3: Rewrite the concern**

```ruby
# app/models/concerns/version_record.rb
# frozen_string_literal: true

# Shared behavior for version-snapshot rows (FlowchartVersion, EntityVersion,
# PageVersion). Each version belongs to a parent and to an immutable, content-
# addressed `content` row that holds the JSON payload. `version_number` is
# unique per parent; `based_on_version_id` records lineage.
module VersionRecord
  extend ActiveSupport::Concern

  class_methods do
    # parent:        association name to the owning record (e.g. :flowchart)
    # content_class: class name string of the content-addressed store
    def acts_as_version(parent:, content_class:)
      self.version_parent_name  = parent
      self.version_content_class = content_class

      belongs_to parent
      belongs_to :content, class_name: content_class, inverse_of: version_inverse
      belongs_to :based_on_version, class_name: name, optional: true

      validates :content, presence: true
      validates :version_number, presence: true,
                                 uniqueness: { scope: :"#{parent}_id" }

      scope :ordered, -> { order(created_at: :desc, version_number: :desc) }
      scope :recent,  -> { ordered.limit(50) }
    end

    # has_many name the content model declares back to us, e.g. :entity_versions.
    def version_inverse
      "#{name.underscore.pluralize}".to_sym
    end
  end

  included do
    class_attribute :version_parent_name, :version_content_class, instance_writer: false
  end

  # Uniform accessor for the snapshot payload (JSON string), read through the
  # content row so the controller JSON contract is unchanged.
  def payload
    content&.payload
  end

  def based_on_version_number
    based_on_version&.version_number
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/concerns/version_record_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/concerns/version_record.rb spec/models/concerns/version_record_spec.rb
git commit -m "refactor(versioning): VersionRecord payload read through content row"
```

---

### Task 5: Version models declare `content_class`

**Files:**
- Modify: `app/models/entity_version.rb`, `app/models/flowchart_version.rb`, `app/models/page_version.rb`
- Test: covered by Task 4 + Task 6 specs.

- [ ] **Step 1: Rewrite `entity_version.rb`**

```ruby
# app/models/entity_version.rb
# frozen_string_literal: true

class EntityVersion < ApplicationRecord
  include VersionRecord

  acts_as_version parent: :entity, content_class: "EntityDefinitionContent"
end
```

Removed: `include JsonSerializable`, `VERSION_PAYLOAD_KEY`, `VERSIONED_COLUMNS`, `json_attribute :snapshot`. (Change detection moves to `commit_version!`'s hash no-op; the `snapshot` column is dropped in Task 13.)

- [ ] **Step 2: Rewrite `flowchart_version.rb`**

```ruby
# app/models/flowchart_version.rb
# frozen_string_literal: true

class FlowchartVersion < ApplicationRecord
  include VersionRecord

  acts_as_version parent: :flowchart, content_class: "FlowchartConfigurationContent"
end
```

- [ ] **Step 3: Rewrite `page_version.rb`**

```ruby
# app/models/page_version.rb
# frozen_string_literal: true

class PageVersion < ApplicationRecord
  include VersionRecord

  acts_as_version parent: :page, content_class: "PageConfigurationContent"
end
```

- [ ] **Step 4: Grep for stale references**

Run: `grep -rn "VERSION_PAYLOAD_KEY\|VERSIONED_COLUMNS" app lib`
Expected: only remaining hits are in `Versionable` (fixed in Task 6) and `entities_controller` (fixed in Task 11). No other production references.

- [ ] **Step 5: Commit**

```bash
git add app/models/entity_version.rb app/models/flowchart_version.rb app/models/page_version.rb
git commit -m "refactor(versioning): version models reference content-addressed store"
```

---

### Task 6: `Versionable` — head pointer, commit, restore, GC

**Files:**
- Modify: `app/models/concerns/versionable.rb`
- Test: `spec/models/concerns/versionable_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/models/concerns/versionable_spec.rb
require "rails_helper"

RSpec.describe Versionable do
  let(:entity) { Entity.create!(customer_id: 1, name: "E", type: :customer_specific) }

  def set_schema(entity, schema)
    entity.property_schema_json = schema
  end

  describe "#commit_version!" do
    it "creates a version, advances the head, and dedups equal payloads" do
      set_schema(entity, [{ "key" => "a" }])
      v1 = entity.commit_version!(description: "one")
      expect(entity.reload.current_version_id).to eq(v1.id)

      # committing the identical definition is a no-op
      expect { entity.commit_version! }.not_to change { entity.entity_versions.count }

      set_schema(entity, [{ "key" => "b" }])
      v2 = entity.commit_version!(description: "two")
      expect(v2.version_number).to eq(v1.version_number + 1)
      expect(entity.reload.current_version_id).to eq(v2.id)
      expect(EntityDefinitionContent.where(customer_id: 1).count).to eq(2)
    end
  end

  describe "#restore_as_new!" do
    it "creates a new head version referencing the chosen version's existing content (no new content row)" do
      set_schema(entity, [{ "key" => "a" }]); v1 = entity.commit_version!
      set_schema(entity, [{ "key" => "b" }]); entity.commit_version!
      content_count = EntityDefinitionContent.where(customer_id: 1).count

      entity.restore_as_new!(v1)

      expect(EntityDefinitionContent.where(customer_id: 1).count).to eq(content_count) # reused
      expect(entity.reload.property_schema_json).to eq([{ "key" => "a" }])
      expect(entity.entity_versions.ordered.first.based_on_version_id).to eq(v1.id)
    end
  end

  describe "GC on prune" do
    it "deletes content orphaned once its last version is pruned" do
      stub_const("Versionable::MAX_VERSIONS", 2)
      set_schema(entity, [{ "k" => 1 }]); entity.commit_version!
      set_schema(entity, [{ "k" => 2 }]); entity.commit_version!
      set_schema(entity, [{ "k" => 3 }]); entity.commit_version! # prunes v1
      payloads = EntityDefinitionContent.where(customer_id: 1).pluck(:payload)
      expect(payloads.none? { |p| p.include?("\"k\":1") }).to be(true)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/concerns/versionable_spec.rb`
Expected: FAIL — `commit_version!` undefined, still `default_version_id`.

- [ ] **Step 3: Rewrite the concern**

```ruby
# app/models/concerns/versionable.rb
# frozen_string_literal: true

# Shared versioning for parents (Flowchart, Entity, Page). Each parent is a
# HEAD: it points at `current_version_id`. Its definition body lives only in
# version rows, whose payloads are stored in a content-addressed table so equal
# payloads across the history share one row.
#
# `current_snapshot` returns the JSON string to store (single-column resources
# read the column directly; Entity serializes its many fields). `content_class`
# names the content-addressed store.
module Versionable
  extend ActiveSupport::Concern

  MAX_VERSIONS = 50

  class_methods do
    def acts_as_versionable(reflection:, version_class:, content_class:,
                            snapshot: nil, snapshot_reader: nil)
      self.versionable_options = {
        reflection: reflection,
        content_class: content_class,
        snapshot_reader: snapshot_reader || snapshot
      }

      has_many reflection, dependent: :destroy
      belongs_to :current_version, class_name: version_class, optional: true
    end
  end

  included do
    class_attribute :versionable_options, instance_writer: false
    before_destroy :nullify_current_version_id_before_destroy
  end

  def versions_relation
    public_send(self.class.versionable_options[:reflection])
  end

  # The "current" version: the explicit head, else the most recent row.
  def display_current_version
    return current_version if current_version
    rel = versions_relation
    rel.loaded? ? rel.max_by(&:version_number) : rel.ordered.first
  end

  # JSON string for the current definition (reader hook per resource).
  def current_snapshot
    public_send(self.class.versionable_options[:snapshot_reader])
  end

  def content_class
    self.class.versionable_options[:content_class].constantize
  end

  # Commit the current definition as a new immutable version and advance the
  # head. No-ops when the payload is unchanged (hash equal to the current head).
  # Pass `content:` to reference an existing content row (restore/set path).
  def commit_version!(description: nil, based_on_version_id: nil, content: nil)
    content ||= content_class.store!(customer_id: customer_id, payload: JSON.parse(current_snapshot))

    if current_version&.content_id == content.id && based_on_version_id.nil?
      return current_version # true no-op: identical definition
    end

    based_on_id =
      if based_on_version_id.present? && versions_relation.exists?(id: based_on_version_id)
        based_on_version_id
      else
        current_version_id
      end

    version  = nil
    attempts = 0
    begin
      attempts += 1
      transaction do
        lock! if persisted?
        next_number = versions_relation.maximum(:version_number).to_i + 1
        version = versions_relation.create!(
          customer_id: customer_id,
          version_number: next_number,
          description: description,
          based_on_version_id: based_on_id,
          content: content
        )
        update_column(:current_version_id, version.id)
      end
    rescue ActiveRecord::RecordNotUnique
      retry if attempts < 3
      raise
    end

    prune_versions!
    content_class.sweep_orphans!(customer_id: customer_id)
    version
  end

  # Restore-as-new: create a new head version whose content IS the chosen
  # version's existing content row (zero payload copy), with lineage. Then
  # refresh the in-memory definition from that content.
  def restore_as_new!(version)
    committed = commit_version!(description: "Restored from v#{version.version_number}",
                                based_on_version_id: version.id, content: version.content)
    reload_definition_from_head!
    committed
  end

  # Move the head pointer to an existing version without creating a new one.
  def set_current_version!(version)
    update_column(:current_version_id, version.id)
    reload_definition_from_head!
  end

  # Default no-op; Entity/Flowchart/Page override to repopulate virtual attrs.
  def reload_definition_from_head!; end

  private

  def nullify_current_version_id_before_destroy
    update_column(:current_version_id, nil) if current_version_id.present?
  end

  def prune_versions!
    rel = versions_relation
    old = rel.ordered.offset(MAX_VERSIONS)
    return unless old.exists?
    pruned_ids = old.ids
    update_column(:current_version_id, nil) if current_version_id.in?(pruned_ids)
    rel.where(based_on_version_id: pruned_ids).update_all(based_on_version_id: nil)
    old.destroy_all
  end
end
```

- [ ] **Step 4: Run tests** — they also depend on Task 7 (Entity virtual attrs + `reload_definition_from_head!`).

Run: `bundle exec rspec spec/models/concerns/versionable_spec.rb`
Expected: PASS after Task 7 lands. (If executing strictly in order, mark this step and re-run at the end of Task 7.)

- [ ] **Step 5: Commit**

```bash
git add app/models/concerns/versionable.rb spec/models/concerns/versionable_spec.rb
git commit -m "refactor(versioning): head pointer + content-addressed commit/restore/GC"
```

---

### Task 7: Entity — virtual definition attributes + head load + bridge rework

**Files:**
- Modify: `app/models/entity.rb`
- Modify: `app/models/concerns/bridge_entity_management.rb`
- Test: `spec/models/entity_spec.rb` (add examples)

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/models/entity_spec.rb  (append)
require "rails_helper"

RSpec.describe Entity do
  it "loads its definition body from the head version's content on find" do
    e = Entity.create!(customer_id: 1, name: "Widget", type: :customer_specific)
    e.property_schema_json = [{ "key" => "sku", "type" => "string" }]
    e.icon = "box"
    e.commit_version!

    reloaded = Entity.find(e.id)
    expect(reloaded.property_schema_json).to eq([{ "key" => "sku", "type" => "string" }])
    expect(reloaded.icon).to eq("box")
  end

  it "keeps name/type as plain columns (renames do not create a version)" do
    e = Entity.create!(customer_id: 1, name: "A", type: :customer_specific)
    e.property_schema_json = [{ "key" => "x" }]
    e.commit_version!
    expect { e.update!(name: "B"); e.commit_version! }
      .not_to change { e.entity_versions.count }
    expect(e.reload.name).to eq("B")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/entity_spec.rb -e "loads its definition"`
Expected: FAIL — body still column-backed / no head load.

- [ ] **Step 3: Rewrite Entity's configuration + versioning + delegation blocks**

Replace lines 20-35 (the `json_attribute`/`acts_as_versionable` block) and the definition-snapshot methods (lines 103-141) as follows. Keep all identity/enum/scope/validation code unchanged.

```ruby
  # --- Definition body: virtual attributes, backed by the head version's
  # content. Declared as Rails attributes so ActiveModel::Dirty tracking,
  # json_attribute, and BridgeEntityManagement keep working after the columns
  # are dropped. Populated from current_version.content on #after_find.
  attribute :property_schema,    :text
  attribute :default_properties, :text
  attribute :associations,       :text
  attribute :attribute_groups,   :text
  attribute :extendable_models,  :text
  attribute :icon,               :string, default: "custom"
  attribute :color,              :string, default: "#6366f1"
  attribute :description,        :text
  attribute :referenced_template, :text

  json_attribute :property_schema,    default: []
  json_attribute :default_properties, default: {}
  json_attribute :associations,       default: []
  json_attribute :attribute_groups,   default: []
  json_attribute :extendable_models,  default: []

  sluggable source: :name, slug_column: :name_slug, scope: :customer_id

  acts_as_versionable reflection: :entity_versions,
                      version_class: "EntityVersion",
                      content_class: "EntityDefinitionContent",
                      snapshot_reader: :definition_snapshot_json

  after_find :reload_definition_from_head!
```

Replace `definition_snapshot`/`definition_snapshot_json`/`apply_definition_snapshot!` (lines 103-141) with:

```ruby
  # The canonical definition hash stored in a version's content. name/name_slug/
  # type are NOT included — they are un-versioned identity columns on the parent.
  def definition_snapshot
    {
      "icon"                => icon,
      "color"               => color,
      "description"         => description,
      "property_schema"     => property_schema_json     || [],
      "default_properties"  => default_properties_json  || {},
      "associations"        => associations_json        || [],
      "attribute_groups"    => attribute_groups_json    || [],
      "extendable_models"   => extendable_models_json   || [],
      "referenced_template" => referenced_template
    }
  end

  def definition_snapshot_json = definition_snapshot.to_json

  # Populate the virtual definition attributes from the current head content.
  # Called on after_find and after head moves (restore / set-current).
  def reload_definition_from_head!
    payload = current_version&.content&.payload
    snap = payload.present? ? JSON.parse(payload) : {}
    assign_attributes(
      icon:                snap.fetch("icon", "custom"),
      color:               snap.fetch("color", "#6366f1"),
      description:         snap["description"],
      referenced_template: snap["referenced_template"],
      property_schema:     (snap["property_schema"]    || []).to_json,
      default_properties:  (snap["default_properties"] || {}).to_json,
      associations:        (snap["associations"]       || []).to_json,
      attribute_groups:    (snap["attribute_groups"]   || []).to_json,
      extendable_models:   (snap["extendable_models"]  || []).to_json
    )
    clear_changes_information if persisted? # loaded state is the baseline for Dirty
    self
  end
```

> `clear_changes_information` resets the dirty baseline to the just-loaded values so a subsequent edit is diffed against the head content — this is what keeps `will_save_change_to_associations?` accurate.

- [ ] **Step 4: Rework `BridgeEntityManagement` orphan detection**

In `app/models/concerns/bridge_entity_management.rb`, `sync_bridge_entities!` currently calls `save(validate: false)` after mutating `associations_json`; a bridge Entity's body must now be committed as a version. Add a commit after each bridge entity is synced, and after the parent's own associations are rewritten:

Modify the tail of `sync_bridge_entities!` (the `self.associations_json = associations; save(validate: false) if persisted?` block) to:

```ruby
      self.associations_json = associations
      if persisted?
        save(validate: false)
        commit_version!(description: "Bridge sync")
      end
```

And in `sync_single_bridge_entity` (creates/updates the bridge `Entity`), after the bridge entity is saved, add `bridge.commit_version!(description: "Auto-generated bridge")` so the bridge entity's definition is stored in a version (bridge entities were previously excluded from versioning). Locate the `save`/`create` of the bridge record and append the commit on success.

> `track_old_associations` and `will_save_change_to_associations?` are unchanged and keep working because `associations` is now a dirty-tracked virtual attribute whose baseline is set by `reload_definition_from_head!`.

- [ ] **Step 5: Run tests**

Run: `bundle exec rspec spec/models/entity_spec.rb spec/models/concerns/versionable_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/entity.rb app/models/concerns/bridge_entity_management.rb spec/models/entity_spec.rb
git commit -m "refactor(entity): definition body as head-backed virtual attributes"
```

---

### Task 8: Flowchart — virtual `configuration` + head load

**Files:**
- Modify: `app/models/flowchart.rb`
- Test: `spec/models/flowchart_spec.rb` (add example)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/flowchart_spec.rb (append)
it "loads configuration from the head version content on find" do
  fc = Flowchart.create!(customer_id: 1, name: "F", uuid: SecureRandom.uuid,
                         configuration: { "nodes" => [] }.to_json)
  fc.configuration = { "nodes" => [{ "id" => "n1" }] }.to_json
  fc.commit_version!
  expect(Flowchart.find(fc.id).configuration_json).to eq({ "nodes" => [{ "id" => "n1" }] })
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "loads configuration from the head"`
Expected: FAIL.

- [ ] **Step 3: Edit `flowchart.rb`**

Replace `json_attribute :configuration` with a virtual attribute plus the same accessor, and update `acts_as_versionable`:

```ruby
  attribute :configuration, :text
  json_attribute :configuration

  acts_as_versionable reflection: :flowchart_versions,
                      version_class: "FlowchartVersion",
                      content_class: "FlowchartConfigurationContent",
                      snapshot: :configuration

  after_find :reload_definition_from_head!
```

Remove the standalone `VERSION_PAYLOAD_KEY = :configuration` line. Add the head-load override:

```ruby
  def reload_definition_from_head!
    payload = current_version&.content&.payload
    self.configuration = payload if payload.present?
    clear_changes_information if persisted?
    self
  end
```

> `configuration_must_be_valid_json` and `validates :configuration, presence: true` are unchanged (they validate the virtual attribute). `generate_activity` (before_save, derives the `activity` column from configuration) still works.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "loads configuration from the head"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/flowchart.rb spec/models/flowchart_spec.rb
git commit -m "refactor(flowchart): configuration as head-backed virtual attribute"
```

---

### Task 9: Page — virtual `configuration` + head load

**Files:**
- Modify: `app/models/page.rb`
- Test: `spec/models/page_spec.rb` (add example)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/page_spec.rb (append)
it "loads configuration from the head version content on find" do
  page = Page.create!(customer_id: 1, name: "P",
                      configuration: { "fields" => [], "metadata" => {} }.to_json)
  page.configuration = { "fields" => [{ "key" => "f1" }], "metadata" => {} }.to_json
  page.commit_version!
  expect(Page.find(page.id).configuration_json["fields"]).to eq([{ "key" => "f1" }])
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/page_spec.rb -e "loads configuration from the head"`
Expected: FAIL.

- [ ] **Step 3: Edit `page.rb`**

Replace `json_attribute :configuration, default: { "fields" => [], "metadata" => {} }` with a virtual attribute + the same `json_attribute`, and update `acts_as_versionable`:

```ruby
  attribute :configuration, :text
  json_attribute :configuration, default: { "fields" => [], "metadata" => {} }

  acts_as_versionable reflection: :page_versions,
                      version_class: "PageVersion",
                      content_class: "PageConfigurationContent",
                      snapshot: :configuration

  after_find :reload_definition_from_head!
```

Remove the standalone `VERSION_PAYLOAD_KEY = :configuration`. Add the head-load override (it must also clear the model's own `@configuration_json_parsed` memo):

```ruby
  def reload_definition_from_head!
    payload = current_version&.content&.payload
    if payload.present?
      self.configuration = payload
      remove_instance_variable(:@configuration_json_parsed) if instance_variable_defined?(:@configuration_json_parsed)
    end
    clear_changes_information if persisted?
    self
  end
```

> The existing `configuration_json` override (memoized parse) and `configuration_json=` setter are unchanged. `generate_content` (derives the `content` column) still works.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/page_spec.rb -e "loads configuration from the head"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/page.rb spec/models/page_spec.rb
git commit -m "refactor(page): configuration as head-backed virtual attribute"
```

---

### Task 10: `BaseVersionsController` — current pointer + set-current

**Files:**
- Modify: `app/controllers/admin/maintenance/base_versions_controller.rb`
- Test: `spec/requests/admin/maintenance/entity_versions_spec.rb` (add examples)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/admin/maintenance/entity_versions_spec.rb (append; SKIP_AUTH env in test)
it "restore-as-new references existing content and advances the head" do
  entity = Entity.create!(customer_id: current_customer.id, name: "E", type: :customer_specific)
  entity.property_schema_json = [{ "key" => "a" }]; v1 = entity.commit_version!
  entity.property_schema_json = [{ "key" => "b" }]; entity.commit_version!

  before = EntityDefinitionContent.where(customer_id: current_customer.id).count
  post admin_maintenance_entity_versions_path(current_customer.id, entity), params: { version_id: v1.id }

  expect(response).to have_http_status(:ok)
  expect(EntityDefinitionContent.where(customer_id: current_customer.id).count).to eq(before)
  expect(entity.reload.property_schema_json).to eq([{ "key" => "a" }])
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/entity_versions_spec.rb`
Expected: FAIL — references to `default_version_id`/`apply_version_snapshot!`.

- [ ] **Step 3: Edit the controller**

Replace the `default` and `destroy` actions and `index_json` to use `current_version_id` and the pointer-only `set_current_version!`:

```ruby
      # PUT .../versions/:id/default  (set an existing version as the head)
      def default
        version = parent.versions_relation.find(params[:id])
        parent.set_current_version!(version)
        render json: { success: true, current_version_id: version.id, version_number: version.version_number }
      end

      # DELETE .../versions/:id
      def destroy
        version = parent.versions_relation.find(params[:id])
        if version.id == parent.current_version_id
          return render json: {
            error: "current_version_undeletable",
            message: "Cannot delete the current version. Set another version as current first."
          }, status: :unprocessable_entity
        end
        parent.transaction do
          parent.versions_relation.where(based_on_version_id: version.id).update_all(based_on_version_id: nil)
          version.destroy!
          parent.content_class.sweep_orphans!(customer_id: parent.customer_id)
        end
        render json: { success: true, id: version.id }
      end
```

And in `index_json`, change `is_default: v.id == parent.default_version_id` to `is_default: v.id == parent.current_version_id`.

> The `create` (restore-as-new) action is unchanged — it calls `parent.restore_as_new!(version)`, which now references existing content. The `show` action is unchanged (`configuration: v.payload` resolves through content).

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/entity_versions_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/base_versions_controller.rb spec/requests/admin/maintenance/entity_versions_spec.rb
git commit -m "refactor(versioning): versions controller uses head pointer + content GC"
```

---

### Task 11: `EntitiesController` — write path

**Files:**
- Modify: `app/controllers/admin/maintenance/entities_controller.rb`
- Test: `spec/requests/admin/maintenance/entities_spec.rb` (add example)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/admin/maintenance/entities_spec.rb (append)
it "creates a versioned definition and updates it without duplicating content" do
  post admin_maintenance_entities_path(current_customer.id), params: {
    entity: { name: "Widget", type: "customer_specific",
              property_schema: [{ "key" => "sku", "type" => "string" }].to_json }
  }
  entity = Entity.find_by!(name: "Widget", customer_id: current_customer.id)
  expect(entity.current_version).to be_present
  expect(entity.property_schema_json).to eq([{ "key" => "sku", "type" => "string" }])

  # a no-op update (same body) creates no new version
  expect {
    patch admin_maintenance_entity_path(current_customer.id, entity), params: {
      entity: { property_schema: [{ "key" => "sku", "type" => "string" }].to_json }
    }
  }.not_to change { entity.reload.entity_versions.count }
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/admin/maintenance/entities_spec.rb`
Expected: FAIL — `VERSIONED_COLUMNS` removed / no head created.

- [ ] **Step 3: Edit the controller**

In `create` (lines 93-95), replace the conditional snapshot with an unconditional no-op-safe commit and eager-load content in the index:

```ruby
      if saved
        @entity.commit_version!(description: "Manual save",
                                based_on_version_id: params[:based_on_version_id])
```

In `update` (lines 117-121), replace the `VERSIONED_COLUMNS` intersection block with:

```ruby
      if saved
        @entity.commit_version!(description: "Manual save",
                                based_on_version_id: params[:based_on_version_id])
```

In `index` (lines 26-31), rename the eager loads and column key:
- `key: :default_version` → `key: :current_version`, label `"Current Version"`, `cell: ->(e) { (v = e.display_current_version) ? "v#{v.version_number}" : "—" }`
- `includes(:default_version, :entity_versions)` → `includes(current_version: :content).includes(:entity_versions)` (both the two `base =` lines).

> `commit_version!` is now called for bridge entities too (they need a head version); its hash no-op makes repeated calls cheap. The old `!@entity.bridge_entity?` guard and `EntityVersion::VERSIONED_COLUMNS` reference are removed.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/admin/maintenance/entities_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/entities_controller.rb spec/requests/admin/maintenance/entities_spec.rb
git commit -m "refactor(entities): write path commits versions via content store"
```

---

### Task 12: Flowchart & Page controllers — write path

**Files:**
- Modify: `app/controllers/admin/maintenance/flowcharts_controller.rb`
- Modify: `app/controllers/admin/maintenance/pages_controller.rb`
- Test: `spec/requests/admin/maintenance/flowcharts_spec.rb`, `pages_spec.rb` (add examples)

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/requests/admin/maintenance/flowcharts_spec.rb (append)
it "saving unchanged configuration creates no new version" do
  fc = Flowchart.create!(customer_id: current_customer.id, name: "F", uuid: SecureRandom.uuid,
                         configuration: { "nodes" => [] }.to_json)
  fc.commit_version!
  expect {
    patch admin_maintenance_flowchart_path(current_customer.id, fc),
          params: { flowchart: { configuration: { "nodes" => [] }.to_json } }
  }.not_to change { fc.reload.flowchart_versions.count }
end
```

(Analogous example in `pages_spec.rb` asserting a real configuration change creates exactly one version.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/admin/maintenance/flowcharts_spec.rb spec/requests/admin/maintenance/pages_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Edit `flowcharts_controller.rb`**

In `update` (lines 94-105), replace the `configuration != configuration_was` guarded snapshot with an unconditional no-op-safe commit:

```ruby
    def update
      if @flowchart.update(update_params)
        @flowchart.commit_version!(description: "Manual save",
                                   based_on_version_id: params[:based_on_version_id])
        respond_to do |format|
          format.html { redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart), notice: "Flowchart was successfully updated." }
          format.json { render json: { status: "success", message: "Flowchart saved successfully" } }
        end
      else
        ...
```

In the `create` action, replace its `create_version_snapshot!` call (if present) with `commit_version!` (same args). In `index` (line 30), change `key: :default_version` → `:current_version` with label "Current Version" and `display_current_version`, and `includes(:entity, :default_version, :flowchart_versions)` → `includes(:entity, :flowchart_versions).includes(current_version: :content)`.

- [ ] **Step 4: Edit `pages_controller.rb`**

Replace both `@page.create_version_snapshot!(...)` calls (create ~line 117, update ~line 150) with `@page.commit_version!(...)` (same args). Drop the `configuration_changed` guard around the update commit — call `commit_version!` unconditionally after a successful save; the no-op check handles unchanged configs. In `index` (lines 22-26), rename `default_version` → `current_version` / "Current Version" / `display_current_version`, and `includes(:default_version, :page_versions)` → `includes(:page_versions).includes(current_version: :content)`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/admin/maintenance/flowcharts_spec.rb spec/requests/admin/maintenance/pages_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/maintenance/flowcharts_controller.rb app/controllers/admin/maintenance/pages_controller.rb \
        spec/requests/admin/maintenance/flowcharts_spec.rb spec/requests/admin/maintenance/pages_spec.rb
git commit -m "refactor(flowchart,page): write path commits versions via content store"
```

---

### Task 13: Data migration — backfill content, drop payload + body columns

**Files:**
- Create: `db/migrate/20260704130000_migrate_versions_to_content_store.rb`
- Test: `spec/migrations/migrate_versions_to_content_store_spec.rb` (optional harness) + full-suite regression in Task 14.

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

# Destructive backfill. Reads each version's raw snapshot/configuration column
# one last time, stores it in the content-addressed table, and sets content_id.
# Points each parent's current_version_id at its former default_version (now
# renamed) — the live state already equals that snapshot, so content dedup makes
# them coincide with no new head. Creates a v1 head for parents lacking any
# version (notably bridge entities, previously excluded from versioning). Then
# drops the payload columns and Entity's body columns.
class MigrateVersionsToContentStore < ActiveRecord::Migration[8.1]
  RESOURCES = [
    { versions: "entity_versions",    parent: "entities",   fk: "entity_id",
      content: "entity_definition_contents",     payload_col: "snapshot" },
    { versions: "flowchart_versions", parent: "flowcharts", fk: "flowchart_id",
      content: "flowchart_configuration_contents", payload_col: "configuration" },
    { versions: "page_versions",      parent: "pages",      fk: "page_id",
      content: "page_configuration_contents",      payload_col: "configuration" }
  ].freeze

  def up
    canon = ->(str) { canonical(str) }

    RESOURCES.each do |r|
      say_with_time "Backfilling #{r[:content]}" do
        rows = select_all("SELECT id, customer_id, #{r[:payload_col]} AS payload FROM #{r[:versions]}")
        rows.each do |row|
          hash    = Digest::SHA256.hexdigest(canon.call(row["payload"]))
          cust    = row["customer_id"]
          cust_eq = cust.nil? ? "IS NULL" : "= #{cust.to_i}"
          existing = select_value(
            "SELECT id FROM #{r[:content]} WHERE customer_id #{cust_eq} AND content_hash = #{quote(hash)}"
          )
          content_id = existing || begin
            execute(<<~SQL)
              INSERT INTO #{r[:content]} (customer_id, content_hash, payload, created_at)
              VALUES (#{cust ? cust.to_i : 'NULL'}, #{quote(hash)}, #{quote(canon.call(row["payload"]))}, #{quote(Time.current)})
            SQL
            select_value("SELECT id FROM #{r[:content]} WHERE customer_id #{cust_eq} AND content_hash = #{quote(hash)}")
          end
          execute("UPDATE #{r[:versions]} SET content_id = #{content_id} WHERE id = #{row['id']}")
        end
        rows.count
      end
    end

    # Point current_version_id at the former default (already renamed to
    # current_version_id by the additive migration — for existing rows it still
    # holds the old default_version id). No-op if already set. Nothing to do.

    # Create a v1 head for parents with no versions (bridge entities etc.).
    backfill_missing_heads

    # Enforce not-null and drop the old payload columns.
    RESOURCES.each do |r|
      change_column_null r[:versions].to_sym, :content_id, false
      remove_column r[:versions].to_sym, r[:payload_col].to_sym
    end

    # Drop Entity's now-virtual body columns (Flowchart/Page keep only the
    # single configuration column, dropped above via the versions loop's parent?
    # No — parent configuration columns are separate; drop them here).
    remove_column :flowcharts, :configuration
    remove_column :pages,      :configuration
    %i[property_schema default_properties associations attribute_groups
       extendable_models icon color description referenced_template].each do |col|
      remove_column :entities, col
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Bridge entities (and any parent) lacking a version get a v1 built from their
  # current live columns, using the models (post-refactor) so the snapshot is
  # serialized exactly as the app does.
  def backfill_missing_heads
    say_with_time "Creating v1 heads for unversioned parents" do
      count = 0
      Entity.reset_column_information
      Entity.where(current_version_id: nil).find_each do |e|
        e.commit_version!(description: "Initial version")
        count += 1
      end
      count
    end
  end

  def canonical(str)
    parsed = str.present? ? JSON.parse(str) : {}
    JSON.generate(deep_sort(parsed))
  rescue JSON::ParserError
    JSON.generate(str.to_s)
  end

  def deep_sort(v)
    case v
    when Hash  then v.keys.sort.to_h { |k| [k, deep_sort(v[k])] }
    when Array then v.map { |e| deep_sort(e) }
    else v
    end
  end
end
```

> Ordering caveat: `backfill_missing_heads` uses `Entity#commit_version!`, which reads the (still-present) body columns via the virtual attributes' `after_find`. Because the body columns are dropped *after* this method runs, `commit_version!` here serializes from the live columns correctly. For Flowchart/Page the additive `default_version_id`→`current_version_id` rename already gives every existing parent a head, so only Entity bridge rows need `backfill_missing_heads`.

- [ ] **Step 2: Run the migration (dev + test)**

Run: `rm -f public/assets/.manifest.json && bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate`
Expected: backfill counts logged; no errors; `snapshot`/`configuration` and Entity body columns gone from `db/schema.rb`.

- [ ] **Step 3: Verify no orphaned/unreferenced state**

Run:
```bash
bin/rails runner '
  bad = Entity.where(current_version_id: nil).count
  puts "entities without head: #{bad}"
  puts "entity contents: #{EntityDefinitionContent.count}, versions: #{EntityVersion.count}"
'
```
Expected: `entities without head: 0`; content count ≤ version count (dedup).

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260704130000_migrate_versions_to_content_store.rb db/schema.rb
git commit -m "feat(versioning): backfill content store, drop payload + entity body columns"
```

---

### Task 14: Full-suite regression + dead-code sweep

**Files:**
- Modify: any spec/factory referencing dropped columns or removed methods.

- [ ] **Step 1: Grep for stale references**

Run:
```bash
grep -rn "default_version\|create_version_snapshot!\|apply_version_snapshot\|VERSIONED_COLUMNS\|\.snapshot\b" app lib spec \
  | grep -v "current_version\|db/migrate"
```
Expected: no production hits. Fix any spec/factory hits (e.g. factories that set `snapshot:`/`configuration:` directly on version rows must set `content:` instead, or build through `commit_version!`).

- [ ] **Step 2: Update factories**

Point `entity_version`/`flowchart_version`/`page_version` factories at a `content` association (or remove them in favor of building versions through the parent's `commit_version!`). Show the entity_version factory:

```ruby
factory :entity_version do
  association :entity
  customer_id { 1 }
  sequence(:version_number)
  content { EntityDefinitionContent.store!(customer_id: customer_id, payload: { "property_schema" => [] }) }
end
```

- [ ] **Step 3: Run the affected layers**

This is a cross-cutting change (auth/tenant-neutral but touches three models + shared concerns), so run the broader relevant set:

Run:
```bash
bundle exec rspec spec/models spec/requests/admin/maintenance \
  spec/controllers 2>&1 | tail -30
```
Expected: all green. Triage failures against the stale-test policy — where a spec asserts old snapshot-duplication behavior, rewrite it to assert content-addressed behavior.

- [ ] **Step 4: Full suite**

Per the memory note, run the full suite via the parallel runner (≈6 min):

Run: `bin/rails parallel:spec`
Expected: green except the known-flaky JS drawer + parallel auth-password specs noted in memory (`[[flaky-auth-password-specs-under-parallel]]`, `[[fast-parallel-test-suite]]`). Re-run any failures in isolation to confirm they are the known flakes, not regressions.

- [ ] **Step 5: Smoke test the dev server**

Run:
```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
sleep 5
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/81721200/admin/maintenance/entities
```
Expected: `200`. Open an entity, edit its schema, save, confirm a new version appears and the Versions panel restore works.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "test(versioning): update factories/specs for content-addressed versions"
```

---

## Self-review notes

- **Spec coverage:** content tables + `content_id` + rename (Task 1); `ContentAddressable` A/B dedup + GC (Tasks 2–3, 6); `VersionRecord` payload-via-content (Task 4); head pointer + `commit_version!` no-op + restore-as-reference + prune GC (Task 6); Entity name/type un-versioning + virtual-attribute delegation (Task 7); Flowchart/Page delegation (Tasks 8–9); controllers current-pointer + write path (Tasks 10–12); migration/backfill incl. bridge v1 (Task 13); multi-tenant per-tenant dedup (Task 2 test); blast-radius regression (Task 14). All spec sections map to a task.
- **Type consistency:** `commit_version!`, `restore_as_new!`, `set_current_version!`, `reload_definition_from_head!`, `content_class`, `current_version(_id)`, `store!`, `sweep_orphans!`, `canonical_json`, `digest`, `version_association` are used with identical signatures across tasks.
- **Known risk:** `BridgeEntityManagement` dirty-tracking depends on `reload_definition_from_head!` calling `clear_changes_information` to set the baseline (Task 7, Step 3/4). Task 14 must confirm bridge-entity association add/remove still cleans up orphans.
```
