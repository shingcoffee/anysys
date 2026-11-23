# Flowchart Default Version & Version-Based Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the flowcharts list show the current default version, let admins set any version as the default (publish/restore), and let admins open a specific version in the builder editor in a new tab where saving creates a new version tagged with based-on lineage.

**Architecture:** Add `flowcharts.default_version_id` (the published/live version) and `flowchart_versions.based_on_version_id` (lineage). "Set as default" publishes a version's config to the live flowchart and repoints the pointer (draft-only, owner-only for shared). The version-view tab reuses the existing editor view with the version's config injected in-memory; the canvas save PATCH carries `based_on_version_id`, which the snapshot records, and the new snapshot becomes the default.

**Tech Stack:** Rails 8.1, ActiveRecord, RSpec, ViewComponent, StimulusJS, TailwindCSS.

**Spec:** `docs/superpowers/specs/2026-06-03-flowchart-default-version-design.md`

---

### Task 1: Migrations + model associations

**Files:**
- Create: `db/migrate/<ts>_add_default_version_to_flowcharts.rb`
- Create: `db/migrate/<ts2>_add_based_on_version_to_flowchart_versions.rb`
- Modify: `app/models/flowchart.rb`
- Modify: `app/models/flowchart_version.rb`
- Test: `spec/models/flowchart_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/flowchart_spec.rb` (inside the top-level `describe Flowchart`):

```ruby
describe "default version + based-on lineage" do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }

  it "belongs to an optional default_version" do
    flowchart.create_version_snapshot!(description: "v1")
    v = flowchart.flowchart_versions.ordered.first
    flowchart.update_column(:default_version_id, v.id)
    expect(flowchart.reload.default_version).to eq(v)
  end

  it "records based_on_version_id when it belongs to this flowchart" do
    flowchart.create_version_snapshot!(description: "v1")
    parent = flowchart.flowchart_versions.ordered.first
    child = flowchart.create_version_snapshot!(description: "v2", based_on_version_id: parent.id)
    expect(child.based_on_version_id).to eq(parent.id)
  end

  it "drops a based_on_version_id that belongs to another flowchart" do
    other = create(:flowchart, :simple, :draft, customer: customer, entity: entity)
    other.create_version_snapshot!
    foreign = other.flowchart_versions.ordered.first
    child = flowchart.create_version_snapshot!(description: "v1", based_on_version_id: foreign.id)
    expect(child.based_on_version_id).to be_nil
  end

  it "display_default_version falls back to the latest snapshot when no default set" do
    flowchart.create_version_snapshot!(description: "v1")
    flowchart.create_version_snapshot!(description: "v2")
    latest = flowchart.flowchart_versions.ordered.first
    expect(flowchart.display_default_version).to eq(latest)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "default version + based-on lineage"`
Expected: FAIL (no `default_version` association / unknown column).

- [ ] **Step 3: Write the migrations**

`db/migrate/<ts>_add_default_version_to_flowcharts.rb`:

```ruby
# frozen_string_literal: true

class AddDefaultVersionToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :default_version_id, :bigint
    add_index  :flowcharts, :default_version_id
    add_foreign_key :flowcharts, :flowchart_versions, column: :default_version_id
  end
end
```

`db/migrate/<ts2>_add_based_on_version_to_flowchart_versions.rb`:

```ruby
# frozen_string_literal: true

class AddBasedOnVersionToFlowchartVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :flowchart_versions, :based_on_version_id, :bigint
    add_index  :flowchart_versions, :based_on_version_id
    add_foreign_key :flowchart_versions, :flowchart_versions, column: :based_on_version_id
  end
end
```

Generate timestamps with real filenames (use `bin/rails g migration` names or copy the pattern of existing migrations). Then run: `bin/rails db:migrate`.

- [ ] **Step 4: Update the models**

In `app/models/flowchart.rb`, add the association near the other associations (after `has_many :flowchart_versions, dependent: :destroy`):

```ruby
  belongs_to :default_version, class_name: "FlowchartVersion", optional: true
```

Add this public method (e.g. just after `def diagram ... end`):

```ruby
  # The version shown as "current" on the list. Explicit default if set,
  # else the most recent snapshot (uses the preloaded association to avoid N+1).
  def display_default_version
    default_version || flowchart_versions.max_by(&:version_number)
  end
```

Replace `create_version_snapshot!` signature + insert block to accept and sanitize `based_on_version_id`, and return the created version:

```ruby
  def create_version_snapshot!(description: nil, based_on_version_id: nil)
    based_on_id = based_on_version_id.presence &&
                  (flowchart_versions.exists?(id: based_on_version_id) ? based_on_version_id : nil)
    version = nil
    attempts = 0
    begin
      attempts += 1
      transaction do
        lock! if persisted?
        next_version = flowchart_versions.maximum(:version_number).to_i + 1
        version = flowchart_versions.create!(
          customer_id: customer_id,
          configuration: configuration,
          version_number: next_version,
          description: description,
          based_on_version_id: based_on_id
        )
      end
    rescue ActiveRecord::RecordNotUnique
      retry if attempts < 3
      raise
    end

    old_versions = flowchart_versions.ordered.offset(50)
    old_versions.destroy_all if old_versions.exists?
    version
  end
```

In `app/models/flowchart_version.rb`, add:

```ruby
  belongs_to :based_on_version, class_name: "FlowchartVersion", optional: true
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/models/flowchart_spec.rb -e "default version + based-on lineage"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate app/models/flowchart.rb app/models/flowchart_version.rb db/schema.rb spec/models/flowchart_spec.rb
git commit -m "feat(flowcharts): default_version + based_on_version columns and model support"
```

---

### Task 2: Routes for edit + set-default

**Files:**
- Modify: `config/routes.rb:216`

- [ ] **Step 1: Update the route**

Replace line 216:

```ruby
          resources :versions, only: %i[index show create], controller: "maintenance/flowchart_versions"
```

with:

```ruby
          resources :versions, only: %i[index show create edit], controller: "maintenance/flowchart_versions" do
            member { put :default }
          end
```

- [ ] **Step 2: Verify the routes exist**

Run: `bin/rails routes -g versions | grep -E "edit|default"`
Expected: rows for `edit_..._version` (GET `.../versions/:id/edit`) and `default_..._version` (PUT `.../versions/:id/default`).

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat(flowcharts): routes for version edit + set-default"
```

---

### Task 3: `flowchart_versions#default` (publish/restore + repoint)

**Files:**
- Modify: `app/controllers/admin/maintenance/flowchart_versions_controller.rb`
- Test: `spec/requests/maintenance/flowchart_versions_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/requests/maintenance/flowchart_versions_spec.rb`:

```ruby
  describe "PUT default (set as default = publish/restore)" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }

    it "syncs live config to the version and repoints default_version_id" do
      flowchart.create_version_snapshot!(description: "v1")
      target = flowchart.flowchart_versions.ordered.first
      target_config = target.configuration
      flowchart.update!(configuration: '{"elements":[],"connections":[],"metadata":{}}')

      put "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions/#{target.id}/default.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("success" => true, "default_version_id" => target.id)
      expect(flowchart.reload.configuration).to eq(target_config)
      expect(flowchart.default_version_id).to eq(target.id)
    end

    it "is blocked (422) for an active flowchart" do
      flowchart.create_version_snapshot!
      target = flowchart.flowchart_versions.ordered.first
      flowchart.update_column(:status, Flowchart.statuses[:active])
      put "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions/#{target.id}/default.json"
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("flowchart_not_draft")
    end

    it "404s for a version on another customer's flowchart" do
      other_customer  = create(:customer)
      other_flowchart = create(:flowchart, :simple, :draft, customer: other_customer, entity: create(:entity, customer: other_customer))
      other_flowchart.create_version_snapshot!
      target = other_flowchart.flowchart_versions.ordered.first
      put "/#{customer.id}/admin/maintenance/flowcharts/#{other_flowchart.id}/versions/#{target.id}/default.json"
      expect(response).to have_http_status(:not_found)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "PUT default"`
Expected: FAIL (no route/action).

- [ ] **Step 3: Implement the action**

In `app/controllers/admin/maintenance/flowchart_versions_controller.rb`, extend the guards and add the action. Update the `before_action` guard lines to cover `:default`:

```ruby
      before_action :guard_shared_write!, only: %i[create default]
      before_action :guard_not_draft!,    only: %i[create default]
```

Add the action (after `create`):

```ruby
      def default
        version = @flowchart.flowchart_versions.find(params[:id])
        @flowchart.transaction do
          @flowchart.update!(configuration: version.configuration)
          @flowchart.update_column(:default_version_id, version.id)
        end
        render json: { success: true, default_version_id: version.id, version_number: version.version_number }
      end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "PUT default"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/flowchart_versions_controller.rb spec/requests/maintenance/flowchart_versions_spec.rb
git commit -m "feat(flowcharts): set-version-as-default endpoint (publish/restore)"
```

---

### Task 4: `flowchart_versions#edit` opens a version in the editor

**Files:**
- Modify: `app/controllers/admin/maintenance/flowchart_versions_controller.rb`
- Test: `spec/requests/maintenance/flowchart_versions_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to the request spec:

```ruby
  describe "GET edit (open version in editor)" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }

    it "renders the editor with the version's configuration and based-on attribute" do
      version = flowchart.create_version_snapshot!(description: "v1")
      get "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions/#{version.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-flowchart-canvas-based-on-version-id-value=\"#{version.id}\"")
      expect(response.body).to include("Editing based on v#{version.version_number}")
    end

    it "404s for a version on another customer's flowchart" do
      other_customer  = create(:customer)
      other_flowchart = create(:flowchart, :simple, :draft, customer: other_customer, entity: create(:entity, customer: other_customer))
      v = other_flowchart.create_version_snapshot!
      get "/#{customer.id}/admin/maintenance/flowcharts/#{other_flowchart.id}/versions/#{v.id}/edit"
      expect(response).to have_http_status(:not_found)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "GET edit"`
Expected: FAIL (no action / missing banner+attr; the editor partial change lands in Task 8 — this test will stay red until then, which is expected; verify it fails for the right reason: "unknown action" or routing).

- [ ] **Step 3: Implement the action**

Add to the controller:

```ruby
      def edit
        @version = @flowchart.flowchart_versions.find(params[:id])
        @flowchart.configuration = @version.configuration # in-memory only; not persisted
        @based_on_version_id = @version.id
        @editing_version = @version
        render template: "admin/maintenance/flowcharts/edit"
      end
```

- [ ] **Step 4: Note**

This test depends on the editor partial changes in Task 8 (`@based_on_version_id` attribute + `@editing_version` banner). Leave it red until Task 8; the action itself is verifiable now via:

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "404s for a version on another customer"`
Expected: PASS (404 path works without the partial change).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/flowchart_versions_controller.rb spec/requests/maintenance/flowchart_versions_spec.rb
git commit -m "feat(flowcharts): versions#edit opens a version in the builder editor"
```

---

### Task 5: `index` exposes `is_default`; `create` sets default + based-on

**Files:**
- Modify: `app/controllers/admin/maintenance/flowchart_versions_controller.rb`
- Test: `spec/requests/maintenance/flowchart_versions_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to the request spec:

```ruby
  describe "GET index is_default flag" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }

    it "marks the default version row" do
      v = flowchart.create_version_snapshot!(description: "v1")
      flowchart.update_column(:default_version_id, v.id)
      get "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions.json"
      body = JSON.parse(response.body)
      default_row = body.find { |r| r["id"] == v.id }
      expect(default_row["is_default"]).to be(true)
    end
  end

  describe "POST create promotes restored snapshot to default with based-on" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }

    it "sets default_version_id to the restored snapshot and tags based_on" do
      flowchart.create_version_snapshot!(description: "v1")
      target = flowchart.flowchart_versions.ordered.first
      post "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/versions.json",
           params: { version_id: target.id }, as: :json
      flowchart.reload
      restored = flowchart.flowchart_versions.ordered.first
      expect(flowchart.default_version_id).to eq(restored.id)
      expect(restored.based_on_version_id).to eq(target.id)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "is_default flag" -e "promotes restored"`
Expected: FAIL.

- [ ] **Step 3: Implement**

Update `index` JSON mapping to include `is_default`:

```ruby
      def index
        @versions = @flowchart.flowchart_versions.recent
        render json: @versions.map { |v|
          {
            id: v.id, version_number: v.version_number, description: v.description,
            created_at: v.created_at.iso8601, is_default: v.id == @flowchart.default_version_id
          }
        }
      end
```

Update `create` to tag based-on and promote to default:

```ruby
      def create
        version = @flowchart.flowchart_versions.find(params[:version_id])
        @flowchart.transaction do
          @flowchart.create_version_snapshot!(description: "Before restore to v#{version.version_number}")
          @flowchart.update!(configuration: version.configuration)
          restored = @flowchart.create_version_snapshot!(
            description: "Restored from v#{version.version_number}",
            based_on_version_id: version.id
          )
          @flowchart.update_column(:default_version_id, restored.id)
        end
        render json: { success: true, configuration: @flowchart.configuration, version_number: @flowchart.flowchart_versions.maximum(:version_number) }
      end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb`
Expected: PASS for all (the existing `POST create` "Restored from vN" assertion still holds).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/flowchart_versions_controller.rb spec/requests/maintenance/flowchart_versions_spec.rb
git commit -m "feat(flowcharts): version index is_default + restore promotes default with lineage"
```

---

### Task 6: `flowcharts#update` carries based-on + promotes default

**Files:**
- Modify: `app/controllers/admin/maintenance/flowcharts_controller.rb:95-111`
- Test: `spec/requests/maintenance/flowcharts_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/requests/maintenance/flowcharts_spec.rb` (create the file if absent, following the versions spec setup):

```ruby
require "rails_helper"

RSpec.describe "Maintenance::Flowcharts update lineage", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, customer: customer, role: :admin) }
  let(:entity)    { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }
  before { sign_in admin }

  def new_config = '{"elements":[{"id":"el_x","type":"start","x":1,"y":1,"width":100,"height":45,"label":"S","properties":{"inputs":[],"outputs":[]}}],"connections":[],"metadata":{}}'

  it "promotes the new snapshot to default and tags based_on when provided" do
    parent = flowchart.create_version_snapshot!(description: "v1")
    patch "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}.json",
          params: { flowchart: { configuration: new_config }, based_on_version_id: parent.id }, as: :json
    expect(response).to have_http_status(:ok)
    flowchart.reload
    snap = flowchart.flowchart_versions.ordered.first
    expect(flowchart.default_version_id).to eq(snap.id)
    expect(snap.based_on_version_id).to eq(parent.id)
  end

  it "drops a foreign based_on_version_id" do
    other = create(:flowchart, :simple, :draft, customer: customer, entity: entity)
    foreign = other.create_version_snapshot!
    patch "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}.json",
          params: { flowchart: { configuration: new_config }, based_on_version_id: foreign.id }, as: :json
    snap = flowchart.reload.flowchart_versions.ordered.first
    expect(snap.based_on_version_id).to be_nil
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_spec.rb -e "update lineage"`
Expected: FAIL (no default promotion).

- [ ] **Step 3: Implement**

In `app/controllers/admin/maintenance/flowcharts_controller.rb`, replace the snapshot block inside `update`:

```ruby
        if @flowchart.configuration != configuration_was
          version = @flowchart.create_version_snapshot!(
            description: "Manual save",
            based_on_version_id: params[:based_on_version_id]
          )
          @flowchart.update_column(:default_version_id, version.id)
        end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_spec.rb -e "update lineage"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/flowcharts_controller.rb spec/requests/maintenance/flowcharts_spec.rb
git commit -m "feat(flowcharts): manual save records based-on lineage and promotes default"
```

---

### Task 7: List page Versions column shows the default version

**Files:**
- Modify: `app/controllers/admin/maintenance/flowcharts_controller.rb:20-33`
- Test: `spec/requests/maintenance/flowcharts_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/requests/maintenance/flowcharts_spec.rb`:

```ruby
RSpec.describe "Maintenance::Flowcharts index versions column", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, customer: customer, role: :admin) }
  let(:entity)    { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer, entity: entity) }
  before { sign_in admin }

  it "shows the default version number, not a count" do
    flowchart.create_version_snapshot!(description: "v1")
    v = flowchart.create_version_snapshot!(description: "v2")
    flowchart.update_column(:default_version_id, v.id)
    get "/#{customer.id}/admin/maintenance/flowcharts"
    expect(response.body).to include("v#{v.version_number}")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_spec.rb -e "index versions column"`
Expected: may already render "2" (count); assert specifically on `v#{number}` so it fails until changed.

- [ ] **Step 3: Implement**

In the `index` action, replace the versions column definition:

```ruby
        { key: :default_version,  label: "Versions", type: :text, sortable: false, searchable: false,
          cell: ->(f) { (v = f.display_default_version) ? "v#{v.version_number}" : "—" } },
```

And update the scope to preload:

```ruby
      scope  = Flowchart.where(customer_id: current_customer.id).includes(:entity, :default_version, :flowchart_versions)
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_spec.rb -e "index versions column"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/flowcharts_controller.rb spec/requests/maintenance/flowcharts_spec.rb
git commit -m "feat(flowcharts): list page Versions column shows the default version"
```

---

### Task 8: Editor partial based-on banner + attribute; canvas JS sends based_on

**Files:**
- Modify: `app/views/admin/maintenance/flowcharts/_editor.html.erb:3-28`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` (static values + `_saveToServer` body)

- [ ] **Step 1: Add the data attribute + banner to the editor partial**

In `_editor.html.erb`, add to the root canvas `<div data-controller="flowchart-canvas" ...>` attribute list (after the `configuration-value` line):

```erb
     <% if @based_on_version_id %>data-flowchart-canvas-based-on-version-id-value="<%= @based_on_version_id %>"<% end %>
```

Add the banner immediately after the opening root `<div ...>` and before the existing `<% if @flowchart.active? %>` block:

```erb
  <% if @editing_version %>
    <div class="bg-indigo-50 border-b border-indigo-200 px-4 py-2 flex items-center gap-2">
      <svg class="w-5 h-5 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <span class="text-sm font-medium text-indigo-800">
        Editing based on v<%= @editing_version.version_number %> — saving will create a new version.
      </span>
    </div>
  <% end %>
```

- [ ] **Step 2: Run the request spec from Task 4 (now expected to pass)**

Run: `bundle exec rspec spec/requests/maintenance/flowchart_versions_spec.rb -e "GET edit"`
Expected: PASS (banner text + based-on attribute now present).

- [ ] **Step 3: Update the canvas controller**

In `app/javascript/controllers/flowchart_canvas_controller.js`, add `basedOnVersionId: String` to the existing `static values = { ... }` declaration.

In `_saveToServer`, change the fetch body:

```js
        body: JSON.stringify({
          flowchart: { configuration: JSON.stringify(configToSave) },
          ...(this.hasBasedOnVersionIdValue && this.basedOnVersionIdValue
              ? { based_on_version_id: this.basedOnVersionIdValue } : {})
        })
```

- [ ] **Step 4: Rebuild assets**

Run: `rm -f public/assets/.manifest.json && yarn build 2>/dev/null || bin/rails assets:precompile`
Expected: build completes without error (use the project's standard JS build command).

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/maintenance/flowcharts/_editor.html.erb app/javascript/controllers/flowchart_canvas_controller.js
git commit -m "feat(flowcharts): editor based-on banner + canvas save carries based_on_version_id"
```

---

### Task 9: Version-history modal refactor (component + Stimulus)

**Files:**
- Modify: `app/components/flowchart_versions_modal_component.html.erb`
- Modify: `app/javascript/controllers/flowchart_versions_controller.js`
- Test: `spec/components/flowchart_versions_modal_component_spec.rb`

- [ ] **Step 1: Rewrite the failing component test**

Replace `spec/components/flowchart_versions_modal_component_spec.rb` body:

```ruby
RSpec.describe FlowchartVersionsModalComponent, type: :component do
  it "renders the modal shell with list, content, diff and error targets" do
    render_inline(described_class.new)
    expect(page).to have_css("[data-flowchart-versions-target='modal']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='title']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='list']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='content']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='diffButton']", visible: :all)
    expect(page).to have_css("[data-flowchart-versions-target='error']", visible: :all)
  end

  it "no longer renders the removed 'New version from' button target" do
    render_inline(described_class.new)
    expect(page).not_to have_css("[data-flowchart-versions-target='newButton']", visible: :all)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/components/flowchart_versions_modal_component_spec.rb`
Expected: FAIL on the second example (newButton still present).

- [ ] **Step 3: Update the modal HTML**

In `app/components/flowchart_versions_modal_component.html.erb`, replace the footer block (the `<div class="flex items-center justify-end ...">` containing both buttons) with just the Diff button:

```erb
      <div class="flex items-center justify-end gap-2 px-4 py-3 border-t border-slate-100 bg-slate-50/50">
        <button type="button" data-flowchart-versions-target="diffButton" disabled
                data-action="click->flowchart-versions#diff"
                class="px-3 py-1.5 text-xs font-medium text-slate-700 bg-white border border-slate-200 rounded-md hover:bg-slate-50 disabled:opacity-50 disabled:cursor-not-allowed">
          Diff selected
        </button>
      </div>
```

Update the content placeholder text on line ~29 from "Select a version to preview, or pick two to diff." to "Select two versions to diff."

- [ ] **Step 4: Update the Stimulus controller**

In `app/javascript/controllers/flowchart_versions_controller.js`:

- Remove the `FlowchartCanvas` import (line 4) and the `_renderPreview` method (the in-modal canvas preview is gone).
- Remove `"newButton"` from `static targets` and delete `newVersionFrom` + the `newButtonTarget` logic in `_updateButtons`.
- Change `view` to open a new tab:

```js
  view(event) {
    if (event) event.preventDefault()
    const id = String(event.params.id)
    window.open(`${this._base()}/${id}/edit`, "_blank")
  }
```

- Add a `setDefault` action:

```js
  async setDefault(event) {
    if (event) event.preventDefault()
    const id = String(event.params.id)
    const res = await this._fetch(`${this._base()}/${id}/default.json`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": getCSRFToken(), Accept: "application/json" }
    })
    if (!res) return
    if (res.status === 422) {
      const body = await res.json().catch(() => ({}))
      return this._error(body.message || "Cannot set default while the flowchart is active. Deactivate it first.")
    }
    if (res.status === 403) return this._error("Shared flowcharts can only be changed by the platform owner.")
    if (!res.ok) return this._error(`Failed to set default (${res.status})`)
    this._clearError()
    await this.loadVersions()
    this._bumpRowCount()
  }
```

- Update `_renderList` so each row shows a Default pill when `v.is_default`, hides "Set as default" on the default row, and renders the new buttons:

```js
    this.listTarget.innerHTML = this.versions.map(v => {
      const id = String(v.id)
      const checked = this.selected.includes(id)
      const defaultPill = v.is_default
        ? `<span class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-emerald-100 text-emerald-700">Default</span>`
        : ""
      const setDefaultBtn = v.is_default
        ? ""
        : `<button type="button" data-action="click->flowchart-versions#setDefault"
                   data-flowchart-versions-id-param="${escapeHtml(id)}"
                   class="text-[11px] font-medium text-emerald-600 hover:text-emerald-700">Set default</button>`
      return `
        <li class="px-3 py-2 flex items-start gap-2 ${checked ? "bg-indigo-50/60" : ""}">
          <input type="checkbox" ${checked ? "checked" : ""}
                 data-action="change->flowchart-versions#toggleSelect"
                 data-flowchart-versions-id-param="${escapeHtml(id)}"
                 class="mt-0.5">
          <div class="flex-1 min-w-0">
            <div class="text-xs font-medium text-slate-800 flex items-center gap-1.5">v${escapeHtml(String(v.version_number))} ${defaultPill}</div>
            <div class="text-[11px] text-slate-500 truncate">${escapeHtml(v.description || "")}</div>
            <div class="text-[10px] text-slate-400">${escapeHtml(v.created_at || "")}</div>
          </div>
          <div class="flex flex-col items-end gap-1">
            <button type="button" data-action="click->flowchart-versions#view"
                    data-flowchart-versions-id-param="${escapeHtml(id)}"
                    class="text-[11px] font-medium text-indigo-600 hover:text-indigo-700">View</button>
            ${setDefaultBtn}
          </div>
        </li>`
    }).join("")
```

- In `_updateButtons`, keep only the diff button:

```js
  _updateButtons() {
    if (this.hasDiffButtonTarget) this.diffButtonTarget.disabled = this.selected.length !== 2
  }
```

- In `open`, update the placeholder text to "Select two versions to diff."

- [ ] **Step 5: Run the component test**

Run: `bundle exec rspec spec/components/flowchart_versions_modal_component_spec.rb`
Expected: PASS.

- [ ] **Step 6: Rebuild assets**

Run: `rm -f public/assets/.manifest.json && yarn build 2>/dev/null || bin/rails assets:precompile`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add app/components/flowchart_versions_modal_component.html.erb app/javascript/controllers/flowchart_versions_controller.js spec/components/flowchart_versions_modal_component_spec.rb
git commit -m "feat(flowcharts): version modal — set-default + view-in-new-tab, drop in-modal preview"
```

---

### Task 10: Full targeted suite + smoke

**Files:** none (verification only)

- [ ] **Step 1: Run all touched specs**

Run:
```bash
bundle exec rspec \
  spec/models/flowchart_spec.rb \
  spec/requests/maintenance/flowchart_versions_spec.rb \
  spec/requests/maintenance/flowcharts_spec.rb \
  spec/components/flowchart_versions_modal_component_spec.rb
```
Expected: all green.

- [ ] **Step 2: Smoke the server**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` (background), then load `/81721200/admin/maintenance/flowcharts`, open the Versions modal, click "Set default" on a draft flowchart's version, and click "View" to confirm a new tab opens the editor with the based-on banner.

- [ ] **Step 3: Final commit (if any asset/manifest changes remain)**

```bash
git add -A
git commit -m "chore(flowcharts): rebuild assets for version default + version-edit"
```
```
```
