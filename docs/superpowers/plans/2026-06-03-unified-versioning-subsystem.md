# Unified Versioning Subsystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract one reusable versioning subsystem (model concerns + base controller + generic ViewComponent + generic Stimulus controller) and bring the Entities list and Pages list to full flowchart-parity versioning, retiring the divergent entity/page version UIs.

**Architecture:** Two model concerns (`Versionable` for parents, `VersionRecord` for version rows) carry all shared logic. An abstract `Admin::Maintenance::BaseVersionsController` carries the JSON API; three thin subclasses configure it. A single `VersionsModalComponent` + `versions` Stimulus controller drive the UI on all three list pages, parameterized by a `resource` value.

**Tech Stack:** Rails 8.1, ViewComponent, StimulusJS, TailwindCSS, RSpec. SQLite (test) / Postgres (prod) — note the FK `on_delete: :nullify` is enforced in app code because the SQLite schema dumper drops the action.

**Spec:** `docs/superpowers/specs/2026-06-03-unified-versioning-subsystem-design.md`

**Reference (the gold-standard implementation to generalize):**
- `app/models/flowchart.rb:97-232` (`display_default_version`, `create_version_snapshot!`)
- `app/models/flowchart_version.rb`
- `app/controllers/admin/maintenance/flowchart_versions_controller.rb`
- `app/components/flowchart_versions_modal_component.html.erb`
- `app/javascript/controllers/flowchart_versions_controller.js`
- `app/javascript/flowchart/version_diff.js`
- `app/views/admin/maintenance/flowcharts/index.html.erb`

---

## Task 1: `VersionRecord` concern (shared version-row behavior)

**Files:**
- Create: `app/models/concerns/version_record.rb`
- Modify: `app/models/flowchart_version.rb`, `app/models/entity_version.rb`, `app/models/page_version.rb`
- Test: `spec/models/concerns/version_record_spec.rb`

- [ ] **Step 1: Write the concern**

```ruby
# frozen_string_literal: true

# Shared behavior for version-snapshot rows (FlowchartVersion, EntityVersion,
# PageVersion). Each version belongs to a parent, carries a monotonically
# increasing `version_number` unique per parent, an optional self-referential
# `based_on_version_id` (lineage), and a JSON snapshot stored in a column that
# differs per resource. `acts_as_version` wires it all up.
module VersionRecord
  extend ActiveSupport::Concern

  class_methods do
    # parent:  association name to the owning record (e.g. :flowchart)
    # payload: column holding the JSON snapshot (e.g. :configuration or :snapshot)
    def acts_as_version(parent:, payload:)
      self.version_parent_name = parent
      self.version_payload_column = payload

      belongs_to parent
      belongs_to :based_on_version, class_name: name, optional: true

      validates payload, presence: true
      validates :version_number, presence: true,
                                 uniqueness: { scope: :"#{parent}_id" }

      scope :ordered, -> { order(created_at: :desc, version_number: :desc) }
      scope :recent,  -> { ordered.limit(50) }
    end
  end

  included do
    class_attribute :version_parent_name, :version_payload_column, instance_writer: false
  end

  # Uniform accessor for the snapshot regardless of underlying column name, so
  # the controller JSON contract is identical across resources.
  def payload
    public_send(self.class.version_payload_column)
  end

  def based_on_version_number
    based_on_version&.version_number
  end
end
```

- [ ] **Step 2: Apply to the three version models**

`app/models/flowchart_version.rb`:
```ruby
# frozen_string_literal: true

class FlowchartVersion < ApplicationRecord
  include VersionRecord
  acts_as_version parent: :flowchart, payload: :configuration
end
```

`app/models/page_version.rb`:
```ruby
# frozen_string_literal: true

class PageVersion < ApplicationRecord
  include VersionRecord
  acts_as_version parent: :page, payload: :configuration
end
```

`app/models/entity_version.rb` — open the file first; keep any existing helpers (e.g. `snapshot_json`), replace the associations/validations/scopes block with:
```ruby
  include VersionRecord
  acts_as_version parent: :entity, payload: :snapshot
```
Remove the now-defunct `is_default`-related code from this model (the parent FK is the source of truth after Task 3).

- [ ] **Step 3: Spec the concern**

```ruby
require "rails_helper"

RSpec.describe VersionRecord do
  let(:customer) { create(:customer) }

  describe "FlowchartVersion" do
    let(:flowchart) { create(:flowchart, customer: customer) }

    it "validates version_number uniqueness per parent" do
      flowchart.create_version_snapshot!(description: "a")
      dup = flowchart.flowchart_versions.build(
        configuration: flowchart.configuration, version_number: 1, customer_id: customer.id)
      expect(dup).not_to be_valid
    end

    it "exposes payload uniformly" do
      v = flowchart.create_version_snapshot!(description: "a")
      expect(v.payload).to eq(flowchart.configuration)
    end

    it "exposes based_on_version_number" do
      v1 = flowchart.create_version_snapshot!(description: "a")
      v2 = flowchart.create_version_snapshot!(description: "b", based_on_version_id: v1.id)
      expect(v2.based_on_version_number).to eq(v1.version_number)
    end

    it "ordered scope returns newest first" do
      flowchart.create_version_snapshot!(description: "a")
      flowchart.create_version_snapshot!(description: "b")
      expect(flowchart.flowchart_versions.ordered.first.version_number).to eq(2)
    end
  end
end
```

- [ ] **Step 4: Run** `bundle exec rspec spec/models/concerns/version_record_spec.rb` → PASS.

- [ ] **Step 5: Commit** (skip — repo policy: no commits on master; leave staged for user).

---

## Task 2: `Versionable` concern (shared parent behavior)

**Files:**
- Create: `app/models/concerns/versionable.rb`
- Test: `spec/models/concerns/versionable_spec.rb`

- [ ] **Step 1: Write the concern.** This is the generalization of `Flowchart#create_version_snapshot!` + `display_default_version`, plus the default-pointer management that the flowchart controller currently does inline, plus the restore-as-new orchestration.

```ruby
# frozen_string_literal: true

# Shared versioning behavior for parents (Flowchart, Entity, Page).
#
# Each parent has a `default_version_id` FK (the published/current version) and
# a has_many to its version rows. `acts_as_versionable` configures which
# association holds the versions and how to read/write the snapshot payload.
#
# Snapshot reading/writing is abstracted because single-column resources
# (flowchart/page `configuration`) differ from Entity, whose definition spans
# many columns and is serialized via `definition_snapshot`.
module Versionable
  extend ActiveSupport::Concern

  MAX_VERSIONS = 50

  class_methods do
    # reflection:    has_many name holding versions (e.g. :flowchart_versions)
    # version_class: class name string (e.g. "FlowchartVersion")
    # snapshot:      column read+written directly (single-column resources)
    # snapshot_reader/snapshot_writer: method names for multi-column resources
    #   reader returns the JSON string to store; writer takes the JSON string,
    #   assigns it onto the record, and is expected to be followed by save.
    def acts_as_versionable(reflection:, version_class:,
                            snapshot: nil, snapshot_reader: nil, snapshot_writer: nil)
      self.versionable_options = {
        reflection: reflection,
        snapshot_reader: snapshot_reader || snapshot,
        snapshot_writer: snapshot_writer
      }
      self.versionable_snapshot_column = snapshot

      has_many reflection, dependent: :destroy
      belongs_to :default_version, class_name: version_class, optional: true
    end
  end

  included do
    class_attribute :versionable_options, :versionable_snapshot_column, instance_writer: false
  end

  # The versions has_many relation, by configured name.
  def versions_relation
    public_send(self.class.versionable_options[:reflection])
  end

  # The "current" version on the list: explicit default else most recent.
  # Uses the preloaded association when loaded (no N+1 on list pages).
  def display_default_version
    return default_version if default_version
    rel = versions_relation
    rel.loaded? ? rel.max_by(&:version_number) : rel.ordered.first
  end

  # JSON string to store in a new snapshot.
  def current_snapshot
    reader = self.class.versionable_options[:snapshot_reader]
    public_send(reader)
  end

  # Apply a snapshot payload onto the record AND persist it. Single-column
  # resources update the column directly; multi-column resources delegate to a
  # configured writer that assigns + saves.
  def apply_version_snapshot!(payload)
    if (writer = self.class.versionable_options[:snapshot_writer])
      public_send(writer, payload)
    else
      update!(self.class.versionable_snapshot_column => payload)
    end
  end

  # Create a snapshot of the current state and make it the default version.
  # Lineage precedence: a valid explicit id wins, else the current default.
  # Concurrency: lock the parent row + retry the narrow RecordNotUnique race
  # (no-op lock on SQLite). Prune to MAX_VERSIONS, clearing inbound FK pointers
  # first so the trim never violates a RESTRICT FK on SQLite.
  def create_version_snapshot!(description: nil, based_on_version_id: nil, set_default: true)
    rel = versions_relation
    based_on_id =
      if based_on_version_id.present? && rel.exists?(id: based_on_version_id)
        based_on_version_id
      else
        default_version_id
      end

    version = nil
    attempts = 0
    begin
      attempts += 1
      transaction do
        lock! if persisted?
        next_number = rel.maximum(:version_number).to_i + 1
        version = rel.create!(
          customer_id: customer_id,
          version_number: next_number,
          description: description,
          based_on_version_id: based_on_id,
          self.class::VERSION_PAYLOAD_KEY => current_snapshot
        )
      end
    rescue ActiveRecord::RecordNotUnique
      retry if attempts < 3
      raise
    end

    update_column(:default_version_id, version.id) if set_default
    prune_versions!
    version
  end

  # Restore-as-new: snapshot the live state ("Before restore"), apply the chosen
  # version, snapshot again ("Restored from vN") with lineage, set as default.
  # Runs in a single transaction so a failure leaves the parent untouched.
  def restore_as_new!(version)
    transaction do
      create_version_snapshot!(description: "Before restore to v#{version.version_number}")
      apply_version_snapshot!(version.payload)
      create_version_snapshot!(description: "Restored from v#{version.version_number}",
                               based_on_version_id: version.id)
    end
  end

  private

  def prune_versions!
    rel = versions_relation
    old = rel.ordered.offset(MAX_VERSIONS)
    return unless old.exists?
    pruned_ids = old.ids
    update_column(:default_version_id, nil) if default_version_id.in?(pruned_ids)
    rel.where(based_on_version_id: pruned_ids).update_all(based_on_version_id: nil)
    old.destroy_all
  end
end
```

Each version model declares the payload key constant so the concern can build the create attributes generically. Add to each version model (Task 1 files):
```ruby
  VERSION_PAYLOAD_KEY = :configuration   # FlowchartVersion, PageVersion
  VERSION_PAYLOAD_KEY = :snapshot        # EntityVersion
```

- [ ] **Step 2: Spec the concern against Flowchart** (the simplest single-column case):

```ruby
require "rails_helper"

RSpec.describe Versionable do
  let(:customer) { create(:customer) }
  let(:flowchart) { create(:flowchart, customer: customer) }

  it "numbers versions monotonically and sets default" do
    v1 = flowchart.create_version_snapshot!(description: "a")
    v2 = flowchart.create_version_snapshot!(description: "b")
    expect([v1.version_number, v2.version_number]).to eq([1, 2])
    expect(flowchart.reload.default_version_id).to eq(v2.id)
  end

  it "display_default_version prefers explicit default" do
    flowchart.create_version_snapshot!(description: "a")
    v2 = flowchart.create_version_snapshot!(description: "b")
    flowchart.update_column(:default_version_id, v2.id)
    expect(flowchart.reload.display_default_version.id).to eq(v2.id)
  end

  it "records lineage from explicit id" do
    v1 = flowchart.create_version_snapshot!(description: "a")
    v2 = flowchart.create_version_snapshot!(description: "b", based_on_version_id: v1.id)
    expect(v2.based_on_version_id).to eq(v1.id)
  end

  it "prunes to MAX_VERSIONS and nullifies pruned pointers" do
    55.times { |i| flowchart.create_version_snapshot!(description: "v#{i}") }
    expect(flowchart.flowchart_versions.count).to eq(Versionable::MAX_VERSIONS)
  end

  it "restore_as_new! creates before+after snapshots and sets default" do
    v1 = flowchart.create_version_snapshot!(description: "first")
    original_config = flowchart.configuration
    flowchart.update!(configuration: flowchart.configuration) # no-op keeps draft
    flowchart.restore_as_new!(v1)
    versions = flowchart.flowchart_versions.ordered
    expect(versions.first.description).to eq("Restored from v#{v1.version_number}")
    expect(versions.first.based_on_version_id).to eq(v1.id)
    expect(flowchart.reload.default_version_id).to eq(versions.first.id)
  end
end
```

- [ ] **Step 3: Run** `bundle exec rspec spec/models/concerns/versionable_spec.rb` → PASS (after Task 3 wires Flowchart to the concern, run this again).

- [ ] **Step 4: Commit** (skip per repo policy).

---

## Task 3: Migrations + model wiring (parity for Entity & Page; Flowchart adopts concern)

**Files:**
- Create migrations under `db/migrate/`:
  - `add_default_version_to_entities`
  - `remove_is_default_from_entity_versions`
  - `add_default_version_to_pages`
  - `add_based_on_version_to_page_versions`
- Modify: `app/models/flowchart.rb`, `app/models/entity.rb`, `app/models/page.rb`,
  `app/models/concerns/entity_versioning.rb` (fold into Versionable / delete)
- Test: `spec/models/entity_spec.rb`, `spec/models/page_spec.rb` (extend)

- [ ] **Step 1: Migration — entities default_version + backfill.** Mirror `db/migrate/20260603083902_add_default_version_to_flowcharts.rb`.

```ruby
class AddDefaultVersionToEntities < ActiveRecord::Migration[8.1]
  def up
    add_reference :entities, :default_version, foreign_key: { to_table: :entity_versions, on_delete: :nullify }
    # Backfill: the version currently flagged is_default (or the latest) becomes the FK default.
    execute <<~SQL
      UPDATE entities SET default_version_id = (
        SELECT ev.id FROM entity_versions ev
        WHERE ev.entity_id = entities.id
        ORDER BY ev.is_default DESC, ev.version_number DESC
        LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :entities, :default_version
  end
end
```

- [ ] **Step 2: Migration — drop entity_versions.is_default** (run AFTER the backfill migration):

```ruby
class RemoveIsDefaultFromEntityVersions < ActiveRecord::Migration[8.1]
  def up
    remove_index :entity_versions, :is_default if index_exists?(:entity_versions, :is_default)
    remove_column :entity_versions, :is_default
  end

  def down
    add_column :entity_versions, :is_default, :boolean, default: false, null: false
    add_index :entity_versions, :is_default
  end
end
```

- [ ] **Step 3: Migration — pages default_version + backfill:**

```ruby
class AddDefaultVersionToPages < ActiveRecord::Migration[8.1]
  def up
    add_reference :pages, :default_version, foreign_key: { to_table: :page_versions, on_delete: :nullify }
    execute <<~SQL
      UPDATE pages SET default_version_id = (
        SELECT pv.id FROM page_versions pv
        WHERE pv.page_id = pages.id
        ORDER BY pv.version_number DESC
        LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :pages, :default_version
  end
end
```

- [ ] **Step 4: Migration — page_versions.based_on_version_id:**

```ruby
class AddBasedOnVersionToPageVersions < ActiveRecord::Migration[8.1]
  def up
    add_reference :page_versions, :based_on_version,
                  foreign_key: { to_table: :page_versions, on_delete: :nullify }, index: true
  end

  def down
    remove_reference :page_versions, :based_on_version
  end
end
```

- [ ] **Step 5: Run migrations** `bin/rails db:migrate` then `bin/rails db:migrate RAILS_ENV=test` (or `db:test:prepare`). Expected: schema updates cleanly.

- [ ] **Step 6: Wire Flowchart to the concern.** In `app/models/flowchart.rb`: add `include Versionable`; replace lines 25-26 (`has_many :flowchart_versions` + `belongs_to :default_version`) and the `display_default_version` (97-100) and `create_version_snapshot!` (181-232) methods with:
```ruby
  include Versionable
  acts_as_versionable reflection: :flowchart_versions,
                      version_class: "FlowchartVersion",
                      snapshot: :configuration
```
Keep everything else. The concern now owns those methods.

- [ ] **Step 7: Wire Entity to the concern.** In `app/models/entity.rb`: remove `include EntityVersioning`. Add:
```ruby
  include Versionable
  acts_as_versionable reflection: :entity_versions,
                      version_class: "EntityVersion",
                      snapshot_reader: :definition_snapshot_json,
                      snapshot_writer: :apply_definition_snapshot!
```
Add these two helpers to Entity (port from the old `EntityVersioning` concern, `app/models/concerns/entity_versioning.rb:27-70`):
```ruby
  def definition_snapshot
    {
      "name" => name, "name_slug" => name_slug, "element_type" => element_type,
      "icon" => icon, "color" => color, "description" => description,
      "property_schema" => property_schema_json || [],
      "default_properties" => default_properties_json || {},
      "associations" => associations_json || [],
      "attribute_groups" => attribute_groups_json || [],
      "referenced_template" => referenced_template
    }
  end

  def definition_snapshot_json = definition_snapshot.to_json

  # Apply a stored snapshot onto the live columns, save (triggers bridge sync via
  # the controller), so the new state is what create_version_snapshot! captures.
  def apply_definition_snapshot!(payload)
    snap = JSON.parse(payload)
    assign_attributes(
      name: snap["name"], element_type: snap["element_type"], icon: snap["icon"],
      color: snap["color"], description: snap["description"],
      property_schema: snap["property_schema"].to_json,
      default_properties: snap["default_properties"].to_json,
      associations: snap["associations"].to_json,
      attribute_groups: snap["attribute_groups"].to_json,
      referenced_template: snap["referenced_template"]
    )
    save!
  end
```
Delete `app/models/concerns/entity_versioning.rb`.

- [ ] **Step 8: Wire Page to the concern.** In `app/models/page.rb`: remove the existing bespoke `create_version_snapshot!`/`rollback_to_version!`/`has_many :page_versions` and add:
```ruby
  include Versionable
  acts_as_versionable reflection: :page_versions,
                      version_class: "PageVersion",
                      snapshot: :configuration
```
(Read `app/models/page.rb` first to find and remove the exact bespoke methods.)

- [ ] **Step 9: Run** the concern specs plus model specs:
`bundle exec rspec spec/models/concerns/versionable_spec.rb spec/models/concerns/version_record_spec.rb spec/models/entity_spec.rb spec/models/page_spec.rb spec/models/flowchart_spec.rb`
→ PASS. Fix fallout (entity/page model specs that referenced auto-snapshot or `is_default` get rewritten per the stale-test policy — newest snapshot is now set via controller, not auto `after_commit`).

- [ ] **Step 10: Commit** (skip per repo policy).

---

## Task 4: `BaseVersionsController` + subclasses + routes

**Files:**
- Create: `app/controllers/admin/maintenance/base_versions_controller.rb`
- Rewrite: `app/controllers/admin/maintenance/flowchart_versions_controller.rb`,
  `entity_versions_controller.rb`, `page_versions_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/maintenance/flowchart_versions_spec.rb` (keep/extend),
  new `entity_versions_spec.rb`, `page_versions_spec.rb`

- [ ] **Step 1: Write the base controller** — generalize `flowchart_versions_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    # Abstract base for versioned-resource version history. Subclasses declare the
    # parent via `versioned_resource`. JSON contract is identical across resources
    # so one Stimulus controller drives all three list pages.
    class BaseVersionsController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_parent
      before_action :guard_write!,  only: %i[create default destroy]

      class_attribute :parent_finder, :parent_ivar

      def self.versioned_resource(finder:, ivar:)
        self.parent_finder = finder
        self.parent_ivar = ivar
      end

      # GET .../versions
      def index
        versions = parent.versions_relation.recent.includes(:based_on_version)
        render json: versions.map { |v| index_json(v) }
      end

      # GET .../versions/:id  (snapshot for client-side diff)
      def show
        v = parent.versions_relation.find(params[:id])
        render json: {
          id: v.id, version_number: v.version_number, description: v.description,
          created_at: v.created_at.iso8601, configuration: v.payload
        }
      end

      # POST .../versions  { version_id: }  (restore-as-new)
      def create
        version = parent.versions_relation.find(params.require(:version_id))
        parent.restore_as_new!(version)
        render json: { success: true, version_number: parent.versions_relation.maximum(:version_number) }
      end

      # PUT .../versions/:id/default
      def default
        version = parent.versions_relation.find(params[:id])
        parent.transaction do
          parent.apply_version_snapshot!(version.payload)
          parent.update_column(:default_version_id, version.id)
        end
        render json: { success: true, default_version_id: version.id, version_number: version.version_number }
      end

      # DELETE .../versions/:id
      def destroy
        version = parent.versions_relation.find(params[:id])
        if version.id == parent.default_version_id
          return render json: {
            error: "default_version_undeletable",
            message: "Cannot delete the default version. Set another version as default first."
          }, status: :unprocessable_entity
        end
        parent.transaction do
          parent.versions_relation.where(based_on_version_id: version.id).update_all(based_on_version_id: nil)
          version.destroy!
        end
        render json: { success: true, id: version.id }
      end

      private

      def parent
        instance_variable_get(parent_ivar)
      end

      def find_parent
        instance_variable_set(parent_ivar, instance_exec(&parent_finder))
      end

      def index_json(v)
        {
          id: v.id, version_number: v.version_number, description: v.description,
          created_at: v.created_at.iso8601,
          is_default: v.id == parent.default_version_id,
          based_on_version_number: v.based_on_version_number
        }
      end

      # Overridable in subclasses (flowchart enforces shared/draft guards).
      def guard_write!; end
    end
  end
end
```

- [ ] **Step 2: Flowchart subclass** — keep its existing guards and editor `edit`:

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartVersionsController < BaseVersionsController
      versioned_resource finder: -> { Flowchart.accessible.find(params[:flowchart_id]) },
                         ivar: :@flowchart

      # GET .../versions/:id/edit — open this version in the flowchart editor.
      def edit
        @version = @flowchart.flowchart_versions.find(params[:id])
        @flowchart.configuration = @version.configuration
        @based_on_version_id = @version.id
        @editing_version = @version
        render template: "admin/maintenance/flowcharts/edit"
      end

      private

      def guard_write!
        guard_shared_write! && guard_not_draft!
      end

      def guard_shared_write!
        return true unless @flowchart&.type_shared?
        return true if current_user&.platform_owner?
        render json: { error: "shared_flowchart_readonly" }, status: :forbidden
        false
      end

      def guard_not_draft!
        return true if @flowchart&.draft?
        render json: {
          error: "flowchart_not_draft",
          message: "Cannot modify versions while the flowchart is active. Deactivate to edit."
        }, status: :unprocessable_entity
        false
      end
    end
  end
end
```
(Note: `default`/`create` previously guarded `guard_not_draft!`; `destroy` did not. Keep delete unguarded by overriding `guard_write!` to only run draft/shared checks for `create`/`default` — set `before_action :guard_write!, only: %i[create default]` in the flowchart subclass if delete must stay allowed on active flowcharts. Verify against `spec/requests/maintenance/flowchart_versions_spec.rb` and preserve existing behavior.)

- [ ] **Step 3: Entity subclass:**

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class EntityVersionsController < BaseVersionsController
      versioned_resource finder: -> { Entity.for_current_customer.find(params[:entity_id]) },
                         ivar: :@entity

      # GET .../versions/:id/edit — open this version in the entity editor.
      def edit
        version = @entity.entity_versions.find(params[:id])
        redirect_to edit_admin_maintenance_entity_path(current_customer_id, @entity, version: version.id)
      end
    end
  end
end
```
(If the entity editor needs the snapshot seeded, pass `version` and have `EntitiesController#edit` load it; verify the editor supports it. Otherwise drop the `edit` action and the "Open" button falls back to the plain edit page.)

- [ ] **Step 4: Page subclass** — analogous, finder `Page.for_current_customer.find(params[:page_id])`, ivar `:@page`, `edit` redirects to `edit_admin_maintenance_page_path(..., version: version.id)`.

- [ ] **Step 5: Routes.** In `config/routes.rb`, replace the three `resources :versions` blocks (under flowcharts, entities, pages) with the identical shape:
```ruby
resources :versions, only: %i[index show create edit destroy],
          controller: "maintenance/<x>_versions" do
  member { put :default }
end
```
Remove: entity `collection { get :diff }`; page `member { post :restore }` + `collection { get :compare }`; the `resource :restoration` under pages (and its controller — Task 8).

- [ ] **Step 6: Request specs.** Keep `spec/requests/maintenance/flowchart_versions_spec.rb` green. Add `spec/requests/maintenance/entity_versions_spec.rb` and `page_versions_spec.rb` covering index/show/create/default/destroy, **cross-tenant 404**, and **default-deletion 422**. Example (entity):
```ruby
require "rails_helper"

RSpec.describe "Admin::Maintenance::EntityVersions", type: :request do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }
  before { sign_in_as_admin(customer) } # use the suite's existing auth helper

  it "lists versions as JSON" do
    entity.create_version_snapshot!(description: "v1")
    get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/versions", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).first["version_number"]).to eq(1)
  end

  it "blocks deleting the default version" do
    v = entity.create_version_snapshot!(description: "v1")
    delete "/#{customer.id}/admin/maintenance/entities/#{entity.id}/versions/#{v.id}.json"
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to eq("default_version_undeletable")
  end

  it "404s on another customer's entity" do
    other = create(:entity, customer: create(:customer))
    get "/#{customer.id}/admin/maintenance/entities/#{other.id}/versions", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 7: Run** `bundle exec rspec spec/requests/maintenance/` → PASS.

- [ ] **Step 8: Commit** (skip per repo policy).

---

## Task 5: Generic UI — `VersionsModalComponent` + `versions` Stimulus controller; refactor flowcharts/index

**Files:**
- Rename: `app/components/flowchart_versions_modal_component.rb` → `app/components/versions_modal_component.rb`
- Rename: `app/components/flowchart_versions_modal_component.html.erb` → `app/components/versions_modal_component.html.erb`
- Rename: `app/javascript/controllers/flowchart_versions_controller.js` → `app/javascript/controllers/versions_controller.js`
- Move: `app/javascript/flowchart/version_diff.js` → `app/javascript/versions/version_diff.js`
- Modify: `app/views/admin/maintenance/flowcharts/index.html.erb`
- Test: rename `spec/components/flowchart_versions_modal_component_spec.rb` → `versions_modal_component_spec.rb`

- [ ] **Step 1: Generalize the modal markup.** In the renamed `.html.erb`, replace every `flowchart-versions` token with `versions` (targets like `data-flowchart-versions-target=` → `data-versions-target=`, actions `flowchart-versions#x` → `versions#x`, the title id `flowchart-versions-title` → `versions-title`). No structural changes.

- [ ] **Step 2: Generalize the Stimulus controller.** In the renamed `versions_controller.js`:
  - Change `import { versionDiff } from "flowchart/version_diff"` → `from "versions/version_diff"`.
  - `static values = { customerId: String, resource: String }`.
  - Replace `_base()`:
```js
  _base() {
    return `/${this.customerIdValue}/admin/maintenance/${this.resourceValue}/${this.parentId}/versions`
  }
```
  - In `open`, read generic params: `this.parentId = params.id; this.parentName = params.name || "Item"`. Update the title assignment to `this.parentName`.
  - Replace every remaining `flowchart-versions` data-attribute name emitted in `_renderList`/`_renderDiff` template strings (e.g. `data-flowchart-versions-id-param` → `data-versions-id-param`, `click->flowchart-versions#...` → `click->versions#...`).
  - Keep `_refreshList()` targeting `turbo-frame#admin-table` (shared across all list pages).

- [ ] **Step 3: Rewire flowcharts/index.** Edit `app/views/admin/maintenance/flowcharts/index.html.erb`:
```erb
  <div data-controller="versions"
       data-versions-customer-id-value="<%= current_customer_id %>"
       data-versions-resource-value="flowcharts">
    <%= render AdminTableComponent.new(
    ...
    row_actions: ->(f) { [
      { label: "Versions", path: "#",
        data: { turbo: "false", action: "versions#open",
                "versions-id-param": f.id,
                "versions-name-param": f.name } },
      ... (Edit, Copy, Delete unchanged) ...
    ] },
    ...
    ) %>

    <%= render VersionsModalComponent.new %>
  </div>
```

- [ ] **Step 4: Confirm the `flowcharts` index controller** already preloads `:default_version, :flowchart_versions` and has the "Default Version" column (it does — `flowcharts_controller.rb`). No change needed; verify.

- [ ] **Step 5: Run** the component spec + flowchart request specs + rebuild assets and smoke-load the flowcharts list. `bundle exec rspec spec/components/versions_modal_component_spec.rb`.

- [ ] **Step 6: Commit** (skip per repo policy).

---

## Task 6: Wire Entities list to the shared versioning UI

**Files:**
- Modify: `app/controllers/admin/maintenance/entities_controller.rb` (index column + includes; manual snapshot on create/update)
- Modify: `app/views/admin/maintenance/entities/index.html.erb`
- Test: extend `spec/requests/entities_spec.rb`

- [ ] **Step 1: Add the Default Version column + preload** in `EntitiesController#index`. Read the action first; add to its `@columns` array (mirror flowcharts):
```ruby
  { key: :default_version, label: "Default Version", type: :text, sortable: false,
    cell: ->(e) { (v = e.display_default_version) ? "v#{v.version_number}" : "—" } },
```
and add `.includes(:default_version, :entity_versions)` to the index scope.

- [ ] **Step 2: Snapshot on definition change.** Since entities no longer auto-snapshot (`after_commit` removed in Task 3), call `create_version_snapshot!` in `EntitiesController#create` and `#update` after a successful save when the definition changed (mirror `FlowchartsController#update`):
```ruby
  # after successful update, inside the same flow that syncs bridge entities:
  if entity.saved_changes.keys.intersect?(EntityVersion::VERSIONED_COLUMNS) || created
    entity.create_version_snapshot!(description: "Manual save",
                                    based_on_version_id: params[:based_on_version_id])
  end
```
Define `EntityVersion::VERSIONED_COLUMNS` (port the list from the deleted concern) on `EntityVersion`, or guard simply with "snapshot differs from latest". Keep bridge entities unversioned (skip when `entity.is_bridge_entity?`).

- [ ] **Step 3: Rewire entities/index.html.erb.** Wrap the `AdminTableComponent` in the `versions` controller div (resource `"entities"`), add the "Versions" row action (passing `id`/`name`), and render `VersionsModalComponent` once — exactly as flowcharts/index in Task 5 Step 3, substituting entity paths/labels.

- [ ] **Step 4: Spec** — extend `spec/requests/entities_spec.rb`: creating then updating an entity definition produces 2 versions; the list page renders the "Default Version" column and a "Versions" action.

- [ ] **Step 5: Run** `bundle exec rspec spec/requests/entities_spec.rb` → PASS.

- [ ] **Step 6: Commit** (skip per repo policy).

---

## Task 7: Wire Pages list to the shared versioning UI

**Files:**
- Modify: `app/controllers/admin/maintenance/pages_controller.rb` (index column + includes; manual snapshot retained on update)
- Modify: `app/views/admin/maintenance/pages/index.html.erb`
- Test: extend `spec/requests/pages_spec.rb`

- [ ] **Step 1: Add the Default Version column + preload** in `PagesController#index` (mirror flowcharts), add `.includes(:default_version, :page_versions)`.

- [ ] **Step 2: Snapshot on config change.** Pages already snapshot on update; ensure it now uses the shared `create_version_snapshot!` (Task 3 makes Page use the concern) and that the new version becomes default. In `PagesController#create`/`#update`, after a successful save where `configuration` changed:
```ruby
  page.create_version_snapshot!(description: "Manual save",
                                based_on_version_id: params[:based_on_version_id]) if page.saved_change_to_configuration?
```
Remove the old `rollback_to_version!` call sites (restore is now the versions `create` endpoint).

- [ ] **Step 3: Rewire pages/index.html.erb.** Replace the existing `"Versions"` row action (which links to the retired HTML index) with the modal trigger, wrap in the `versions` controller div (resource `"pages"`), render `VersionsModalComponent`. Keep Edit/Copy/Preview/Delete actions. Pattern identical to Task 5 Step 3.

- [ ] **Step 4: Spec** — extend `spec/requests/pages_spec.rb`: updating a page config creates a version + sets default; list renders the column + "Versions" action; the old `/versions` HTML route is gone (the modal uses JSON).

- [ ] **Step 5: Run** `bundle exec rspec spec/requests/pages_spec.rb` → PASS.

- [ ] **Step 6: Commit** (skip per repo policy).

---

## Task 8: Retire obsolete code

**Files (delete):**
- `app/components/entity_version_list_component.rb` (+ `.html.erb`)
- `app/components/entity_version_diff_component.rb` (+ `.html.erb`)
- `app/javascript/controllers/entity_versions_controller.js`
- `app/services/entities/version_diff.rb`
- `app/services/page_version_diff.rb`
- `app/views/admin/maintenance/page_versions/` (HTML index/show templates)
- `app/views/admin/maintenance/page_versions/compare.*`
- `app/controllers/admin/maintenance/page_restorations_controller.rb`
- `app/models/concerns/entity_versioning.rb` (done in Task 3)
- Their specs: `spec/components/entity_version_*`, `spec/services/entities/version_diff_spec.rb`, `spec/services/page_version_diff_spec.rb`

- [ ] **Step 1: Grep for references** before deleting:
`grep -rn "EntityVersionListComponent\|EntityVersionDiffComponent\|entity-versions\|Entities::VersionDiff\|PageVersionDiff\|rollback_to_version\|page_restoration\|entity_versioning\|EntityVersioning" app spec config`
Remove each reference (Stimulus registry, view renders, controller calls, routes).

- [ ] **Step 2: Delete the files** listed above.

- [ ] **Step 3: Remove the `restoration` route** under pages and any `entity_versions#diff` / `page_versions#restore|compare` route remnants (done in Task 4 Step 5 — verify).

- [ ] **Step 4: Run** `grep` again → zero hits. Run `bin/rails routes | grep versions` → only the unified routes remain for all three resources.

- [ ] **Step 5: Commit** (skip per repo policy).

---

## Task 9: Full verification

- [ ] **Step 1: Rebuild assets & restart dev server** (AGENTS.md sequence):
`rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`

- [ ] **Step 2: Smoke-test** all three list pages and the modal:
  - `/81721200/admin/maintenance/flowcharts` — Default Version column + Versions modal open/diff/set-default/delete.
  - `/81721200/admin/maintenance/entities` — same.
  - `/81721200/admin/maintenance/pages` — same.

- [ ] **Step 3: Full RSpec suite** (cross-cutting change touching auth/tenant/three modules):
`bundle exec rspec`
Expected: green. Fix any fallout per the stale-test policy (rewrite specs that asserted the retired behavior; do not revert production to satisfy a stale test).

- [ ] **Step 4: Hand off for review** (Task 10).

---

## Self-Review (completed during authoring)

- **Spec coverage:** data-model parity → Tasks 1-3; shared concerns → Tasks 1-2; shared controller + routes → Task 4; shared UI → Task 5; entities/pages wiring → Tasks 6-7; retire divergent UIs → Task 8; full-suite testing → Task 9. All spec sections mapped.
- **Type consistency:** `versions_relation`, `current_snapshot`, `apply_version_snapshot!`, `restore_as_new!`, `display_default_version`, `payload`, `based_on_version_number`, `VERSION_PAYLOAD_KEY` used consistently across Tasks 1-7. JSON contract (`id, version_number, description, created_at, is_default, based_on_version_number` / `configuration`) matches the unchanged Stimulus controller.
- **Open verification points flagged inline:** flowchart delete-guard scope (Task 4 Step 2), entity/page editor seeding from a version (Task 4 Steps 3-4), exact bespoke methods to remove from `page.rb` (Task 3 Step 8). Implementers must read those files before editing.
