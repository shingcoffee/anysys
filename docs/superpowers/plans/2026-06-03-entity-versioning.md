# Entity Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Version entity *definitions* so every meaningful edit snapshots a new default version, any two versions can be diffed side-by-side, and an old version can be forked into a new default.

**Architecture:** Mirror the existing `flowchart_versions` pattern. A new `entity_versions` table stores immutable JSON snapshots of the entity definition. An `EntityVersioning` concern on `Entity` records a snapshot via `after_commit` whenever a versioned column actually changes (skipping bridge entities and no-op saves); the newest version is always `is_default` and equals the entity's live columns. A pure `Entities::VersionDiff` service computes a structured side-by-side diff. A nested admin controller + ViewComponents expose list / compare / fork on the entity show page.

**Tech Stack:** Rails 8.1, ViewComponent, StimulusJS, TailwindCSS, RSpec. SQLite in test (no row locks — mirror flowchart's lock/retry).

**Reference files to read before starting:**
- `app/models/flowchart_version.rb`, `app/models/flowchart.rb:164-198` (`create_version_snapshot!`)
- `app/controllers/admin/maintenance/flowchart_versions_controller.rb`
- `spec/requests/maintenance/flowchart_versions_spec.rb`
- `app/models/entity.rb`, `app/models/concerns/{tenant_scoped,json_serializable}.rb`
- `app/views/admin/maintenance/entities/show.html.erb`
- `app/components/badge_component.rb` (+ `.html.erb`) for component style

---

### Task 1: Migration + `entity_versions` table

**Files:**
- Create: `db/migrate/20260603000001_create_entity_versions.rb`
- Modify: `db/schema.rb` (auto via migrate)

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class CreateEntityVersions < ActiveRecord::Migration[8.1]
  def up
    create_table :entity_versions do |t|
      t.integer  :entity_id,      null: false
      t.integer  :customer_id,    null: false
      t.integer  :version_number, null: false
      t.text     :snapshot,       null: false
      t.string   :description
      t.boolean  :is_default,     null: false, default: false
      t.timestamps
    end

    add_index :entity_versions, %i[entity_id version_number], unique: true,
              name: "index_entity_versions_on_entity_id_and_version_number"
    add_index :entity_versions, :entity_id
    add_index :entity_versions, :customer_id
    add_index :entity_versions, %i[entity_id is_default]

    # Backfill an initial default version (v1) for existing non-bridge entities
    # so the Versions panel is populated for pre-existing data.
    say_with_time "Backfilling initial entity versions" do
      execute(<<~SQL)
        INSERT INTO entity_versions
          (entity_id, customer_id, version_number, snapshot, description, is_default, created_at, updated_at)
        SELECT e.id, e.customer_id, 1,
               json_object(
                 'name', e.name,
                 'name_slug', e.name_slug,
                 'element_type', e.element_type,
                 'icon', e.icon,
                 'color', e.color,
                 'description', e.description,
                 'property_schema', COALESCE(e.property_schema, '[]'),
                 'default_properties', COALESCE(e.default_properties, '{}'),
                 'associations', COALESCE(e.associations, '[]'),
                 'attribute_groups', COALESCE(e.attribute_groups, '[]'),
                 'referenced_template', e.referenced_template
               ),
               'Initial version', 1,
               CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM entities e
        WHERE e.is_bridge_entity = #{quoted_false}
          AND NOT EXISTS (SELECT 1 FROM entity_versions ev WHERE ev.entity_id = e.id)
      SQL
    end
  end

  def down
    drop_table :entity_versions
  end
end
```

> NOTE: the backfill stores `property_schema`/`associations`/etc. as JSON *strings* nested inside the snapshot string. The model snapshot writer (Task 3) instead stores parsed structures. Both round-trip through `JSON.parse`; the diff service (Task 4) normalizes by parsing string values that look like JSON. Keep the backfill simple — it only needs to produce a readable v1.

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `entity_versions` table created; `db/schema.rb` updated; no errors.

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260603000001_create_entity_versions.rb db/schema.rb
git commit -m "feat(entity-versioning): add entity_versions table + backfill"
```

---

### Task 2: `EntityVersion` model

**Files:**
- Create: `app/models/entity_version.rb`
- Test: `spec/models/entity_version_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe EntityVersion, type: :model do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  it "is valid with a snapshot and version_number" do
    v = entity.entity_versions.build(customer_id: customer.id, snapshot: "{}", version_number: 99)
    expect(v).to be_valid
  end

  it "requires a snapshot" do
    v = entity.entity_versions.build(customer_id: customer.id, snapshot: nil, version_number: 99)
    expect(v).not_to be_valid
  end

  it "enforces version_number uniqueness per entity" do
    entity.entity_versions.create!(customer_id: customer.id, snapshot: "{}", version_number: 5)
    dup = entity.entity_versions.build(customer_id: customer.id, snapshot: "{}", version_number: 5)
    expect(dup).not_to be_valid
  end

  it "orders newest first and exposes snapshot_json" do
    entity.entity_versions.create!(customer_id: customer.id, snapshot: '{"name":"A"}', version_number: 1)
    entity.entity_versions.create!(customer_id: customer.id, snapshot: '{"name":"B"}', version_number: 2)
    expect(entity.entity_versions.ordered.first.version_number).to eq(2)
    expect(entity.entity_versions.ordered.first.snapshot_json).to eq("name" => "B")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/entity_version_spec.rb`
Expected: FAIL — `uninitialized constant EntityVersion`.

- [ ] **Step 3: Write the model**

```ruby
# frozen_string_literal: true

class EntityVersion < ApplicationRecord
  include JsonSerializable

  belongs_to :entity

  json_attribute :snapshot, default: {}

  validates :snapshot, presence: true
  validates :version_number, presence: true, uniqueness: { scope: :entity_id }

  scope :ordered,         -> { order(version_number: :desc) }
  scope :recent,          -> { ordered.limit(50) }
  scope :default_version, -> { where(is_default: true) }
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/entity_version_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
git add app/models/entity_version.rb spec/models/entity_version_spec.rb
git commit -m "feat(entity-versioning): EntityVersion model"
```

---

### Task 3: `EntityVersioning` concern (snapshot on change, fork)

**Files:**
- Create: `app/models/concerns/entity_versioning.rb`
- Modify: `app/models/entity.rb` (include concern + `has_many` — see Step 3)
- Test: `spec/models/concerns/entity_versioning_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe EntityVersioning, type: :model do
  let(:customer) { create(:customer) }

  def build_entity(**attrs)
    create(:entity, { customer: customer, name: "Donor",
                      property_schema: [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json }.merge(attrs))
  end

  it "creates version 1 as default on create" do
    e = build_entity
    expect(e.entity_versions.count).to eq(1)
    v1 = e.entity_versions.ordered.first
    expect(v1.version_number).to eq(1)
    expect(v1.is_default).to be(true)
    expect(v1.snapshot_json["name"]).to eq("Donor")
  end

  it "creates a new default version when a versioned column changes" do
    e = build_entity
    e.update!(description: "A donor record")
    expect(e.entity_versions.count).to eq(2)
    expect(e.entity_versions.ordered.first.version_number).to eq(2)
    expect(e.entity_versions.default_version.count).to eq(1)
    expect(e.entity_versions.default_version.first.version_number).to eq(2)
  end

  it "does not create a version for a no-op save" do
    e = build_entity
    e.update!(name: "Donor") # unchanged
    expect(e.entity_versions.count).to eq(1)
  end

  it "never versions bridge entities" do
    e = build_entity(is_bridge_entity: true)
    expect(e.entity_versions.count).to eq(0)
    e.update!(description: "x")
    expect(e.entity_versions.count).to eq(0)
  end

  it "keeps only the latest 50 versions" do
    e = build_entity
    (2..55).each { |n| e.update!(description: "rev #{n}") }
    expect(e.entity_versions.count).to eq(50)
    expect(e.entity_versions.ordered.first.version_number).to eq(55)
  end

  describe "#restore_as_new_version!" do
    it "copies an old snapshot into the live entity and makes it the new default" do
      e = build_entity
      v1 = e.entity_versions.ordered.first
      e.update!(name: "Donor", description: "edited", property_schema: [].to_json)
      expect(e.data_fields).to be_empty

      e.restore_as_new_version!(v1)
      e.reload

      expect((e.property_schema_json || []).map { |a| a["name_slug"] }).to eq(["email"])
      latest = e.entity_versions.ordered.first
      expect(latest.is_default).to be(true)
      expect(latest.version_number).to eq(e.entity_versions.maximum(:version_number))
      expect(latest.description).to match(/Forked from v1/)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/concerns/entity_versioning_spec.rb`
Expected: FAIL — `uninitialized constant EntityVersioning`.

- [ ] **Step 3: Write the concern, then wire it into Entity**

Create `app/models/concerns/entity_versioning.rb`:

```ruby
# frozen_string_literal: true

# EntityVersioning
#
# Snapshots an entity's *definition* into entity_versions whenever a versioned
# column actually changes. The newest version is always the default and mirrors
# the entity's live columns. Bridge entities are never versioned.
module EntityVersioning
  extend ActiveSupport::Concern

  MAX_VERSIONS = 50

  # Scalar + JSON columns that make up the versioned definition.
  VERSIONED_COLUMNS = %w[
    name name_slug element_type icon color description
    property_schema default_properties associations attribute_groups
    referenced_template
  ].freeze

  included do
    has_many :entity_versions, dependent: :destroy
    attr_accessor :pending_version_description
    after_commit :record_version_if_changed, on: %i[create update]
  end

  # The canonical definition hash stored in a version snapshot.
  def definition_snapshot
    {
      "name"                => name,
      "name_slug"           => name_slug,
      "element_type"        => element_type,
      "icon"                => icon,
      "color"               => color,
      "description"         => description,
      "property_schema"     => property_schema_json     || [],
      "default_properties"  => default_properties_json  || {},
      "associations"        => associations_json        || [],
      "attribute_groups"    => attribute_groups_json    || [],
      "referenced_template" => referenced_template
    }
  end

  # Fork: copy an old version's snapshot into the live columns, then save so the
  # after_commit hook records it as the new default version.
  def restore_as_new_version!(source_version)
    snap = source_version.snapshot_json
    assign_attributes(
      name:                snap["name"],
      element_type:        snap["element_type"],
      icon:                snap["icon"],
      color:               snap["color"],
      description:         snap["description"],
      property_schema:     dump_json(snap["property_schema"]),
      default_properties:  dump_json(snap["default_properties"]),
      associations:        dump_json(snap["associations"]),
      attribute_groups:    dump_json(snap["attribute_groups"]),
      referenced_template: snap["referenced_template"]
      # name_slug intentionally re-derived by Sluggable
    )
    self.pending_version_description = "Forked from v#{source_version.version_number}"
    save!
    entity_versions.ordered.first
  end

  private

  # JSON columns accept a String; nested snapshot values are already parsed.
  def dump_json(value)
    value.is_a?(String) ? value : value.to_json
  end

  def record_version_if_changed
    return if is_bridge_entity?

    if previously_new_record?
      create_version_snapshot!(description: take_pending_description)
    elsif versioned_columns_changed? && definition_differs_from_latest?
      create_version_snapshot!(description: take_pending_description)
    else
      self.pending_version_description = nil
    end
  end

  def take_pending_description
    desc = pending_version_description
    self.pending_version_description = nil
    desc
  end

  def versioned_columns_changed?
    (saved_changes.keys & VERSIONED_COLUMNS).any?
  end

  def definition_differs_from_latest?
    latest = entity_versions.ordered.first
    return true if latest.nil?
    latest.snapshot_json != definition_snapshot
  end

  # Mirrors Flowchart#create_version_snapshot! (lock + retry for SQLite/Postgres),
  # but additionally flips the default pointer to the newly created version.
  def create_version_snapshot!(description: nil)
    attempts = 0
    begin
      attempts += 1
      transaction do
        lock! if persisted?
        next_number = entity_versions.maximum(:version_number).to_i + 1
        entity_versions.where(is_default: true).update_all(is_default: false)
        entity_versions.create!(
          customer_id:    customer_id,
          snapshot:       definition_snapshot.to_json,
          version_number: next_number,
          description:    description,
          is_default:     true
        )
      end
    rescue ActiveRecord::RecordNotUnique
      retry if attempts < 3
      raise
    end

    prune = entity_versions.ordered.offset(MAX_VERSIONS)
    prune.destroy_all if prune.exists?
  end
end
```

Then modify `app/models/entity.rb` — add to the include list (after `include EntitySchemaValidation`):

```ruby
  include EntityVersioning
```

(Do NOT add a separate `has_many :entity_versions` in entity.rb — the concern adds it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/concerns/entity_versioning_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 5: Run entity model + CRUD specs to confirm no regression**

Run: `bundle exec rspec spec/models/entity_spec.rb spec/requests/maintenance/entities_spec.rb`
Expected: PASS. (The after_commit hook must not break existing create/update.)

- [ ] **Step 6: Commit**

```bash
git add app/models/concerns/entity_versioning.rb app/models/entity.rb spec/models/concerns/entity_versioning_spec.rb
git commit -m "feat(entity-versioning): snapshot-on-change concern + fork"
```

---

### Task 4: `Entities::VersionDiff` service (side-by-side)

**Files:**
- Create: `app/services/entities/version_diff.rb`
- Test: `spec/services/entities/version_diff_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe Entities::VersionDiff do
  def snap(overrides = {})
    {
      "name" => "Donor", "name_slug" => "donor", "element_type" => "custom",
      "icon" => "custom", "color" => "#111", "description" => "",
      "property_schema" => [], "default_properties" => {},
      "associations" => [], "attribute_groups" => [], "referenced_template" => nil
    }.merge(overrides)
  end

  it "flags changed meta scalar fields" do
    result = described_class.call(snap, snap("description" => "now set"))
    desc = result[:meta].find { |m| m[:field] == "description" }
    expect(desc[:status]).to eq(:changed)
    expect(desc[:a]).to eq("")
    expect(desc[:b]).to eq("now set")
    expect(result[:meta].find { |m| m[:field] == "name" }[:status]).to eq(:same)
  end

  it "detects added, removed, and changed attributes by name_slug" do
    a = snap("property_schema" => [
      { "name" => "Email", "name_slug" => "email", "html_type" => "text" },
      { "name" => "Fax",   "name_slug" => "fax",   "html_type" => "tel" }
    ])
    b = snap("property_schema" => [
      { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
      { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel" }
    ])
    result = described_class.call(a, b)
    by_key = result[:attributes].index_by { |x| x[:key] }
    expect(by_key["phone"][:status]).to eq(:added)
    expect(by_key["fax"][:status]).to eq(:removed)
    expect(by_key["email"][:status]).to eq(:changed)
    html = by_key["email"][:field_changes].find { |c| c[:field] == "html_type" }
    expect(html).to eq(field: "html_type", a: "text", b: "email")
  end

  it "marks identical snapshots as all same" do
    result = described_class.call(snap, snap)
    expect(result[:attributes]).to all(include(status: :same).or(be_a(Hash)))
    expect(result[:meta]).to all(include(status: :same))
    expect(result[:changed?]).to be(false)
  end

  it "accepts EntityVersion records and JSON strings" do
    customer = create(:customer); entity = create(:entity, customer: customer)
    va = entity.entity_versions.create!(customer_id: customer.id, version_number: 1, snapshot: snap.to_json)
    vb = entity.entity_versions.create!(customer_id: customer.id, version_number: 2, snapshot: snap("name" => "Member").to_json)
    result = described_class.call(va, vb)
    expect(result[:meta].find { |m| m[:field] == "name" }[:status]).to eq(:changed)
    expect(result[:changed?]).to be(true)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/entities/version_diff_spec.rb`
Expected: FAIL — `uninitialized constant Entities::VersionDiff`.

- [ ] **Step 3: Write the service**

```ruby
# frozen_string_literal: true

module Entities
  # Pure, read-only diff between two entity-definition snapshots.
  # Accepts EntityVersion records, JSON strings, or already-parsed hashes.
  class VersionDiff
    META_FIELDS = %w[name name_slug element_type icon color description referenced_template].freeze
    ATTR_FIELDS = %w[display_label type html_type validators visibility group_id config description].freeze

    def self.call(a, b)
      new(a, b).call
    end

    def initialize(a, b)
      @a = normalize(a)
      @b = normalize(b)
    end

    def call
      meta         = diff_meta
      attributes   = diff_collection("property_schema", "name_slug", ATTR_FIELDS)
      associations = diff_collection("associations", "name_slug", nil)
      groups       = diff_collection("attribute_groups", "id", %w[name color icon description])

      changed = meta.any? { |m| m[:status] != :same } ||
                [attributes, associations, groups].any? { |c| c.any? { |x| x[:status] != :same } }

      { meta:, attributes:, associations:, groups:, changed?: changed }
    end

    private

    def normalize(input)
      raw = input.respond_to?(:snapshot_json) ? input.snapshot_json : input
      raw = JSON.parse(raw) if raw.is_a?(String)
      (raw || {}).each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.is_a?(String) && json_like?(v) ? (JSON.parse(v) rescue v) : v
      end
    end

    def json_like?(str)
      stripped = str.strip
      stripped.start_with?("[", "{")
    end

    def diff_meta
      META_FIELDS.map do |field|
        av = @a[field]
        bv = @b[field]
        { field:, a: av, b: bv, status: av == bv ? :same : :changed }
      end
    end

    # Generic collection differ. `key` is the stable identity field; `fields`
    # is the list of attribute keys to compare for :changed (nil => compare whole hash).
    def diff_collection(column, key, fields)
      a_items = Array(@a[column])
      b_items = Array(@b[column])
      a_by = a_items.index_by { |x| x[key] }
      b_by = b_items.index_by { |x| x[key] }

      ordered_keys = b_items.map { |x| x[key] } + a_items.map { |x| x[key] }.reject { |k| b_by.key?(k) }

      ordered_keys.uniq.map do |k|
        av = a_by[k]
        bv = b_by[k]
        if av.nil?
          { key: k, status: :added,   a: nil, b: bv, field_changes: [] }
        elsif bv.nil?
          { key: k, status: :removed, a: av,  b: nil, field_changes: [] }
        else
          changes = field_changes(av, bv, fields)
          { key: k, status: changes.empty? ? :same : :changed, a: av, b: bv, field_changes: changes }
        end
      end
    end

    def field_changes(av, bv, fields)
      compare = fields || (av.keys | bv.keys)
      compare.filter_map do |f|
        next if av[f] == bv[f]
        { field: f, a: av[f], b: bv[f] }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/entities/version_diff_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/entities/version_diff.rb spec/services/entities/version_diff_spec.rb
git commit -m "feat(entity-versioning): VersionDiff service"
```

---

### Task 5: Routes + `EntityVersionsController` (admin, tenant-scoped)

**Files:**
- Modify: `config/routes.rb` (inside the `resources :entities, controller: "maintenance/entities"` block, ~line 189-199)
- Create: `app/controllers/admin/maintenance/entity_versions_controller.rb`
- Test: `spec/requests/maintenance/entity_versions_spec.rb`

- [ ] **Step 1: Add the nested routes**

Inside the existing entities block, add after the `entries` nested resource:

```ruby
          resources :versions, only: %i[index create],
                    controller: "maintenance/entity_versions" do
            collection { get :diff }
          end
```

- [ ] **Step 2: Write the failing request spec**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Maintenance::EntityVersions", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, customer: customer, role: :admin) }
  let(:member)   { create(:user, customer: customer, role: :member) }
  let(:entity)   { create(:entity, customer: customer, name: "Donor", description: "v1") }

  def base = "/#{customer.id}/admin/maintenance/entities/#{entity.id}/versions"

  before { entity.update!(description: "v2 edit") } # => versions 1 and 2 exist

  context "as admin" do
    before { sign_in admin }

    it "lists versions newest-first" do
      get base, as: :json
      expect(response).to have_http_status(:ok)
      numbers = JSON.parse(response.body).map { |v| v["version_number"] }
      expect(numbers).to eq([2, 1])
    end

    it "diffs two versions" do
      get "#{base}/diff", params: { a: 1, b: 2 }, as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["changed?"] || body["changed"]).to be_truthy
    end

    it "forks an old version into the new default and rewrites the live entity" do
      v1 = entity.entity_versions.find_by!(version_number: 1)
      post base, params: { version_id: v1.id }
      expect(response).to have_http_status(:found).or have_http_status(:ok)
      entity.reload
      expect(entity.description).to eq("v1")
      latest = entity.entity_versions.ordered.first
      expect(latest.is_default).to be(true)
      expect(latest.version_number).to eq(3)
    end
  end

  context "as member (member)" do
    before { sign_in member }
    it "is forbidden / redirected away from admin route" do
      get base, as: :json
      expect(response).not_to have_http_status(:ok)
    end
  end

  context "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let(:other_admin)    { create(:user, customer: other_customer, role: :admin) }
    before { sign_in other_admin }

    it "cannot read another customer's entity versions" do
      get "/#{other_customer.id}/admin/maintenance/entities/#{entity.id}/versions", as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/maintenance/entity_versions_spec.rb`
Expected: FAIL — routing error / missing controller.

- [ ] **Step 4: Write the controller**

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class EntityVersionsController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_entity

      # GET .../versions
      def index
        versions = @entity.entity_versions.recent
        render json: versions.map { |v| serialize(v) }
      end

      # GET .../versions/diff?a=<n>&b=<n>
      def diff
        a = @entity.entity_versions.find_by!(version_number: params.require(:a))
        b = @entity.entity_versions.find_by!(version_number: params.require(:b))
        result = Entities::VersionDiff.call(a, b)
        respond_to do |format|
          format.json { render json: result.merge(a: serialize(a), b: serialize(b)) }
          format.html do
            render(EntityVersionDiffComponent.new(entity: @entity, version_a: a, version_b: b, diff: result),
                   layout: false)
          end
        end
      end

      # POST .../versions  { version_id: }  => fork-from-old (new default)
      def create
        source = @entity.entity_versions.find(params.require(:version_id))
        ActiveRecord::Base.transaction do
          @entity.restore_as_new_version!(source)
          raise ActiveRecord::Rollback unless @entity.sync_bridge_entities!
        end
        respond_to do |format|
          format.html { redirect_to admin_maintenance_entity_path(current_customer_id, @entity),
                                    notice: "New version created from v#{source.version_number}." }
          format.json { render json: serialize(@entity.entity_versions.ordered.first), status: :created }
        end
      end

      private

      def find_entity
        @entity = Entity.for_current_customer.find(params[:entity_id])
      end

      def serialize(v)
        { id: v.id, version_number: v.version_number, description: v.description,
          is_default: v.is_default, created_at: v.created_at.iso8601 }
      end
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/maintenance/entity_versions_spec.rb`
Expected: PASS. (The `diff` HTML format depends on Task 7's component; the spec only exercises JSON, so it passes now. If the HTML branch errors at load time, guard with `format.json` only until Task 7, then add HTML.)

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/maintenance/entity_versions_controller.rb spec/requests/maintenance/entity_versions_spec.rb
git commit -m "feat(entity-versioning): nested admin versions controller + routes"
```

---

### Task 6: `EntityVersionListComponent`

**Files:**
- Create: `app/components/entity_version_list_component.rb`
- Create: `app/components/entity_version_list_component.html.erb`
- Test: `spec/components/entity_version_list_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe EntityVersionListComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  before { entity.update!(description: "edit") } # v1, v2 (v2 default)

  it "renders versions newest-first with a Default badge and a fork action on old versions" do
    render_inline(described_class.new(entity: entity, customer_id: customer.id))
    expect(page).to have_text("Version 2")
    expect(page).to have_text("Version 1")
    expect(page).to have_css("[data-version-number='2']")
    # Default badge on v2 only
    expect(page).to have_css("[data-version-number='2'] .badge", text: "Default")
    expect(page).not_to have_css("[data-version-number='1'] .badge", text: "Default")
    # Fork action present on the non-default v1
    expect(page).to have_css("[data-version-number='1'] [data-fork-version]")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/entity_version_list_component_spec.rb`
Expected: FAIL — `uninitialized constant EntityVersionListComponent`.

- [ ] **Step 3: Write the component class**

```ruby
# frozen_string_literal: true

class EntityVersionListComponent < ApplicationComponent
  def initialize(entity:, customer_id:)
    @entity = entity
    @customer_id = customer_id
  end

  def versions
    @versions ||= @entity.entity_versions.recent
  end

  attr_reader :entity, :customer_id
end
```

- [ ] **Step 4: Write the template**

`app/components/entity_version_list_component.html.erb`:

```erb
<div class="card" data-controller="entity-versions"
     data-entity-versions-diff-url-value="<%= diff_admin_maintenance_entity_versions_path(customer_id, entity) %>">
  <div class="px-6 py-4 border-b border-border-subtle flex items-center justify-between">
    <h3 class="section-header">Versions</h3>
    <button type="button" class="btn btn-secondary btn-sm" disabled
            data-entity-versions-target="compareBtn"
            data-action="click->entity-versions#compare">
      Compare selected
    </button>
  </div>

  <ul class="divide-y divide-border-subtle">
    <% versions.each do |v| %>
      <li class="flex items-center gap-3 px-6 py-3" data-version-number="<%= v.version_number %>">
        <input type="checkbox" class="rounded" value="<%= v.version_number %>"
               data-entity-versions-target="select"
               data-action="change->entity-versions#toggleSelect">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="text-body font-medium text-text-primary">Version <%= v.version_number %></span>
            <% if v.is_default %>
              <span class="badge badge-success">Default</span>
            <% end %>
          </div>
          <p class="text-caption truncate">
            <%= v.description.presence || "—" %> ·
            <span title="<%= v.created_at.iso8601 %>"><%= time_ago_in_words(v.created_at) %> ago</span>
          </p>
        </div>
        <% unless v.is_default %>
          <%= button_to admin_maintenance_entity_versions_path(customer_id, entity),
                params: { version_id: v.id },
                form: { data: { turbo_confirm: "Create a new version from v#{v.version_number}? It becomes the new default." } },
                class: "btn btn-tertiary btn-sm", data: { fork_version: v.version_number } do %>
            Create new version from this
          <% end %>
        <% end %>
      </li>
    <% end %>
  </ul>

  <div class="hidden px-6 py-4 border-t border-border-subtle" data-entity-versions-target="diffPanel"></div>
</div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/components/entity_version_list_component_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/components/entity_version_list_component.* spec/components/entity_version_list_component_spec.rb
git commit -m "feat(entity-versioning): version list component"
```

---

### Task 7: `EntityVersionDiffComponent` (side-by-side)

**Files:**
- Create: `app/components/entity_version_diff_component.rb`
- Create: `app/components/entity_version_diff_component.html.erb`
- Test: `spec/components/entity_version_diff_component_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe EntityVersionDiffComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer, description: "") }

  before do
    entity.update!(description: "now set",
                   property_schema: [{ "name" => "Phone", "name_slug" => "phone", "html_type" => "tel" }].to_json)
  end

  it "renders two columns and marks added/changed rows" do
    a = entity.entity_versions.find_by!(version_number: 1)
    b = entity.entity_versions.find_by!(version_number: 2)
    diff = Entities::VersionDiff.call(a, b)
    render_inline(described_class.new(entity: entity, version_a: a, version_b: b, diff: diff))

    expect(page).to have_text("Version 1")
    expect(page).to have_text("Version 2")
    # responsive two-column container
    expect(page).to have_css(".md\\:grid-cols-2")
    # an added attribute marker
    expect(page).to have_css("[data-diff-status='added']", text: /phone/i)
    # a changed meta field
    expect(page).to have_css("[data-diff-status='changed']", text: /description/i)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/components/entity_version_diff_component_spec.rb`
Expected: FAIL — missing constant.

- [ ] **Step 3: Write the component class**

```ruby
# frozen_string_literal: true

class EntityVersionDiffComponent < ApplicationComponent
  STATUS_CLASSES = {
    added:   "bg-emerald-50 text-emerald-800",
    removed: "bg-rose-50 text-rose-800 line-through",
    changed: "bg-amber-50 text-amber-900",
    same:    "text-text-secondary"
  }.freeze

  def initialize(entity:, version_a:, version_b:, diff:)
    @entity = entity
    @version_a = version_a
    @version_b = version_b
    @diff = diff
  end

  attr_reader :entity, :version_a, :version_b, :diff

  def status_class(status) = STATUS_CLASSES[status] || STATUS_CLASSES[:same]

  # Render a value for display; collapses hashes/arrays to compact JSON.
  def show(value)
    return "—" if value.nil? || value == "" || value == [] || value == {}
    value.is_a?(String) ? value : value.to_json
  end

  def attr_label(item)
    src = item[:b] || item[:a] || {}
    src["display_label"].presence || src["name"].presence || item[:key]
  end
end
```

- [ ] **Step 4: Write the template**

`app/components/entity_version_diff_component.html.erb`:

```erb
<div class="space-y-6">
  <div class="grid grid-cols-2 gap-4 text-sm font-semibold text-text-primary">
    <div>Version <%= version_a.version_number %></div>
    <div>Version <%= version_b.version_number %><% if version_b.is_default %> <span class="badge badge-success">Default</span><% end %></div>
  </div>

  <%# Meta scalars %>
  <section>
    <h4 class="text-caption uppercase tracking-wide mb-2">Details</h4>
    <div class="space-y-1">
      <% diff[:meta].each do |m| %>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-2 rounded px-2 py-1 <%= status_class(m[:status]) %>"
             data-diff-status="<%= m[:status] %>">
          <div><span class="text-text-muted"><%= m[:field] %>:</span> <%= show(m[:a]) %></div>
          <div><span class="text-text-muted"><%= m[:field] %>:</span> <%= show(m[:b]) %></div>
        </div>
      <% end %>
    </div>
  </section>

  <%# Attributes / Associations / Groups %>
  <% [["Attributes", diff[:attributes]], ["Associations", diff[:associations]], ["Groups", diff[:groups]]].each do |label, items| %>
    <section>
      <h4 class="text-caption uppercase tracking-wide mb-2"><%= label %></h4>
      <% if items.empty? %>
        <p class="text-caption">—</p>
      <% else %>
        <div class="space-y-1">
          <% items.each do |item| %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-2 rounded px-2 py-1 <%= status_class(item[:status]) %>"
                 data-diff-status="<%= item[:status] %>">
              <div><%= item[:status] == :added ? "—" : attr_label(item) %></div>
              <div>
                <%= item[:status] == :removed ? "—" : attr_label(item) %>
                <% if item[:status] == :changed %>
                  <ul class="mt-1 text-xs text-text-muted">
                    <% item[:field_changes].each do |c| %>
                      <li><%= c[:field] %>: <%= show(c[:a]) %> → <%= show(c[:b]) %></li>
                    <% end %>
                  </ul>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </section>
  <% end %>
</div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/components/entity_version_diff_component_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/components/entity_version_diff_component.* spec/components/entity_version_diff_component_spec.rb
git commit -m "feat(entity-versioning): side-by-side diff component"
```

---

### Task 8: Stimulus controller + show-page integration

**Files:**
- Create: `app/javascript/controllers/entity_versions_controller.js`
- Modify: `app/views/admin/maintenance/entities/show.html.erb` (add the panel near the end, before closing the wrapper `</div>`)

- [ ] **Step 1: Write the Stimulus controller**

```javascript
import { Controller } from "@hotwired/stimulus"

// Manages two-version selection and fetching the side-by-side diff.
export default class extends Controller {
  static targets = ["select", "compareBtn", "diffPanel"]
  static values  = { diffUrl: String }

  toggleSelect() {
    const checked = this.selectTargets.filter(c => c.checked)
    // Keep at most two selections (drop the oldest).
    if (checked.length > 2) checked[0].checked = false
    const count = this.selectTargets.filter(c => c.checked).length
    if (this.hasCompareBtnTarget) this.compareBtnTarget.disabled = count !== 2
  }

  async compare(event) {
    event.preventDefault()
    const picked = this.selectTargets.filter(c => c.checked).map(c => parseInt(c.value, 10))
    if (picked.length !== 2) return
    const [a, b] = picked.sort((x, y) => x - y)
    const url = `${this.diffUrlValue}?a=${a}&b=${b}`
    const resp = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!resp.ok) return
    this.diffPanelTarget.innerHTML = await resp.text()
    this.diffPanelTarget.classList.remove("hidden")
  }
}
```

- [ ] **Step 2: Integrate the panel into the show page**

In `app/views/admin/maintenance/entities/show.html.erb`, add before the final closing `</div>` of the `data-controller="entity-form"` wrapper, and only for non-bridge entities:

```erb
  <% unless @entity.bridge_entity? %>
    <div class="mt-6">
      <%= render EntityVersionListComponent.new(entity: @entity, customer_id: current_customer_id) %>
    </div>
  <% end %>
```

- [ ] **Step 3: Rebuild assets and smoke-test (manual / release-engineer)**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` (release-engineer task), open an entity show page, verify the Versions panel lists versions, Compare renders a side-by-side diff, and "Create new version from this" forks + reloads with the new default. (No headless Chrome here — covered by request/component specs; manual smoke optional.)

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/entity_versions_controller.js app/views/admin/maintenance/entities/show.html.erb
git commit -m "feat(entity-versioning): versions panel + compare stimulus controller"
```

---

### Task 9: Full regression + isolation sweep

**Files:** none (verification task)

- [ ] **Step 1: Run the entity-related suite + all new specs**

Run:
```bash
bundle exec rspec \
  spec/models/entity_version_spec.rb \
  spec/models/concerns/entity_versioning_spec.rb \
  spec/services/entities/version_diff_spec.rb \
  spec/requests/maintenance/entity_versions_spec.rb \
  spec/components/entity_version_list_component_spec.rb \
  spec/components/entity_version_diff_component_spec.rb \
  spec/models/entity_spec.rb \
  spec/requests/maintenance/entities_spec.rb \
  spec/models/concerns/bridge_entity_management_spec.rb
```
Expected: all PASS.

- [ ] **Step 2: Run the broader suite (cross-cutting model concern)**

Run: `bundle exec rspec` (or, if too slow, `spec/models spec/requests spec/services spec/components`).
Expected: green. Investigate any failure caused by the new `after_commit` hook (e.g., factories that create many entities → ensure no version spam breaks counts elsewhere).

- [ ] **Step 3: Commit any fixups**

```bash
git add -A && git commit -m "test(entity-versioning): regression sweep fixups"
```

---

## Self-Review

**Spec coverage:**
- Always-on snapshot on change → Task 3 (concern, `record_version_if_changed`).
- Skip bridge / no-op → Task 3 tests.
- Default = live entity; newest is default → Task 3 (`create_version_snapshot!` flips default; fork rewrites columns).
- Diff any two versions, side-by-side → Task 4 (service) + Task 7 (component).
- Fork-from-old becomes default → Task 3 (`restore_as_new_version!`) + Task 5 (`create`).
- Admin-only + tenant isolation → Task 5 (controller via `Entity.for_current_customer`, RouteAuthorization; request spec covers member-forbidden + cross-tenant 404).
- Retention 50 → Task 3.
- Migration + backfill → Task 1.
- UI on show page → Task 6/7/8.

**Placeholder scan:** none — all steps contain concrete code/commands.

**Type/name consistency:** `entity_versions`, `snapshot_json`, `definition_snapshot`, `create_version_snapshot!`, `restore_as_new_version!`, `Entities::VersionDiff.call`, component names, and the `entity-versions` Stimulus identifier are used consistently across tasks. The controller `diff` HTML branch references `Entities::VersionDiffComponent` — note that the *component constant* is `EntityVersionDiffComponent` (Rails top-level), so in Task 5 the controller must render `EntityVersionDiffComponent`, not a namespaced one. **Fix applied:** in Task 5 controller, change `Entities::VersionDiffComponent` → `EntityVersionDiffComponent`.

**Known coupling:** Task 5's `diff` HTML format depends on Task 7's component. Implement 5 (JSON path green), then 6/7, then revisit 5's HTML branch. Order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9.
