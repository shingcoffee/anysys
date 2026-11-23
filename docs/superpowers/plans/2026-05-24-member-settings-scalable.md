# Member Admin Settings — Scalable Source-Driven Architecture — Implementation Plan

> **For agentic workers:** This plan is **role-sliced** for the `anysys-*` agent family. The orchestrator (you, Copilot) dispatches one specialized agent per slice. Within a phase, parallel slices fan out concurrently; phase boundaries are review checkpoints. The slices intentionally honor the role boundaries declared in the agent definitions:
>
> - `anysys-backend-developer` — models, migrations, services, Trailblazer activities, Reform contracts. CANNOT edit views, components, routes, controllers.
> - `anysys-security-engineer` — routes + controllers + auth guards + tenant scoping.
> - `anysys-frontend-developer` — ViewComponent classes + ERB templates + Stimulus controllers + component specs. CANNOT edit models/migrations/routes/controllers.
> - `anysys-qa-engineer` — RSpec specs (model/activity/contract/component/request/system). NEVER edits production code.
> - `anysys-release-engineer` — runs RSpec on touched files, rebuilds assets, restarts dev server, smoke-hits a URL. PASS/FAIL only; never edits files.
> - `anysys-tech-lead` — diff-only convention review; never edits.
> - `anysys-code-reviewer` — diff-only correctness/security review; never edits.

**Goal:** Restructure `/:cid/admin/settings/member` as a hub of pluggable surface sources (Built-in / Modules / Entities) with per-source and per-surface drill-down pages, replacing today's single tall form. Member-facing member behavior stays wire-compatible.

**Architecture:** Introduce `Member::SurfaceSource` (parallel to `SettingsContributor`) with a registry. `Member::Surfaces` keeps its public API but routes discovery through registered sources. Three source classes ship: `Builtin` (always-locked Home/Profile/Security), `Modules` (auto-discovers `FeatureModules::*::MemberSurface`), `Entities` (one descriptor per `Entity` row, scope intentionally `EntityEntry.none` until per-entry ownership ships). Admin URLs split into hub → `/sources/:key` → `/sources/:source_key/surfaces/:key`.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, ViewComponent, TailwindCSS, StimulusJS, Trailblazer (Reform + Activity), `JsonSerializable` concern.

**Spec:** `docs/superpowers/specs/2026-05-24-member-settings-scalable-design.md` (this plan implements every section).

---

## Phase map

```
Phase 0 — Foundation (sequential, single backend agent)
  └─ Slice 0.A: Surface source contract + registry (NO behavior change yet)

Phase 1 — Sources + storage delta (sequential, single backend agent)
  └─ Slice 1.A: SurfaceSetting source_key migration + model validation
  └─ Slice 1.B: Sources::Builtin + BuiltinSurface adapter
  └─ Slice 1.C: Sources::Modules
  └─ Slice 1.D: Sources::Entities + EntitySurfaceBuilder
  └─ Slice 1.E: Surfaces.for / fetch / sources / source_for / surfaces_in
                + EffectiveSurface#source_key
                + delete BESPOKE_ITEMS from Member::Navigation
  └─ Slice 1.F: Operation::Update — drop contract inclusion, validate per
                customer, drop !editable, set source_key on save

Phase 2 — Admin surface (parallel)
  ├─ Slice 2.A — security-engineer: routes + 3 controllers + auth guards
  ├─ Slice 2.B — frontend-developer: 3 ViewComponents + 3 views + Stimulus
  └─ Slice 2.C — qa-engineer: request specs + system specs

Phase 3 — Verification + review (sequential)
  └─ Slice 3.A — release-engineer: full test sweep + dev smoke
  └─ Slice 3.B — tech-lead: diff convention review
  └─ Slice 3.C — code-reviewer: correctness + security review
```

Phase boundaries (between 0/1, 1/2, 2/3) are checkpoints: orchestrator reviews diffs before dispatching the next phase. **Within Phase 2 the three slices fan out concurrently** because they touch disjoint files.

---

## Phase 0 — Foundation

### Slice 0.A — `SurfaceSource` contract + `SourceRegistry`

**Agent:** `anysys-backend-developer`

**Why first:** Every later slice imports from this. No production behavior change yet — registry is empty until Phase 1 sources call `register!`.

**Files:**
- Create: `app/services/member/surface_source.rb`
- Create: `app/services/member/surfaces/source_registry.rb`
- Create: `spec/services/member/surface_source_spec.rb`
- Create: `spec/services/member/surfaces/source_registry_spec.rb`
- Create: `config/initializers/member_surface_sources.rb` (empty stub — Phase 1 fills it)

**Tasks:**

- [ ] **Step 1: Failing spec — `SourceRegistry`**

```ruby
# spec/services/member/surfaces/source_registry_spec.rb
require "rails_helper"

RSpec.describe Member::Surfaces::SourceRegistry do
  let(:source_class) do
    Class.new(Member::SurfaceSource) do
      def self.key      ; :test_src ; end
      def self.name     ; "Test"    ; end
      def self.position ; 99        ; end
      def surfaces      ; []        ; end
    end
  end

  before { described_class.reset! }

  describe ".register / .all / .find" do
    it "registers a source class and returns it" do
      described_class.register(source_class)
      expect(described_class.all).to include(source_class)
      expect(described_class.find(:test_src)).to eq(source_class)
    end

    it "looks up by string or symbol" do
      described_class.register(source_class)
      expect(described_class.find("test_src")).to eq(source_class)
    end

    it "returns nil for an unknown key" do
      expect(described_class.find(:nope)).to be_nil
    end

    it "sorts .all by position ascending" do
      first  = Class.new(Member::SurfaceSource) do
        def self.key ; :a_first ; end
        def self.name ; "A" ; end
        def self.position ; 1 ; end
        def surfaces ; [] ; end
      end
      second = Class.new(Member::SurfaceSource) do
        def self.key ; :z_second ; end
        def self.name ; "Z" ; end
        def self.position ; 10 ; end
        def surfaces ; [] ; end
      end
      described_class.register(second)
      described_class.register(first)
      expect(described_class.all).to eq([first, second])
    end

    it ".reset! empties the registry" do
      described_class.register(source_class)
      described_class.reset!
      expect(described_class.all).to eq([])
    end
  end
end
```

- [ ] **Step 2: Failing spec — `SurfaceSource`**

```ruby
# spec/services/member/surface_source_spec.rb
require "rails_helper"

RSpec.describe Member::SurfaceSource do
  describe "subclass interface" do
    it "raises NotImplementedError when .key is not overridden" do
      klass = Class.new(described_class)
      expect { klass.key }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError when .name is not overridden" do
      klass = Class.new(described_class)
      expect { klass.name }.to raise_error(NotImplementedError)
    end

    it "defaults .editable? to true" do
      klass = Class.new(described_class) do
        def self.key ; :x ; end
        def self.name ; "X" ; end
      end
      expect(klass.editable?).to be(true)
    end

    it "defaults .position to 100" do
      klass = Class.new(described_class) do
        def self.key ; :x ; end
        def self.name ; "X" ; end
      end
      expect(klass.position).to eq(100)
    end

    it "defaults .description to ''" do
      klass = Class.new(described_class) do
        def self.key ; :x ; end
        def self.name ; "X" ; end
      end
      expect(klass.description).to eq("")
    end

    it "raises NotImplementedError when #surfaces is not overridden" do
      klass = Class.new(described_class) do
        def self.key ; :x ; end
        def self.name ; "X" ; end
      end
      expect { klass.new(customer: build(:customer)).surfaces }.to raise_error(NotImplementedError)
    end
  end

  describe "#surface_for(key:)" do
    let(:customer) { create(:customer) }

    it "returns the surface with the matching key" do
      surface = double("Surface", key: :alpha)
      klass = Class.new(described_class) do
        def self.key ; :x ; end
        def self.name ; "X" ; end
      end
      instance = klass.new(customer: customer)
      allow(instance).to receive(:surfaces).and_return([surface])

      expect(instance.surface_for(key: :alpha)).to eq(surface)
    end

    it "returns nil when no surface matches" do
      klass = Class.new(described_class) do
        def self.key ; :x ; end
        def self.name ; "X" ; end
      end
      instance = klass.new(customer: customer)
      allow(instance).to receive(:surfaces).and_return([])

      expect(instance.surface_for(key: :nope)).to be_nil
    end
  end

  describe ".register!" do
    after { Member::Surfaces::SourceRegistry.reset! }

    it "delegates to SourceRegistry.register(self)" do
      klass = Class.new(described_class) do
        def self.key ; :reg_test ; end
        def self.name ; "Reg" ; end
      end
      klass.register!
      expect(Member::Surfaces::SourceRegistry.find(:reg_test)).to eq(klass)
    end
  end
end
```

- [ ] **Step 3: Run, confirm red**

```
bundle exec rspec spec/services/member/surface_source_spec.rb \
                  spec/services/member/surfaces/source_registry_spec.rb
```

Expected: NameError (constants not defined).

- [ ] **Step 4: Implement `SourceRegistry`**

```ruby
# app/services/member/surfaces/source_registry.rb
# frozen_string_literal: true

module Member
  module Surfaces
    # Registry of Member::SurfaceSource subclasses. Each source
    # self-registers via `register!` at file load.
    module SourceRegistry
      class << self
        def register(klass)
          @sources ||= {}
          @sources[klass.key.to_sym] = klass
        end

        def all
          (@sources || {}).values.sort_by(&:position)
        end

        def find(key)
          (@sources || {})[key.to_sym]
        end

        def reset!
          @sources = {}
        end
      end
    end
  end
end
```

- [ ] **Step 5: Implement `SurfaceSource`**

```ruby
# app/services/member/surface_source.rb
# frozen_string_literal: true

module Member
  # Pluggable contributor of Member::Surface descriptors. Concrete
  # subclasses live in Member::Sources::* and self-register via
  # `register!` at file load. The orchestrator that walks the registry is
  # Member::Surfaces.
  class SurfaceSource
    # ---- subclass interface (class methods) ----
    def self.key             ; raise NotImplementedError, "subclass must define .key"  ; end
    def self.name            ; raise NotImplementedError, "subclass must define .name" ; end
    def self.description     ; "" ; end
    def self.editable?       ; true ; end
    def self.position        ; 100 ; end

    def self.register!
      Member::Surfaces::SourceRegistry.register(self)
    end

    # ---- instance interface ----
    def initialize(customer:)
      @customer = customer
    end
    attr_reader :customer

    def surfaces
      raise NotImplementedError, "#{self.class} must define #surfaces"
    end

    def surface_for(key:)
      surfaces.find { |s| s.key.to_sym == key.to_sym }
    end
  end
end
```

- [ ] **Step 6: Empty initializer stub**

```ruby
# config/initializers/member_surface_sources.rb
# frozen_string_literal: true

# Eager-load member surface sources so SourceRegistry is fully populated
# before the first request. Each source file calls `register!` at load.
#
# Phase 1 fills this in. Empty during Phase 0.
Rails.application.config.to_prepare do
  # Member::Sources::Builtin
  # Member::Sources::Modules
  # Member::Sources::Entities
end
```

- [ ] **Step 7: Run, confirm green**

```
bundle exec rspec spec/services/member/surface_source_spec.rb \
                  spec/services/member/surfaces/source_registry_spec.rb
```

- [ ] **Step 8: Commit**

```
git add app/services/member/surface_source.rb \
        app/services/member/surfaces/source_registry.rb \
        spec/services/member/surface_source_spec.rb \
        spec/services/member/surfaces/source_registry_spec.rb \
        config/initializers/member_surface_sources.rb
git commit -m "feat(member): add SurfaceSource contract + SourceRegistry"
```

**Phase 0 checkpoint:** Orchestrator reviews diff. No production behavior change expected. Proceed to Phase 1.

---

## Phase 1 — Sources + storage + registry refactor

All slices in Phase 1 run **sequentially** (single backend agent dispatch covers them all in one session, or one slice per dispatch — at orchestrator's choice). They touch overlapping files.

### Slice 1.A — Migration + `source_key` validation on `SurfaceSetting`

**Agent:** `anysys-backend-developer`

**Files:**
- Create: `db/migrate/<TS>_add_source_key_to_member_surface_settings.rb`
- Modify: `app/models/member/surface_setting.rb`
- Modify: `spec/models/member/surface_setting_spec.rb`

**Tasks:**

- [ ] **Step 1: Generate migration filename**

```
TS=$(date -u +%Y%m%d%H%M%S)
touch db/migrate/${TS}_add_source_key_to_member_surface_settings.rb
```

- [ ] **Step 2: Migration**

```ruby
class AddSourceKeyToMemberSurfaceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :member_surface_settings, :source_key, :string
    add_index  :member_surface_settings, %i[customer_id source_key],
               name: "idx_member_surface_settings_on_customer_and_source"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE member_surface_settings
             SET source_key = 'modules'
           WHERE source_key IS NULL
        SQL
      end
    end
  end
end
```

- [ ] **Step 3: Run migration**

```
bundle exec rails db:migrate
RAILS_ENV=test bundle exec rails db:migrate
```

- [ ] **Step 4: Failing spec for model — add to `spec/models/member/surface_setting_spec.rb`**

Append:

```ruby
describe "source_key" do
  before do
    Member::Surfaces::SourceRegistry.reset!
    klass = Class.new(Member::SurfaceSource) do
      def self.key ; :modules ; end
      def self.name ; "Modules" ; end
    end
    Member::Surfaces::SourceRegistry.register(klass)
  end
  after { Member::Surfaces::SourceRegistry.reset! }

  it "is valid when source_key matches a registered source" do
    record = described_class.new(customer: customer, surface_key: "payments", source_key: "modules")
    expect(record).to be_valid
  end

  it "is invalid when source_key is not registered" do
    record = described_class.new(customer: customer, surface_key: "payments", source_key: "phantom")
    expect(record).not_to be_valid
    expect(record.errors[:source_key]).to be_present
  end

  it "is invalid when source_key is blank" do
    record = described_class.new(customer: customer, surface_key: "payments", source_key: "")
    expect(record).not_to be_valid
  end
end
```

- [ ] **Step 5: Run, confirm red**

```
bundle exec rspec spec/models/member/surface_setting_spec.rb -e "source_key"
```

- [ ] **Step 6: Add validation to `Member::SurfaceSetting`**

In `app/models/member/surface_setting.rb`, add after the existing `surface_key` validation:

```ruby
validates :source_key, presence: true,
                       inclusion: {
                         in: ->(_) { Member::Surfaces::SourceRegistry.all.map { |s| s.key.to_s } }
                       }
```

- [ ] **Step 7: Run, confirm green**

```
bundle exec rspec spec/models/member/surface_setting_spec.rb
```

- [ ] **Step 8: Commit**

```
git add db/migrate/ db/schema.rb \
        app/models/member/surface_setting.rb \
        spec/models/member/surface_setting_spec.rb
git commit -m "feat(member): add source_key column + validation to SurfaceSetting"
```

---

### Slice 1.B — `Sources::Builtin` + `BuiltinSurface` adapter

**Agent:** `anysys-backend-developer`

**Files:**
- Create: `app/services/member/sources/builtin.rb`
- Create: `app/services/member/sources/builtin_surface.rb`
- Create: `spec/services/member/sources/builtin_spec.rb`

**Tasks:**

- [ ] **Step 1: Failing spec**

```ruby
# spec/services/member/sources/builtin_spec.rb
require "rails_helper"

RSpec.describe Member::Sources::Builtin do
  let(:customer) { create(:customer) }

  describe "metadata" do
    it { expect(described_class.key).to eq(:builtin) }
    it { expect(described_class.name).to eq("Built-in") }
    it { expect(described_class.editable?).to be(false) }
    it { expect(described_class.position).to eq(0) }
  end

  describe "#surfaces" do
    subject(:surfaces) { described_class.new(customer: customer).surfaces }

    it "yields three surfaces in fixed order: home, profile, security" do
      expect(surfaces.map(&:key)).to eq([:builtin_home, :builtin_profile, :builtin_security])
    end

    it "labels them Home / Profile / Security" do
      expect(surfaces.map(&:label)).to eq(["Home", "Profile", "Security"])
    end

    it "assigns ascending default positions (0, 10, 20)" do
      expect(surfaces.map(&:default_position)).to eq([0, 10, 20])
    end

    it "exposes path_seg on each surface" do
      expect(surfaces.map(&:path_seg)).to eq(["", "profile", "security"])
    end

    it "responds true to enabled_for? for any user" do
      surface = surfaces.first
      expect(surface.enabled_for?(double("User"))).to be(true)
    end
  end
end
```

- [ ] **Step 2: Run, confirm red**

```
bundle exec rspec spec/services/member/sources/builtin_spec.rb
```

- [ ] **Step 3: Implement `BuiltinSurface` adapter**

```ruby
# app/services/member/sources/builtin_surface.rb
# frozen_string_literal: true

module Member
  module Sources
    # Tiny duck-type that quacks like Member::Surface for the bespoke
    # Home / Profile / Security entries. These are routed to dedicated
    # controllers (profiles#show, securities#show, etc.) and never flow
    # through SurfacesController, so index/detail accessors raise.
    BuiltinSurface = Struct.new(:key, :label, :icon, :path_seg, :default_position,
                                keyword_init: true) do
      def default_position_or_default ; default_position.to_i ; end
      def enabled_for?(_user)         ; true ; end

      def index
        raise NotImplementedError, "BuiltinSurface does not expose an index"
      end

      def detail
        raise NotImplementedError, "BuiltinSurface does not expose a detail"
      end

      # Validation no-op so EffectiveSurface and the kit treat it like a
      # real Surface for the few accessors they do touch (label/icon/key).
      def validate! ; true ; end
    end
  end
end
```

- [ ] **Step 4: Implement `Sources::Builtin`**

```ruby
# app/services/member/sources/builtin.rb
# frozen_string_literal: true

require_relative "builtin_surface"

module Member
  module Sources
    class Builtin < Member::SurfaceSource
      def self.key         ; :builtin ; end
      def self.name        ; "Built-in" ; end
      def self.description ; "Always-visible member pages." ; end
      def self.editable?   ; false ; end
      def self.position    ; 0 ; end

      ENTRIES = [
        { key: :builtin_home,     label: "Home",     icon: :home,         path_seg: "",         default_position:  0 },
        { key: :builtin_profile,  label: "Profile",  icon: :user,         path_seg: "profile",  default_position: 10 },
        { key: :builtin_security, label: "Security", icon: :shield_check, path_seg: "security", default_position: 20 }
      ].freeze

      def surfaces
        ENTRIES.map { |e| BuiltinSurface.new(**e) }
      end

      register!
    end
  end
end
```

- [ ] **Step 5: Wire into initializer**

In `config/initializers/member_surface_sources.rb`, replace the body with:

```ruby
Rails.application.config.to_prepare do
  Member::Sources::Builtin
  # Member::Sources::Modules    (Slice 1.C)
  # Member::Sources::Entities   (Slice 1.D)
end
```

- [ ] **Step 6: Run, confirm green**

```
bundle exec rspec spec/services/member/sources/builtin_spec.rb
```

- [ ] **Step 7: Commit**

```
git add app/services/member/sources/ \
        config/initializers/member_surface_sources.rb \
        spec/services/member/sources/builtin_spec.rb
git commit -m "feat(member): add Sources::Builtin + BuiltinSurface adapter"
```

---

### Slice 1.C — `Sources::Modules`

**Agent:** `anysys-backend-developer`

**Files:**
- Create: `app/services/member/sources/modules.rb`
- Create: `spec/services/member/sources/modules_spec.rb`

**Tasks:**

- [ ] **Step 1: Failing spec**

```ruby
# spec/services/member/sources/modules_spec.rb
require "rails_helper"

RSpec.describe Member::Sources::Modules do
  let(:customer) { create(:customer) }

  describe "metadata" do
    it { expect(described_class.key).to eq(:modules) }
    it { expect(described_class.editable?).to be(true) }
    it { expect(described_class.position).to eq(10) }
  end

  describe "#surfaces" do
    before do
      payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
      FeatureModules::CustomerAssignment.find_or_create_by!(
        customer: customer, feature_module: payment_module
      ) { |a| a.status = :active }
    end

    it "includes the Payments descriptor when payment module is enabled" do
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).to include(:payments)
    end

    it "skips modules that are not available for the customer" do
      other_customer = create(:customer)
      keys = described_class.new(customer: other_customer).surfaces.map(&:key)
      expect(keys).not_to include(:payments)
    end

    it "calls validate! on each yielded descriptor" do
      surfaces = described_class.new(customer: customer).surfaces
      expect(surfaces.first).to be_a(Member::Surface)
    end
  end
end
```

- [ ] **Step 2: Run, confirm red**

- [ ] **Step 3: Implement**

```ruby
# app/services/member/sources/modules.rb
# frozen_string_literal: true

module Member
  module Sources
    class Modules < Member::SurfaceSource
      def self.key         ; :modules ; end
      def self.name        ; "Modules" ; end
      def self.description ; "Read-only surfaces shipped by feature modules." ; end
      def self.position    ; 10 ; end

      def surfaces
        FeatureModules::Module.available_for_customer(customer.id).flat_map do |fm|
          ns_name = "FeatureModules::#{fm.key.camelize}"
          ns      = ns_name.safe_constantize or next []

          surface = ns.const_defined?(:MemberSurface, false) ? ns.const_get(:MemberSurface) : nil
          next [] unless surface.is_a?(Member::Surface)

          surface.validate!
          [surface]
        end
      end

      register!
    end
  end
end
```

- [ ] **Step 4: Update initializer**

```ruby
Rails.application.config.to_prepare do
  Member::Sources::Builtin
  Member::Sources::Modules
  # Member::Sources::Entities   (Slice 1.D)
end
```

- [ ] **Step 5: Run, confirm green; commit**

```
bundle exec rspec spec/services/member/sources/modules_spec.rb
git add app/services/member/sources/modules.rb \
        config/initializers/member_surface_sources.rb \
        spec/services/member/sources/modules_spec.rb
git commit -m "feat(member): add Sources::Modules"
```

---

### Slice 1.D — `Sources::Entities` + `EntitySurfaceBuilder`

**Agent:** `anysys-backend-developer`

**Files:**
- Create: `app/services/member/sources/entities.rb`
- Create: `app/services/member/entity_surface_builder.rb`
- Create: `spec/services/member/sources/entities_spec.rb`
- Create: `spec/services/member/entity_surface_builder_spec.rb`

**Notes for the agent:**
- `Entity` is in `app/models/entity.rb`. Field schema is `entity.property_schema_json` — an array of hashes with `"name"`, `"name_slug"`, `"type"`, sometimes `"required"`. Skip entries where `type == "Calculated"`.
- Records are `EntityEntry` (not `EntityRecord`). The `entity_entries` table has NO `user_id` column. The Entities source's `scope:` lambda MUST return `EntityEntry.none` — this is intentional and called out in the spec §4.6.2. Do not invent a `user_id` filter; don't add user-ownership in this slice.

**Tasks:**

- [ ] **Step 1: Failing spec — `EntitySurfaceBuilder`**

```ruby
# spec/services/member/entity_surface_builder_spec.rb
require "rails_helper"

RSpec.describe Member::EntitySurfaceBuilder do
  let(:customer) { create(:customer) }
  let(:entity) do
    Entity.create!(
      customer_id: customer.id,
      name:        "Course",
      element_type: "custom",
      description: "Courses you've enrolled in.",
      property_schema: [
        { "name" => "Term",  "name_slug" => "term",  "type" => "string" },
        { "name" => "Score", "name_slug" => "score", "type" => "number" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
      ]
    )
  end

  subject(:surface) { described_class.call(entity: entity) }

  it "returns a Member::Surface" do
    expect(surface).to be_a(Member::Surface)
  end

  it "namespaces the surface key with entity_<slug>" do
    expect(surface.key).to eq(:"entity_#{entity.name_slug}")
  end

  it "uses the entity name as the label" do
    expect(surface.label).to eq("Course")
  end

  it "skips Calculated fields when building columns" do
    keys = surface.index.columns.map { |c| c[:key] }
    expect(keys).to include(:term, :score)
    expect(keys).not_to include(:total)
  end

  it "uses :money/:number/:string format for known types" do
    score_col = surface.index.columns.find { |c| c[:key] == :score }
    expect(score_col[:format]).to eq(:number)

    term_col = surface.index.columns.find { |c| c[:key] == :term }
    expect(term_col[:format]).to eq(:string)
  end

  it "returns EntityEntry.none from the scope (no user-ownership yet)" do
    user = build_stubbed(:user, customer: customer)
    expect(surface.index.scope.call(user)).to eq(EntityEntry.none)
  end

  it "subtitles with the entity description when present" do
    expect(surface.index.subtitle).to eq("Courses you've enrolled in.")
  end

  context "when the entity has no data fields" do
    let(:entity) do
      Entity.create!(
        customer_id: customer.id, name: "Bare", element_type: "custom", property_schema: []
      )
    end

    it "falls back to a single :id column so validate! passes" do
      expect(surface.index.columns.map { |c| c[:key] }).to eq([:id])
    end
  end

  context "with a default-position offset" do
    it "places entities after the DEFAULT_POSITION_BASE" do
      expect(surface.default_position).to be >= described_class::DEFAULT_POSITION_BASE
    end
  end
end
```

- [ ] **Step 2: Failing spec — `Sources::Entities`**

```ruby
# spec/services/member/sources/entities_spec.rb
require "rails_helper"

RSpec.describe Member::Sources::Entities do
  let(:customer) { create(:customer) }

  describe "metadata" do
    it { expect(described_class.key).to eq(:entities) }
    it { expect(described_class.editable?).to be(true) }
    it { expect(described_class.position).to eq(20) }
  end

  describe "#surfaces" do
    let!(:entity_a) { Entity.create!(customer_id: customer.id, name: "Course",  element_type: "custom") }
    let!(:entity_b) { Entity.create!(customer_id: customer.id, name: "Event",   element_type: "custom") }

    it "yields one surface per Entity row owned by the customer" do
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).to include(:entity_course, :entity_event)
    end

    it "ignores entities owned by other customers" do
      other = create(:customer)
      Entity.create!(customer_id: other.id, name: "Foreign", element_type: "custom")
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).not_to include(:entity_foreign)
    end
  end
end
```

- [ ] **Step 3: Run, confirm red**

- [ ] **Step 4: Implement `EntitySurfaceBuilder`**

```ruby
# app/services/member/entity_surface_builder.rb
# frozen_string_literal: true

module Member
  module EntitySurfaceBuilder
    DEFAULT_POSITION_BASE = 200

    def self.call(entity:)
      data_fields = (entity.property_schema_json || []).reject { |f| f["type"] == "Calculated" }

      columns = data_fields.map { |f|
        slug = f["name_slug"] || f["key"] || ""
        next nil if slug.empty?

        {
          key:      slug.to_sym,
          label:    f["name"].presence || slug.to_s.titleize,
          value:    ->(entry) { entry.respond_to?(:data_json) ? entry.data_json[slug] : nil },
          format:   format_for(f["type"]),
          align:    align_for(f["type"]),
          hideable: true
        }
      }.compact

      columns = [{ key: :id, label: "ID", value: ->(e) { e.id }, hideable: false }] if columns.empty?

      Member::Surface.new(
        key:   :"entity_#{entity.name_slug}",
        label: entity.name,
        icon:  :rectangle_stack,
        default_position: DEFAULT_POSITION_BASE + entity.id.to_i,
        enabled_for: ->(user) { user.customer_id == entity.customer_id },
        index: Member::Surface::Index.new(
          title:    entity.name,
          subtitle: entity.description.presence || "Records linked to your account.",
          # No user_id on entity_entries yet — return an empty relation.
          # Members never see records until per-entry ownership ships.
          scope:    ->(_user) { EntityEntry.none },
          columns:  columns,
          empty_state: {
            headline: "No #{entity.name.downcase} yet",
            body:     "Records will appear here once they're linked to your account.",
            icon:     :rectangle_stack
          },
          per_page: 20
        ),
        detail: Member::Surface::Detail.new(
          title:    ->(entry) { "##{entry.id}" },
          subtitle: ->(entry) { I18n.l(entry.created_at, format: :long) },
          sections: [{
            key:   :primary,
            rows:  columns.map { |c|
              { key: c[:key], label: c[:label], value: c[:value], format: c[:format], hideable: c[:hideable] }
            }
          }]
        )
      ).tap(&:validate!)
    end

    def self.format_for(type)
      case type.to_s.downcase
      when "money", "currency"           then :money
      when "number", "integer", "decimal" then :number
      when "datetime", "timestamp"       then :datetime
      when "date"                        then :date
      else                                    :string
      end
    end

    def self.align_for(type)
      %w[money currency number integer decimal].include?(type.to_s.downcase) ? :right : :left
    end
  end
end
```

- [ ] **Step 5: Implement `Sources::Entities`**

```ruby
# app/services/member/sources/entities.rb
# frozen_string_literal: true

module Member
  module Sources
    class Entities < Member::SurfaceSource
      def self.key         ; :entities ; end
      def self.name        ; "Entities" ; end
      def self.description ; "Surfaces auto-generated from custom entity schemas." ; end
      def self.position    ; 20 ; end

      def surfaces
        ::Entity.where(customer_id: customer.id).map { |entity|
          Member::EntitySurfaceBuilder.call(entity: entity)
        }
      end

      register!
    end
  end
end
```

- [ ] **Step 6: Update initializer**

```ruby
Rails.application.config.to_prepare do
  Member::Sources::Builtin
  Member::Sources::Modules
  Member::Sources::Entities
end
```

- [ ] **Step 7: Run green; commit**

```
bundle exec rspec spec/services/member/entity_surface_builder_spec.rb \
                  spec/services/member/sources/entities_spec.rb
git add app/services/member/sources/entities.rb \
        app/services/member/entity_surface_builder.rb \
        config/initializers/member_surface_sources.rb \
        spec/services/member/sources/entities_spec.rb \
        spec/services/member/entity_surface_builder_spec.rb
git commit -m "feat(member): add Sources::Entities + EntitySurfaceBuilder"
```

---

### Slice 1.E — Refactor `Surfaces`, `EffectiveSurface`, `Navigation`

**Agent:** `anysys-backend-developer`

**Files:**
- Modify: `app/services/member/surfaces.rb`
- Modify: `app/services/member/effective_surface.rb`
- Modify: `app/services/member/navigation.rb`
- Modify: `spec/services/member/surfaces_spec.rb`
- Modify: `spec/services/member/effective_surface_spec.rb`
- Modify: `spec/services/member/navigation_spec.rb` (if it asserts on legacy bespoke keys)
- Modify: `spec/components/member/top_nav_component_spec.rb` (if it asserts on legacy bespoke keys)
- Modify: `spec/system/member/surface_kit_spec.rb` (only if affected)

**Tasks:**

- [ ] **Step 1: Replace `Surfaces`**

```ruby
# app/services/member/surfaces.rb
# frozen_string_literal: true

module Member
  # Customer-aware accessor over Member::SurfaceSource registry.
  # Member-facing API (.for, .fetch) is wire-compatible with the prior
  # version; new methods (.sources, .source_for, .surfaces_in) drive the
  # admin settings UI.
  module Surfaces
    class << self
      # Sorted list of registered SurfaceSource classes.
      def sources
        Surfaces::SourceRegistry.all
      end

      def source_for(key)
        Surfaces::SourceRegistry.find(key)
      end

      def for(customer:)
        descriptors_with_source = sources.flat_map { |klass|
          klass.new(customer: customer).surfaces.map { |d| [klass.key.to_sym, d] }
        }

        settings_by_key = SurfaceSetting.where(customer_id: customer.id)
                                        .index_by { |s| s.surface_key.to_sym }

        descriptors_with_source.map { |source_key, descriptor|
          EffectiveSurface.new(
            descriptor: descriptor,
            settings:   settings_by_key.fetch(descriptor.key) { NullSurfaceSetting.new },
            source_key: source_key
          )
        }.sort_by(&:position)
      end

      def fetch(key, customer:)
        found = self.for(customer: customer).find { |s| s.key == key.to_sym }
        return found if found

        raise ActiveRecord::RecordNotFound, "no member surface for #{key.inspect}"
      end

      def surfaces_in(source_key:, customer:)
        self.for(customer: customer).select { |e| e.source_key == source_key.to_sym }
      end
    end
  end
end
```

- [ ] **Step 2: Modify `EffectiveSurface` — accept and expose `source_key`**

In `app/services/member/effective_surface.rb`:

Replace the constructor + add accessor:

```ruby
def initialize(descriptor:, settings:, source_key: nil)
  @descriptor = descriptor
  @settings   = settings
  @source_key = source_key&.to_sym
end

def source_key ; @source_key ; end
```

Add `attr_reader :source_key` alongside the existing `attr_reader :descriptor, :settings`.

- [ ] **Step 3: Replace `Navigation`**

```ruby
# app/services/member/navigation.rb
# frozen_string_literal: true

require_relative "navigation/item"

module Member
  module Navigation
    def self.items_for(user)
      Member::Surfaces
        .for(customer: user.customer)
        .map { |effective| item_from_effective(effective) }
        .select { |item| item.visible_to?(user) }
    end

    def self.item_from_effective(effective)
      descriptor = effective.descriptor

      if descriptor.respond_to?(:path_seg)
        Item.new(
          key:     effective.key,
          label:   effective.label,
          icon:    effective.icon,
          path:    ->(customer) {
            seg = descriptor.path_seg.to_s
            seg.empty? ? "/#{customer.id}/member" : "/#{customer.id}/member/#{seg}"
          },
          visible: ->(user) { effective.enabled_for?(user) }
        )
      else
        Item.new(
          key:     effective.key,
          label:   effective.label,
          icon:    effective.icon,
          path:    ->(customer) { "/#{customer.id}/member/#{effective.key}" },
          visible: ->(user) { effective.enabled_for?(user) }
        )
      end
    end
  end
end
```

- [ ] **Step 4: Rewrite `surfaces_spec.rb` per stale-test policy**

```ruby
# spec/services/member/surfaces_spec.rb
require "rails_helper"

RSpec.describe Member::Surfaces do
  let(:customer) { create(:customer) }

  let(:test_surface) do
    Member::Surface.new(
      key:   :test_widget,
      label: "Widgets",
      icon:  :sparkles,
      default_position: 50,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Widgets", scope: ->(_u) { [] },
        columns: [{ key: :x, label: "X", value: ->(r) { r } }],
        empty_state: { headline: "x", body: "y", icon: :z },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(_r) { "T" },
        sections: [{ key: :primary, rows: [{ key: :x, label: "X", value: ->(_r) { "v" } }] }]
      )
    )
  end

  let(:test_source) do
    surface = test_surface
    Class.new(Member::SurfaceSource) do
      define_singleton_method(:key)      { :test_src }
      define_singleton_method(:name)     { "Test"     }
      define_singleton_method(:position) { 99         }
      define_method(:surfaces) { [surface] }
    end
  end

  before do
    Member::Surfaces::SourceRegistry.reset!
    Member::Surfaces::SourceRegistry.register(test_source)
  end
  after { Member::Surfaces::SourceRegistry.reset! }

  describe ".sources / .source_for" do
    it "exposes registered sources sorted by position" do
      expect(described_class.sources).to include(test_source)
    end

    it "looks up by key" do
      expect(described_class.source_for(:test_src)).to eq(test_source)
      expect(described_class.source_for(:nope)).to be_nil
    end
  end

  describe ".for(customer:)" do
    it "returns one EffectiveSurface per descriptor with source_key set" do
      effectives = described_class.for(customer: customer)
      eff = effectives.find { |e| e.key == :test_widget }
      expect(eff).to be_a(Member::EffectiveSurface)
      expect(eff.source_key).to eq(:test_src)
    end

    it "uses the descriptor default_position when no setting exists" do
      eff = described_class.for(customer: customer).find { |e| e.key == :test_widget }
      expect(eff.position).to eq(50)
    end

    it "honors stored SurfaceSetting overrides" do
      setting = Member::SurfaceSetting.create!(
        customer: customer, surface_key: "test_widget", source_key: "test_src", position: 7
      )
      setting.write_overlay(label: "Renamed")
      setting.save!

      eff = described_class.for(customer: customer).find { |e| e.key == :test_widget }
      expect(eff.label).to eq("Renamed")
      expect(eff.position).to eq(7)
    end
  end

  describe ".fetch" do
    it "returns the EffectiveSurface for a known key" do
      expect(described_class.fetch(:test_widget, customer: customer).key).to eq(:test_widget)
    end

    it "raises ActiveRecord::RecordNotFound on unknown keys" do
      expect { described_class.fetch(:nope, customer: customer) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".surfaces_in(source_key:, customer:)" do
    it "filters effectives by source_key" do
      effectives = described_class.surfaces_in(source_key: :test_src, customer: customer)
      expect(effectives.map(&:key)).to eq([:test_widget])
    end

    it "returns [] when source_key is unknown" do
      expect(described_class.surfaces_in(source_key: :phantom, customer: customer)).to eq([])
    end
  end
end
```

- [ ] **Step 5: Update `effective_surface_spec.rb` — add source_key example**

Append:

```ruby
describe "#source_key" do
  it "returns the source_key passed at construction" do
    eff = described_class.new(descriptor: descriptor, settings: Member::NullSurfaceSetting.new, source_key: :modules)
    expect(eff.source_key).to eq(:modules)
  end

  it "returns nil when source_key is not provided" do
    eff = described_class.new(descriptor: descriptor, settings: Member::NullSurfaceSetting.new)
    expect(eff.source_key).to be_nil
  end
end
```

- [ ] **Step 6: Update navigation_spec.rb if it asserts on `:home`/`:profile`/`:security`**

Replace any literal `:home`, `:profile`, `:security` with `:builtin_home`, `:builtin_profile`, `:builtin_security`. Update path expectations only if asserted (paths remain `/member`, `/member/profile`, `/member/security`).

- [ ] **Step 7: Run member suite**

```
bundle exec rspec spec/services/member spec/components/member
```

Fix any spec that breaks because `:home`/`:profile`/`:security` literals moved (stale-test policy: rewrite the spec, not production).

- [ ] **Step 8: Commit**

```
git add app/services/member/surfaces.rb \
        app/services/member/effective_surface.rb \
        app/services/member/navigation.rb \
        spec/services/member
# plus any spec files updated per stale-test policy
git commit -m "refactor(member): drive Surfaces from SourceRegistry; add source_key + path_seg"
```

---

### Slice 1.F — `Operation::Update` rewrite

**Agent:** `anysys-backend-developer`

**Files:**
- Modify: `app/concepts/member/settings/operation/update.rb`
- Modify: `app/concepts/member/settings/contract/update.rb`
- Modify: `spec/concepts/member/settings/operation/update_spec.rb`

**Tasks:**

- [ ] **Step 1: Update contract — drop the inclusion validator**

In `app/concepts/member/settings/contract/update.rb`, remove the `inclusion: { in: ... }` clause from the `surface_key` validation (the new operation handles that customer-aware). Keep `presence: true`.

```ruby
validates :surface_key, presence: true
```

- [ ] **Step 2: Failing spec — update the existing operation spec**

Add to `spec/concepts/member/settings/operation/update_spec.rb`:

```ruby
it "writes source_key from the resolved EffectiveSurface" do
  result = described_class.call(
    customer: customer,
    params: ActionController::Parameters.new(rows: [{ surface_key: "payments", enabled: "1" }])
  )
  expect(result.success?).to be(true)
  row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
  expect(row.source_key).to eq("modules")
end

it "silently drops rows whose source is not editable" do
  Member::Surfaces::SourceRegistry.reset!
  Member::Surfaces::SourceRegistry.register(Member::Sources::Builtin)

  expect {
    described_class.call(
      customer: customer,
      params: ActionController::Parameters.new(
        rows: [{ surface_key: "builtin_home", enabled: "0", label: "ATTACK" }]
      )
    )
  }.not_to change(Member::SurfaceSetting, :count)
ensure
  Member::Surfaces::SourceRegistry.reset!
  [Member::Sources::Builtin, Member::Sources::Modules, Member::Sources::Entities].each(&:register!)
end

it "rejects rows whose surface_key does not resolve for this customer" do
  result = described_class.call(
    customer: customer,
    params: ActionController::Parameters.new(rows: [{ surface_key: "phantom", enabled: "1" }])
  )
  expect(result.success?).to be(false)
end
```

- [ ] **Step 3: Run, confirm red**

- [ ] **Step 4: Modify operation**

In `app/concepts/member/settings/operation/update.rb`, locate the `form.rows.each do |row|` block and replace its body:

```ruby
form.rows.each do |row|
  begin
    effective = Member::Surfaces.fetch(row.surface_key, customer: customer)
  rescue ActiveRecord::RecordNotFound
    form.errors.add(:surface_key, "is not a valid surface for this customer")
    return Result.new(success?: false, errors: form.errors)
  end

  source = Member::Surfaces.source_for(effective.source_key)
  next if source.nil? || !source.editable?

  setting = Member::SurfaceSetting.for_customer_surface(
    customer_id: customer.id, surface_key: row.surface_key
  )
  setting.source_key = effective.source_key.to_s
  setting.enabled    = truthy?(row.enabled)
  setting.position   = row.position.to_i if row.position.present?
  setting.write_overlay(
    label:                   row.label.presence,
    icon:                    row.icon.presence,
    subtitle:                row.subtitle.presence,
    empty_headline:          row.empty_headline.presence,
    empty_body:              row.empty_body.presence,
    per_page:                (row.per_page.presence && row.per_page.to_i),
    visible_column_keys:     Array(row.visible_column_keys),
    visible_detail_row_keys: Array(row.visible_detail_row_keys),
    visible_section_keys:    Array(row.visible_section_keys)
  )
  setting.save!
end
```

- [ ] **Step 5: Update `for_customer_surface` — accept `source_key`**

In `app/models/member/surface_setting.rb`, change:

```ruby
def self.for_customer_surface(customer_id:, surface_key:)
  find_or_create_by!(customer_id: customer_id, surface_key: surface_key.to_s) do |row|
    # source_key is set by the caller (operation) before save
  end
end
```

Note: `find_or_create_by!` may run validations on create. To avoid the chicken-and-egg with the source_key validation, change to:

```ruby
def self.for_customer_surface(customer_id:, surface_key:)
  scope = where(customer_id: customer_id, surface_key: surface_key.to_s)
  scope.first || scope.new
end
```

The operation now sets `source_key` before calling `save!`.

- [ ] **Step 6: Run, confirm green**

```
bundle exec rspec spec/concepts/member/settings spec/models/member/surface_setting_spec.rb
```

- [ ] **Step 7: Commit**

```
git add app/concepts/member/settings/ \
        app/models/member/surface_setting.rb \
        spec/concepts/member/settings/
git commit -m "feat(member): operation writes source_key, drops !editable rows"
```

**Phase 1 checkpoint:** Orchestrator runs `bundle exec rspec spec/services/member spec/models/member spec/concepts/member` and verifies all green. Member-facing routes (`/:cid/member/payments`) should still work end-to-end. Proceed to Phase 2.

---

## Phase 2 — Admin surface (parallel)

**Three slices fan out concurrently** (one Agent dispatch per slice in a single message):

### Slice 2.A — Routes + 3 controllers + auth

**Agent:** `anysys-security-engineer`

**Why this role:** Slice creates new admin URLs and controllers under `/:cid/admin/...`. Per AGENTS.md, admin routes need `require_admin_or_owner!` guards; record-level reads must scope by `customer_id`. Security-engineer is the only role that may add routes + controllers per the agent definitions.

**Files:**
- Modify: `config/routes.rb`
- Rename: `app/controllers/admin/settings/members_controller.rb` (rewrite show)
- Create: `app/controllers/admin/settings/member_sources_controller.rb`
- Create: `app/controllers/admin/settings/member_surfaces_controller.rb`
- Create: `app/presenters/admin/settings/member_hub_card_presenter.rb`

**Reference:** spec §6 (URL table) + §8 (controller skeletons). Implement both verbatim.

**Tasks:**

- [ ] **Step 1: Routes — replace existing `resource :member` block**

In `config/routes.rb` around line 132:

```ruby
namespace :settings do
  resource :member, only: %i[show update],
                         controller: "settings/members" do
    resources :sources,  only: %i[show update],
                         param:  :key,
                         controller: "settings/member_sources" do
      resources :surfaces, only: %i[show update],
                           param:  :key,
                           controller: "settings/member_surfaces"
    end
  end

  namespace :modules do
    # ... existing payments / authentication / captcha sub-routes (unchanged) ...
  end
end
```

- [ ] **Step 2: Verify routes**

```
bundle exec rails routes -g admin/settings/member
```

Expected: 6 routes (show/update on each of the three nested resources).

- [ ] **Step 3: Hub presenter**

```ruby
# app/presenters/admin/settings/member_hub_card_presenter.rb
# frozen_string_literal: true

module Admin
  module Settings
    class MemberHubCardPresenter
      def initialize(source_class:, customer:)
        @source_class = source_class
        @customer     = customer
      end

      attr_reader :source_class, :customer

      def key          ; source_class.key.to_sym ; end
      def name         ; source_class.name        ; end
      def description  ; source_class.description ; end
      def editable?    ; source_class.editable?   ; end

      def total_count
        effectives.size
      end

      def enabled_count
        effectives.count(&:enabled?)
      end

      def configure_path
        "/#{customer.id}/admin/settings/member/sources/#{key}"
      end

      private

      def effectives
        @effectives ||= ::Member::Surfaces.surfaces_in(source_key: key, customer: customer)
      end
    end
  end
end
```

- [ ] **Step 4: Hub controller (rewrite)**

Replace `app/controllers/admin/settings/members_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    class MembersController < ApplicationController
      dashboard_menu_item :settings

      def show
        @hub_cards = ::Member::Surfaces.sources.map do |source_class|
          ::Admin::Settings::MemberHubCardPresenter.new(
            source_class: source_class,
            customer:     current_customer
          )
        end
      end

      def update
        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member",
                      notice: "Member surface settings saved."
        else
          @hub_cards = []
          flash.now[:alert] = result.errors.full_messages.join(", ") if result.errors.respond_to?(:full_messages)
          render :show, status: :unprocessable_entity
        end
      end
    end
  end
end
```

- [ ] **Step 5: Per-source controller**

```ruby
# app/controllers/admin/settings/member_sources_controller.rb
# frozen_string_literal: true

module Admin
  module Settings
    class MemberSourcesController < ApplicationController
      dashboard_menu_item :settings

      before_action :load_source

      def show
        @source_name = @source.name
        @editable    = @source.editable?
        @rows        = ::Member::Surfaces.surfaces_in(
          source_key: @source.key, customer: current_customer
        ).map { |effective| ::Admin::Settings::MemberRowPresenter.new(effective: effective) }
      end

      def update
        return head(:forbidden) unless @source.editable?

        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member/sources/#{@source.key}",
                      notice: "Saved."
        else
          show
          render :show, status: :unprocessable_entity
        end
      end

      private

      def load_source
        @source = ::Member::Surfaces.source_for(params[:key]) or raise ActiveRecord::RecordNotFound
      end
    end
  end
end
```

- [ ] **Step 6: Per-surface controller**

```ruby
# app/controllers/admin/settings/member_surfaces_controller.rb
# frozen_string_literal: true

module Admin
  module Settings
    class MemberSurfacesController < ApplicationController
      dashboard_menu_item :settings

      before_action :load_surface

      def show
        @presenter = ::Admin::Settings::MemberRowPresenter.new(effective: @effective)
      end

      def update
        return head(:forbidden) unless @source.editable?

        result = ::Member::Settings::Operation::Update.call(
          customer: current_customer,
          params:   params.fetch(:member_settings, {})
        )
        if result.success?
          redirect_to "/#{current_customer.id}/admin/settings/member/sources/#{@source.key}/surfaces/#{@effective.key}",
                      notice: "Surface saved."
        else
          @presenter = ::Admin::Settings::MemberRowPresenter.new(effective: @effective)
          render :show, status: :unprocessable_entity
        end
      end

      private

      def load_surface
        @source = ::Member::Surfaces.source_for(params[:source_key]) or raise ActiveRecord::RecordNotFound
        @effective = ::Member::Surfaces.fetch(params[:key], customer: current_customer)
        raise ActiveRecord::RecordNotFound unless @effective.source_key == @source.key.to_sym
      end
    end
  end
end
```

- [ ] **Step 7: Auth verification — admin gate is the URL prefix**

The `/admin/*` URL gate is enforced by the surrounding admin namespace. No additional ability changes required (admin/owner abilities already grant `:manage, :all`). Read-only built-in source returns `head :forbidden` on PATCH.

- [ ] **Step 8: Commit**

```
git add config/routes.rb \
        app/controllers/admin/settings/members_controller.rb \
        app/controllers/admin/settings/member_sources_controller.rb \
        app/controllers/admin/settings/member_surfaces_controller.rb \
        app/presenters/admin/settings/member_hub_card_presenter.rb
git commit -m "feat(admin): nested member settings routes + 3 controllers"
```

---

### Slice 2.B — ViewComponents + views + Stimulus

**Agent:** `anysys-frontend-developer`

**Why this role:** Slice creates view components, ERB, and a Stimulus controller. Per the agent definition: ViewComponent + ERB + Stimulus + Tailwind only; no models/migrations/routes/controllers.

**Files:**
- Create: `app/components/admin/settings/member_hub_card_component.rb`
- Create: `app/components/admin/settings/member_hub_card_component.html.erb`
- Create: `app/components/admin/settings/member_source_row_component.rb`
- Create: `app/components/admin/settings/member_source_row_component.html.erb`
- Create: `app/components/admin/settings/member_surface_form_component.rb`
- Create: `app/components/admin/settings/member_surface_form_component.html.erb`
- Create: `app/views/admin/settings/member_sources/show.html.erb`
- Create: `app/views/admin/settings/member_surfaces/show.html.erb`
- Create: `app/javascript/controllers/auto_submit_controller.js`
- Modify: `app/views/admin/settings/members/show.html.erb` (now the hub)
- Delete: `app/components/admin/settings/member_bespoke_card_component.rb` and its `.html.erb`
- Delete: `app/components/admin/settings/member_surface_card_component.rb` and its `.html.erb` (replaced by `member_surface_form_component`)
- Create: `spec/components/admin/settings/member_hub_card_component_spec.rb`
- Create: `spec/components/admin/settings/member_source_row_component_spec.rb`
- Create: `spec/components/admin/settings/member_surface_form_component_spec.rb`
- Delete: `spec/components/admin/settings/member_surface_card_component_spec.rb`

**Reference:** spec §7.3 / §7.4 / §7.5 for layouts.

**Tasks:**

- [ ] **Step 1: Hub card component spec**

```ruby
# spec/components/admin/settings/member_hub_card_component_spec.rb
require "rails_helper"

RSpec.describe Admin::Settings::MemberHubCardComponent, type: :component do
  let(:customer) { create(:customer) }

  let(:editable_presenter) do
    instance_double(
      Admin::Settings::MemberHubCardPresenter,
      key: :modules, name: "Modules",
      description: "Read-only surfaces shipped by feature modules.",
      editable?: true, total_count: 3, enabled_count: 2,
      configure_path: "/#{customer.id}/admin/settings/member/sources/modules"
    )
  end

  let(:locked_presenter) do
    instance_double(
      Admin::Settings::MemberHubCardPresenter,
      key: :builtin, name: "Built-in",
      description: "Always-visible.", editable?: false,
      total_count: 3, enabled_count: 3,
      configure_path: "/#{customer.id}/admin/settings/member/sources/builtin"
    )
  end

  it "renders source name and description" do
    render_inline(described_class.new(presenter: editable_presenter))
    expect(page).to have_text("Modules")
    expect(page).to have_text("Read-only surfaces shipped by feature modules.")
  end

  it "shows count summary when editable" do
    render_inline(described_class.new(presenter: editable_presenter))
    expect(page).to have_text("3 surfaces")
    expect(page).to have_text("2 enabled")
  end

  it "renders 'Configure' CTA for editable sources" do
    render_inline(described_class.new(presenter: editable_presenter))
    expect(page).to have_link("Configure", href: editable_presenter.configure_path)
  end

  it "renders 'View' CTA + locked badge for non-editable sources" do
    render_inline(described_class.new(presenter: locked_presenter))
    expect(page).to have_link("View", href: locked_presenter.configure_path)
    expect(page).to have_text("Locked")
  end
end
```

- [ ] **Step 2: Hub card component implementation**

```ruby
# app/components/admin/settings/member_hub_card_component.rb
# frozen_string_literal: true

module Admin
  module Settings
    class MemberHubCardComponent < ApplicationComponent
      attr_reader :presenter
      def initialize(presenter:) ; @presenter = presenter ; end

      def cta_label   ; presenter.editable? ? "Configure" : "View" ; end
      def cta_classes ; "btn btn-ghost text-sm" ; end
    end
  end
end
```

```erb
<%# app/components/admin/settings/member_hub_card_component.html.erb %>
<section class="card p-6 mb-4">
  <header class="flex items-center justify-between">
    <div>
      <h2 class="text-lg font-semibold flex items-center gap-2">
        <%= presenter.name %>
        <% unless presenter.editable? %>
          <span class="badge badge-default text-xs">Locked</span>
        <% end %>
      </h2>
      <p class="text-sm text-text-muted mt-1"><%= presenter.description %></p>
    </div>
    <%= link_to cta_label, presenter.configure_path, class: cta_classes %>
  </header>
  <p class="text-xs text-text-muted mt-3">
    <%= pluralize(presenter.total_count, "surface") %><%
    %><% if presenter.editable? %> &mdash; <%= presenter.enabled_count %> enabled<% end %>
  </p>
</section>
```

- [ ] **Step 3: Source row component spec + impl**

```ruby
# spec/components/admin/settings/member_source_row_component_spec.rb
require "rails_helper"

RSpec.describe Admin::Settings::MemberSourceRowComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:descriptor) { FeatureModules::Payment::MemberSurface }
  let(:effective) do
    Member::EffectiveSurface.new(
      descriptor: descriptor,
      settings:   Member::NullSurfaceSetting.new,
      source_key: :modules
    )
  end
  let(:presenter) { Admin::Settings::MemberRowPresenter.new(effective: effective) }

  context "editable source" do
    it "renders the surface label" do
      render_inline(described_class.new(presenter: presenter, editable: true, customer: customer))
      expect(page).to have_text("Payments")
    end

    it "renders an enabled checkbox wrapped in an auto-submitting form" do
      render_inline(described_class.new(presenter: presenter, editable: true, customer: customer))
      expect(page).to have_css("form[data-controller~='auto-submit']")
      expect(page).to have_css("input[type='checkbox'][name='member_settings[rows][0][enabled]']")
    end

    it "renders an Edit link to the per-surface page" do
      render_inline(described_class.new(presenter: presenter, editable: true, customer: customer))
      expect(page).to have_link("Edit",
        href: "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments")
    end
  end

  context "non-editable source" do
    it "renders read-only without a form wrapper" do
      render_inline(described_class.new(presenter: presenter, editable: false, customer: customer))
      expect(page).not_to have_css("form")
      expect(page).to have_text("Payments")
    end
  end
end
```

```ruby
# app/components/admin/settings/member_source_row_component.rb
# frozen_string_literal: true

module Admin
  module Settings
    class MemberSourceRowComponent < ApplicationComponent
      attr_reader :presenter, :editable, :customer
      def initialize(presenter:, editable:, customer:)
        @presenter = presenter
        @editable  = editable
        @customer  = customer
      end

      def edit_path
        "/#{customer.id}/admin/settings/member/sources/#{presenter.effective.source_key}/surfaces/#{presenter.surface_key}"
      end

      def update_path
        "/#{customer.id}/admin/settings/member/sources/#{presenter.effective.source_key}"
      end
    end
  end
end
```

```erb
<%# app/components/admin/settings/member_source_row_component.html.erb %>
<% if editable %>
  <%= form_with url: update_path, method: :patch, local: true,
                data: { controller: "auto-submit" },
                class: "flex items-center justify-between py-3 border-b border-border-subtle" do %>
    <input type="hidden" name="member_settings[rows][0][surface_key]" value="<%= presenter.surface_key %>"/>
    <div class="flex items-center gap-3">
      <span class="font-medium"><%= presenter.label %></span>
      <span class="text-xs text-text-muted font-mono">position <%= presenter.position %></span>
    </div>
    <div class="flex items-center gap-3">
      <label class="inline-flex items-center gap-2 text-sm">
        <input type="hidden" name="member_settings[rows][0][enabled]" value="0"/>
        <input type="checkbox"
               name="member_settings[rows][0][enabled]"
               value="1"
               <%= "checked" if presenter.enabled? %>
               data-action="change->auto-submit#submit"
               class="rounded"/>
        <span>Enabled</span>
      </label>
      <%= link_to "Edit", edit_path, class: "btn btn-ghost text-sm" %>
    </div>
  <% end %>
<% else %>
  <div class="flex items-center justify-between py-3 border-b border-border-subtle opacity-80">
    <div class="flex items-center gap-3">
      <span class="font-medium"><%= presenter.label %></span>
      <span class="text-xs text-text-muted font-mono">position <%= presenter.position %></span>
    </div>
    <span class="badge badge-default text-xs">Locked</span>
  </div>
<% end %>
```

- [ ] **Step 4: Auto-submit Stimulus controller**

```js
// app/javascript/controllers/auto_submit_controller.js
import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form when an input fires the `submit` action.
// Used by the per-source enabled-toggle to persist on change.
export default class extends Controller {
  submit() {
    if (this.element.requestSubmit) {
      this.element.requestSubmit()
    } else {
      this.element.submit()
    }
  }
}
```

- [ ] **Step 5: Surface form component spec + impl**

The spec mirrors the prior `member_surface_card_component_spec.rb` (ported / renamed). Implementation reuses the existing `MemberSurfaceCardComponent`'s ERB body, wrapped in a `<form>` posting to the nested route. See spec §7.5.

```ruby
# spec/components/admin/settings/member_surface_form_component_spec.rb
require "rails_helper"

RSpec.describe Admin::Settings::MemberSurfaceFormComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:descriptor) { FeatureModules::Payment::MemberSurface }
  let(:effective) do
    Member::EffectiveSurface.new(
      descriptor: descriptor,
      settings:   Member::NullSurfaceSetting.new,
      source_key: :modules
    )
  end
  let(:presenter) { Admin::Settings::MemberRowPresenter.new(effective: effective) }

  it "renders the surface label and form action" do
    render_inline(described_class.new(presenter: presenter, customer: customer))
    expect(page).to have_text("Payments")
    expect(page).to have_css("form[action$='/admin/settings/member/sources/modules/surfaces/payments']")
  end

  it "renders enabled checkbox and label/icon/subtitle inputs" do
    render_inline(described_class.new(presenter: presenter, customer: customer))
    expect(page).to have_css("input[type='checkbox'][name='member_settings[rows][0][enabled]']")
    expect(page).to have_css("input[name='member_settings[rows][0][label]']")
    expect(page).to have_css("input[name='member_settings[rows][0][icon]']")
    expect(page).to have_css("input[name='member_settings[rows][0][subtitle]']")
  end

  it "renders empty-state copy fields" do
    render_inline(described_class.new(presenter: presenter, customer: customer))
    expect(page).to have_css("input[name='member_settings[rows][0][empty_headline]']")
    expect(page).to have_css("textarea[name='member_settings[rows][0][empty_body]']")
  end

  it "renders one column checkbox per descriptor column with hideable=false locked" do
    render_inline(described_class.new(presenter: presenter, customer: customer))
    locked = page.find("input[name='member_settings[rows][0][visible_column_keys][]'][value='amount']")
    expect(locked[:disabled]).to eq("disabled")
  end

  it "renders surface_key as a hidden field" do
    render_inline(described_class.new(presenter: presenter, customer: customer))
    expect(page).to have_css("input[type='hidden'][name='member_settings[rows][0][surface_key]'][value='payments']")
  end
end
```

```ruby
# app/components/admin/settings/member_surface_form_component.rb
# frozen_string_literal: true

module Admin
  module Settings
    class MemberSurfaceFormComponent < ApplicationComponent
      attr_reader :presenter, :customer

      def initialize(presenter:, customer:)
        @presenter = presenter
        @customer  = customer
      end

      def form_url
        "/#{customer.id}/admin/settings/member/sources/#{presenter.effective.source_key}/surfaces/#{presenter.surface_key}"
      end

      def name_for(field)       ; "member_settings[rows][0][#{field}]"   ; end
      def array_name_for(field) ; "member_settings[rows][0][#{field}][]" ; end
    end
  end
end
```

ERB body — port the contents of the existing `member_surface_card_component.html.erb` verbatim, but:
- Wrap the entire `<section>` body in `<%= form_with url: form_url, method: :patch, local: true do %>...<% end %>`
- Inside the form, keep the existing visible field structure (label/icon/subtitle/position/per_page/empty_state/columns/sections/rows). The hidden `surface_key` and `enabled` rendering stays.
- At the bottom of the form, add `<div class="flex justify-end gap-3 mt-6"><button type="submit" class="btn btn-primary">Save</button></div>`.

- [ ] **Step 6: View files**

```erb
<%# app/views/admin/settings/members/show.html.erb (rewrite the existing) %>
<%= render BreadcrumbsComponent.new(crumbs: [
      { label: "Settings",    path: "/#{current_customer.id}/admin/settings" },
      { label: "Member", path: nil }
    ]) %>

<div class="mb-8">
  <h1 class="text-subtitle">Member surfaces</h1>
  <p class="mt-1 text-body-sm">Choose what your members see and how it's labelled.</p>
</div>

<% @hub_cards.each do |card| %>
  <%= render Admin::Settings::MemberHubCardComponent.new(presenter: card) %>
<% end %>
```

```erb
<%# app/views/admin/settings/member_sources/show.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
      { label: "Settings",     path: "/#{current_customer.id}/admin/settings" },
      { label: "Member",  path: "/#{current_customer.id}/admin/settings/member" },
      { label: @source_name,   path: nil }
    ]) %>

<div class="mb-8">
  <h1 class="text-subtitle"><%= @source_name %></h1>
</div>

<section class="card p-2">
  <% @rows.each do |row_presenter| %>
    <%= render Admin::Settings::MemberSourceRowComponent.new(
          presenter: row_presenter, editable: @editable, customer: current_customer
        ) %>
  <% end %>
</section>
```

```erb
<%# app/views/admin/settings/member_surfaces/show.html.erb %>
<%= render BreadcrumbsComponent.new(crumbs: [
      { label: "Settings",     path: "/#{current_customer.id}/admin/settings" },
      { label: "Member",  path: "/#{current_customer.id}/admin/settings/member" },
      { label: @presenter.effective.source_key.to_s.titleize,
        path: "/#{current_customer.id}/admin/settings/member/sources/#{@presenter.effective.source_key}" },
      { label: @presenter.label, path: nil }
    ]) %>

<div class="mb-8">
  <h1 class="text-subtitle"><%= @presenter.label %></h1>
</div>

<%= render Admin::Settings::MemberSurfaceFormComponent.new(
      presenter: @presenter, customer: current_customer
    ) %>
```

- [ ] **Step 7: Delete the old components and their specs**

```
git rm app/components/admin/settings/member_bespoke_card_component.rb \
       app/components/admin/settings/member_bespoke_card_component.html.erb \
       app/components/admin/settings/member_surface_card_component.rb \
       app/components/admin/settings/member_surface_card_component.html.erb
# Old surface_card_component_spec.rb may not exist if the prior plan didn't ship it; if it does:
git rm spec/components/admin/settings/member_surface_card_component_spec.rb 2>/dev/null || true
```

- [ ] **Step 8: Run new component specs**

```
bundle exec rspec spec/components/admin/settings
```

- [ ] **Step 9: Commit**

```
git add app/components/admin/settings/ \
        app/views/admin/settings/ \
        app/javascript/controllers/auto_submit_controller.js \
        spec/components/admin/settings/
git commit -m "feat(admin): hub + source row + surface form components; delete bespoke card"
```

---

### Slice 2.C — Request + system specs

**Agent:** `anysys-qa-engineer`

**Why this role:** QA-engineer owns RSpec specs and never edits production code. The request and system specs lock in the round-trip behavior across the three controllers.

**Files:**
- Replace: `spec/requests/admin/settings/members_spec.rb` (existed under prior plan; rewrite for hub semantics)
- Create: `spec/requests/admin/settings/member_sources_spec.rb`
- Create: `spec/requests/admin/settings/member_surfaces_spec.rb`
- Replace: `spec/system/admin/settings/members_spec.rb` (rewrite for drill-down)
- Create: `spec/system/admin/settings/member_entities_spec.rb`

**Tasks:**

- [ ] **Step 1: Hub request spec**

```ruby
# spec/requests/admin/settings/members_spec.rb
require "rails_helper"

RSpec.describe "Admin Settings — Member (hub)", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:member)   { create(:user, :member, customer: customer) }

  before do
    payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: payment_module
    ) { |a| a.status = :active }
  end

  describe "GET /:cid/admin/settings/member" do
    it "renders three source cards for an admin (Built-in / Modules / Entities)" do
      sign_in admin
      get "/#{customer.id}/admin/settings/member"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Built-in")
      expect(response.body).to include("Modules")
      expect(response.body).to include("Entities")
    end

    it "denies a member" do
      sign_in member
      get "/#{customer.id}/admin/settings/member"
      expect(response).not_to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 2: Per-source request spec**

```ruby
# spec/requests/admin/settings/member_sources_spec.rb
require "rails_helper"

RSpec.describe "Admin Settings — Member Source", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  before do
    payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: payment_module
    ) { |a| a.status = :active }
    sign_in admin
  end

  describe "GET .../sources/modules" do
    it "renders the source row list" do
      get "/#{customer.id}/admin/settings/member/sources/modules"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payments")
      expect(response.body).to include("Edit")
    end
  end

  describe "GET .../sources/builtin" do
    it "renders the built-in source as locked (no Edit links)" do
      get "/#{customer.id}/admin/settings/member/sources/builtin"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Locked")
    end
  end

  describe "PATCH .../sources/builtin" do
    it "returns 403 because the source is not editable" do
      patch "/#{customer.id}/admin/settings/member/sources/builtin",
            params: { member_settings: { rows: [{ surface_key: "builtin_home", enabled: "0" }] } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH .../sources/modules" do
    it "persists an inline toggle" do
      patch "/#{customer.id}/admin/settings/member/sources/modules",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "0" }]
              }
            }
      expect(response).to redirect_to("/#{customer.id}/admin/settings/member/sources/modules")
      row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      expect(row.enabled).to be(false)
    end
  end

  describe "GET .../sources/phantom" do
    it "404s on unknown source" do
      get "/#{customer.id}/admin/settings/member/sources/phantom"
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 3: Per-surface request spec**

```ruby
# spec/requests/admin/settings/member_surfaces_spec.rb
require "rails_helper"

RSpec.describe "Admin Settings — Member Surface", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  before do
    payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: payment_module
    ) { |a| a.status = :active }
    sign_in admin
  end

  describe "GET .../sources/modules/surfaces/payments" do
    it "renders the per-surface form" do
      get "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payments")
      expect(response.body).to include("Save")
    end
  end

  describe "GET with mismatched source/surface" do
    it "404s when surface does not belong to source" do
      get "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/payments"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH .../sources/modules/surfaces/payments" do
    it "saves the overlay and round-trips on next GET" do
      patch "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "1", label: "Donations", per_page: "5" }]
              }
            }
      expect(response).to redirect_to("/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments")

      get "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments"
      expect(response.body).to include("Donations")
    end

    it "returns 422 on invalid input" do
      patch "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "1", per_page: "999999" }]
              }
            }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH on built-in surface" do
    it "returns 403" do
      patch "/#{customer.id}/admin/settings/member/sources/builtin/surfaces/builtin_home",
            params: { member_settings: { rows: [{ surface_key: "builtin_home", enabled: "0" }] } }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 4: System drill-down spec**

```ruby
# spec/system/admin/settings/members_spec.rb
require "rails_helper"

RSpec.describe "Admin Settings — Member (system)", type: :system do
  def page ; Capybara.current_session ; end

  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:member)   { create(:user, :member, customer: customer) }

  before do
    payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: payment_module
    ) { |a| a.status = :active }
  end

  it "drills hub → modules → payments, renames to Donations, and member nav reflects it" do
    sign_in admin
    visit "/#{customer.id}/admin/settings/member"
    expect(page).to have_text("Modules")

    click_link "Configure", match: :first
    expect(page).to have_text("Payments")

    click_link "Edit", match: :first
    fill_in "member_settings[rows][0][label]", with: "Donations"
    click_button "Save"
    expect(page).to have_text("Surface saved.")

    visit "/#{customer.id}/auth/sign_out"
    sign_in member
    visit "/#{customer.id}/member"
    expect(page).to have_link("Donations")
  end
end
```

- [ ] **Step 5: System entities spec**

```ruby
# spec/system/admin/settings/member_entities_spec.rb
require "rails_helper"

RSpec.describe "Admin Settings — Member Entities", type: :system do
  def page ; Capybara.current_session ; end

  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  it "shows a freshly created Entity under the Entities source" do
    Entity.create!(customer_id: customer.id, name: "Course", element_type: "custom")

    sign_in admin
    visit "/#{customer.id}/admin/settings/member"
    expect(page).to have_text("Entities")

    within("section", text: "Entities") { click_link "Configure" }
    expect(page).to have_text("Course")
  end
end
```

- [ ] **Step 6: Run, expect green; commit**

```
bundle exec rspec spec/requests/admin/settings spec/system/admin/settings
git add spec/requests/admin/settings spec/system/admin/settings
git commit -m "test(admin): request + system specs for hub / source / surface"
```

**Phase 2 checkpoint:** Orchestrator runs the full member + admin spec set. Three slices' commits should compose cleanly. Proceed to Phase 3.

---

## Phase 3 — Verification + review (sequential)

### Slice 3.A — Release smoke

**Agent:** `anysys-release-engineer`

**Tasks:**

- [ ] **Step 1: Run targeted RSpec on touched files**

```
bundle exec rspec spec/services/member spec/components/member \
                  spec/requests/member spec/system/member \
                  spec/models/member spec/concepts/member \
                  spec/components/admin/settings spec/requests/admin/settings \
                  spec/system/admin/settings
```

Expected: all green.

- [ ] **Step 2: Rebuild assets**

```
rm -f public/assets/.manifest.json
bundle exec rails tailwindcss:build
```

- [ ] **Step 3: Boot dev server**

```
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

- [ ] **Step 4: Smoke endpoints**

```
curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3000/<cid>/admin/settings/member
curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3000/<cid>/admin/settings/member/sources/modules
curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3000/<cid>/admin/settings/member/sources/modules/surfaces/payments
curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3000/<cid>/member/payments
```

Expected: 200 / 200 / 200 / 302 (redirect to sign-in if SKIP_AUTH does not bypass member gate; otherwise 200).

- [ ] **Step 5: Stop server, report PASS/FAIL with trimmed output**

---

### Slice 3.B — Tech-lead review

**Agent:** `anysys-tech-lead`

Review the diff against AGENTS.md conventions:

- Three URL areas (admin/member/public) — admin URLs all under `/:cid/admin/`
- Module URL & resource categorization — settings under `/:cid/admin/settings/`
- Multi-tenant `customer_id` scoping — every `SurfaceSetting` read/write goes through `current_customer`
- ViewComponent purity — no inline ERB outside components, no `<style>`, no inline `<script>`
- Tailwind/Stimulus purity — no custom CSS, no other JS framework, Stimulus controller declared in `app/javascript/controllers/`
- Trailblazer convention — `Operation::Update` + Reform contract; thin model
- No backward-compatibility hacks — old `BESPOKE_ITEMS` deleted, old `descriptor_keys`/`register` helpers deleted

Report findings; no edits.

---

### Slice 3.C — Code review

**Agent:** `anysys-code-reviewer`

Diff-only review for:

- SQL injection / mass-assignment in the operation (params should be filtered)
- Missing `customer_id` scoping on any read or write
- Missing auth guards on the three new controllers
- N+1 in `Surfaces.for(customer:)` (sources walking modules / entities)
- Error handling at boundaries (operation result error path; per-source 404)
- Missing tests for any new public surface

Report findings; no edits.

---

## Self-review (orchestrator)

Run before declaring complete:

**Spec coverage check:**
- §3.1 layered architecture — Phase 0 + 1 ✓
- §3.2 surface key namespacing — Slice 1.B (`builtin_*`), 1.C (no prefix), 1.D (`entity_*`) ✓
- §3.3 Navigation refactor — Slice 1.E ✓
- §4.1 SurfaceSource base class — Slice 0.A ✓
- §4.2 SourceRegistry — Slice 0.A ✓
- §4.3 Sources::Builtin + BuiltinSurface — Slice 1.B ✓
- §4.4 Sources::Modules — Slice 1.C ✓
- §4.5 Sources::Entities — Slice 1.D ✓
- §4.6 EntitySurfaceBuilder + EntityEntry.none scope — Slice 1.D ✓
- §4.7 Surfaces public-API additions — Slice 1.E ✓
- §5 source_key migration + validation — Slice 1.A ✓
- §6.1/6.2 nested admin routes + 3 controllers + auth — Slice 2.A ✓
- §6.3 settings sidebar unchanged — no slice (verified manually in tech-lead review) ✓
- §7.1/7.2/7.3/7.4/7.5 hub, source, surface views + components — Slice 2.B ✓
- §8 operation drops !editable rows + writes source_key — Slice 1.F ✓
- §9 refactor table — covered by individual slices ✓
- §10 testing strategy — Slices 0.A, 1.A–1.F, 2.B, 2.C cover unit/component/request/system ✓
- §11 acceptance criteria — Phase 3 verification ✓
- §12 risks — addressed inline (entity ownership = §4.6.2) ✓

**Type-consistency check:**
- `EffectiveSurface#source_key` (returns `Symbol`) — Slice 1.E adds; Slice 1.F (operation) and 2.A (controllers) consume it as Symbol ✓
- `Surfaces.surfaces_in(source_key:, customer:)` — Slice 1.E defines; Slices 2.A (sources controller) and 2.B (hub presenter) consume ✓
- `Member::Surfaces.source_for(key)` — Slice 1.E defines (returns class or nil); Slice 2.A consumes (`@source.editable?`, `@source.key`, `@source.name`) ✓
- `BuiltinSurface#path_seg` — Slice 1.B defines; Slice 1.E (Navigation) consumes ✓
- Operation's `for_customer_surface` change — Slice 1.F revises to plain `where.first || .new` so `source_key` can be set before `save!` ✓

No placeholders. No TBDs.

---

## Execution handoff

Plan saved to `docs/superpowers/plans/2026-05-24-member-settings-scalable.md`.

Recommended dispatch:
- **Phase 0** → one `anysys-backend-developer` dispatch.
- **Phase 1** → one `anysys-backend-developer` dispatch (covers 1.A–1.F as one session, since they touch overlapping files); orchestrator reviews after each slice's commit.
- **Phase 2** → three parallel dispatches in one message: `anysys-security-engineer` (2.A), `anysys-frontend-developer` (2.B), `anysys-qa-engineer` (2.C).
- **Phase 3** → sequential: release-engineer → tech-lead → code-reviewer.
