# Member Admin Settings & Effective Surface Overlay — Implementation Plan

> **For agentic workers:** Use **superpowers:executing-plans** to drive task-by-task. Each task is TDD: red → green → commit.

**Goal:** Layer a per-tenant admin overlay on top of the descriptor-driven member surfaces shipped on 2026-05-23. Customer admins control which surfaces appear, what they're called, what they look like, and what's hidden — all from `/:cid/admin/settings/member`. No code change, no new descriptor file, just a form.

**Why a fresh plan:** the prior plan (2026-05-23) silently dropped phases §5 (effective overlay), §6 (storage), §7 (admin page) of the design spec. Acceptance criterion #6 — "the saved overlay is visible on the next member visit" — was never built. This plan implements that gap, end to end.

**Deliver MAXIMUM configurability** within what the spec authorizes:
- Visibility (enable / disable)
- Label, icon, subtitle (header copy)
- Empty-state headline + body (override descriptor copy when the tenant prefers different wording for "No payments yet")
- Navigation position (lower → higher in nav)
- Page size (1–200)
- Visible columns (subset of descriptor columns; `hideable: false` columns are locked)
- Visible detail rows (subset of descriptor rows; `hideable: false` rows are locked)
- Visible detail sections (subset of descriptor sections; `hideable: false` sections are locked)
- All knobs round-trip via the `config` JSON blob — adding a new knob later requires no migration

**NOT admin-controlled (deliberate, per spec §7.4):**
- The query / scope (security-critical)
- Format vocabulary keys (presentation owned by descriptor)
- Bespoke entries (Home / Profile / Security) — listed read-only, locked

**Tech stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, ViewComponent, Tailwind, Stimulus, Trailblazer (Reform + Activity), `JsonSerializable` concern. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-23-member-page-kit-design.md` §4.1, §4.2, §4.3, §5, §6, §7, §10 acceptance criterion #6.

---

## Phase 0 — Descriptor upgrade

### Task 1 — Add `:default_position`, `:key`, `:hideable` to descriptor shapes

**Files:**
- Modify: `app/services/member/surface.rb`
- Modify: `app/services/feature_modules/payment/member_surface.rb`
- Modify: `spec/services/member/surface_spec.rb` (and dependent component / request specs)

The descriptor shape so far has no `:default_position` on the surface, and no `:key` / `:hideable` on columns / sections / rows. The overlay layer needs both: `:default_position` for fallback nav order, `:key` for stable identification of what to hide, `:hideable: false` to lock load-bearing columns.

- [ ] **Step 1: Update `Member::Surface` struct**

Replace `app/services/member/surface.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Descriptor for a read-only member surface (index + detail).
  # Modules ship one of these as FeatureModules::<Name>::MemberSurface.
  Surface = Struct.new(:key, :label, :icon, :enabled_for, :index, :detail, :default_position,
                       keyword_init: true)

  class Surface
    KEY_RE = /\A[a-z][a-z0-9_]*\z/.freeze
    DEFAULT_POSITION = 100

    Index = Struct.new(:title, :subtitle, :scope, :columns, :empty_state, :per_page,
                       keyword_init: true) do
      def per_page_or_default
        per_page.presence || 20
      end
    end

    Detail = Struct.new(:title, :subtitle, :meta, :sections, keyword_init: true)

    def enabled_for?(user) = enabled_for.call(user)

    def default_position_or_default
      default_position.presence || DEFAULT_POSITION
    end

    def validate!
      raise ArgumentError, "key must be a lowercase identifier (got: #{key.inspect})" unless key.to_s.match?(KEY_RE)
      raise ArgumentError, "label is required"  if label.to_s.strip.empty?
      raise ArgumentError, "index must be a Member::Surface::Index"  unless index.is_a?(Index)
      raise ArgumentError, "detail must be a Member::Surface::Detail" unless detail.is_a?(Detail)

      validate_index!(index)
      validate_detail!(detail)
      true
    end

    private

    def validate_index!(idx)
      raise ArgumentError, "index.columns must be a non-empty array" if Array(idx.columns).empty?

      idx.columns.each_with_index do |col, i|
        raise ArgumentError, "index.column[#{i}] missing :key"   if col[:key].to_s.empty?
        raise ArgumentError, "index.column[#{i}] missing :label" if col[:label].to_s.empty?
        raise ArgumentError, "index.column[#{i}] missing :value (must be a callable)" unless col[:value].respond_to?(:call)
      end
    end

    def validate_detail!(det)
      Array(det.sections).each_with_index do |section, i|
        raise ArgumentError, "detail.section[#{i}] missing :key" if section[:key].to_s.empty?

        Array(section[:rows]).each_with_index do |row, j|
          raise ArgumentError, "detail.section[#{i}].row[#{j}] missing :key"   if row[:key].to_s.empty?
          raise ArgumentError, "detail.section[#{i}].row[#{j}] missing :label" if row[:label].to_s.empty?
          raise ArgumentError, "detail.section[#{i}].row[#{j}] missing :value" unless row[:value].respond_to?(:call)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Update Payments descriptor with `:key` + `default_position`**

Replace `app/services/feature_modules/payment/member_surface.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  module Payment
    MemberSurface = Member::Surface.new(
      key:   :payments,
      label: "Payments",
      icon:  :credit_card,
      default_position: 30,
      enabled_for: ->(user) {
        FeatureModules::Module.enabled?(key: "payment", customer_id: user.customer_id)
      },
      index: Member::Surface::Index.new(
        title:    "Payments",
        subtitle: "A history of payments tied to your account.",
        scope:    ->(user) {
          Payments::Payment
            .where(user_id: user.id, customer_id: user.customer_id)
            .order(created_at: :desc)
        },
        columns: [
          { key: :date,   label: "Date",   value: ->(r) { r.created_at }, format: :date },
          { key: :vendor, label: "Vendor", value: ->(r) { r.provider.titleize } },
          { key: :amount, label: "Amount", value: ->(r) { r.amount_cents }, format: :money, align: :right, hideable: false },
          { key: :status, label: "Status", value: ->(r) { r.status }, format: :status_pill }
        ],
        empty_state: {
          headline: "No payments yet",
          body:     "Your payment history will appear here.",
          icon:     :credit_card
        },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title:    ->(r) { "Payment #{r.out_trade_no}" },
        subtitle: ->(r) { "Created #{I18n.l(r.created_at, format: :long)}" },
        meta:     ->(r) { { label: r.status, tone: r.status == "succeeded" ? :success : :default } },
        sections: [
          {
            key: :primary,
            rows: [
              { key: :amount,     label: "Amount",  value: ->(r) { r.amount_cents }, format: :money_large, hideable: false },
              { key: :vendor,     label: "Vendor",  value: ->(r) { r.provider.titleize } },
              { key: :flow,       label: "Flow",    value: ->(r) { r.flow.upcase } },
              { key: :paid_at,    label: "Paid at", value: ->(r) { r.paid_at }, format: :datetime,
                when: ->(r) { r.paid_at } },
              { key: :psp_txn_id, label: "PSP transaction id",
                value: ->(r) { r.psp_transaction_id }, format: :mono, span: 2,
                when: ->(r) { r.psp_transaction_id.present? } }
            ]
          },
          {
            key:   :refunds,
            title: "Refunds",
            when:  ->(r) { r.payment_refunds.any? },
            list:  ->(r) {
              r.payment_refunds.map { |x|
                { left: I18n.l(x.created_at, format: :long), right: x.amount_cents, format: :money }
              }
            }
          }
        ]
      )
    )
  end
end
```

- [ ] **Step 3: Update spec coverage for Surface — extend `spec/services/member/surface_spec.rb`**

Where the existing spec builds columns / sections without `:key`, add `key:` everywhere. Add four new examples:

- "rejects a column missing :key" → `ArgumentError /key/`
- "rejects a section missing :key"
- "rejects a section row missing :key"
- "exposes default_position via default_position_or_default (DEFAULT_POSITION when nil)"

- [ ] **Step 4: Update other specs that use the old shape (per stale-test policy)**

Add `key:` on every column / section / row used in:
- `spec/services/member/surfaces_spec.rb`
- `spec/components/member/surface_index_component_spec.rb`
- `spec/components/member/surface_detail_component_spec.rb`
- `spec/components/member/index_table_component_spec.rb` (only if its column literals lack `:key` — `:key` is harmless to other consumers)
- `spec/requests/member/surfaces_spec.rb`
- `spec/system/member/surface_kit_spec.rb`

Also update:
- `app/components/member/surface_detail_component.rb` is unchanged — it iterates sections/rows by hash access and ignores `:key`.

- [ ] **Step 5: Run tests**

```
bundle exec rspec spec/services/member spec/components/member spec/requests/member spec/system/member
```

Expected: green.

- [ ] **Step 6: Commit**

```
git add app/services/member/surface.rb \
        app/services/feature_modules/payment/member_surface.rb \
        spec/services/member spec/components/member spec/requests/member spec/system/member
git commit -m "feat(member): require :key on column/section/row; add default_position"
```

---

## Phase 1 — Storage

### Task 2 — Migration: `member_surface_settings` table

**Files:**
- Create: `db/migrate/<TS>_create_member_surface_settings.rb`

- [ ] **Step 1: Generate migration filename**

```
TS=$(date -u +%Y%m%d%H%M%S)
touch db/migrate/${TS}_create_member_surface_settings.rb
```

- [ ] **Step 2: Write migration**

```ruby
class CreateMemberSurfaceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :member_surface_settings do |t|
      t.references :customer, null: false, foreign_key: true, type: :bigint
      t.string  :surface_key, null: false
      t.boolean :enabled,     null: false, default: true
      t.integer :position,    null: false, default: 0
      t.text    :config,      null: false, default: "{}"
      t.timestamps
    end

    add_index :member_surface_settings, %i[customer_id surface_key], unique: true,
              name: "idx_member_surface_settings_on_customer_and_key"
  end
end
```

(Using `t.text` for `config` so the existing `JsonSerializable` concern can round-trip it the same way `Captcha::ProviderSettings#config` does.)

- [ ] **Step 3: Run migration**

```
bundle exec rails db:migrate
RAILS_ENV=test bundle exec rails db:migrate
```

- [ ] **Step 4: Commit**

```
git add db/migrate/ db/schema.rb
git commit -m "feat(member): add member_surface_settings table"
```

---

### Task 3 — `Member::SurfaceSetting` model

**Files:**
- Create: `app/models/member/surface_setting.rb`
- Create: `spec/models/member/surface_setting_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceSetting do
  let(:customer) { create(:customer) }

  describe "validations" do
    it "requires surface_key" do
      record = described_class.new(customer: customer, surface_key: nil)
      expect(record).not_to be_valid
      expect(record.errors[:surface_key]).to be_present
    end

    it "enforces uniqueness of [customer_id, surface_key]" do
      described_class.create!(customer: customer, surface_key: "payments")
      dup = described_class.new(customer: customer, surface_key: "payments")
      expect(dup).not_to be_valid
    end

    it "allows the same surface_key across different customers" do
      other = create(:customer)
      described_class.create!(customer: customer, surface_key: "payments")
      expect(described_class.new(customer: other, surface_key: "payments")).to be_valid
    end
  end

  describe "config JSON round-trip" do
    it "stores and reads label / icon / subtitle / per_page" do
      record = described_class.create!(
        customer: customer, surface_key: "payments"
      )
      record.write_overlay(
        label: "Donations", icon: :heart, subtitle: "Past donations",
        per_page: 50,
        empty_headline: "No donations yet",
        empty_body:     "Once you donate it'll show up here."
      )
      record.save!
      record.reload

      expect(record.label_or("Payments")).to eq("Donations")
      expect(record.icon_or(:credit_card)).to eq(:heart)
      expect(record.subtitle_or("default")).to eq("Past donations")
      expect(record.per_page_or(20)).to eq(50)
      expect(record.empty_headline_or("default")).to eq("No donations yet")
      expect(record.empty_body_or("default")).to eq("Once you donate it'll show up here.")
    end

    it "falls back to defaults when not set" do
      record = described_class.create!(customer: customer, surface_key: "payments")
      expect(record.label_or("Payments")).to eq("Payments")
      expect(record.icon_or(:credit_card)).to eq(:credit_card)
      expect(record.per_page_or(20)).to eq(20)
    end

    it "stores visible_column_keys / visible_detail_row_keys / visible_section_keys as symbols" do
      record = described_class.create!(customer: customer, surface_key: "payments")
      record.write_overlay(
        visible_column_keys:     [:date, :amount],
        visible_detail_row_keys: [:amount, :vendor],
        visible_section_keys:    [:primary]
      )
      record.save! && record.reload
      expect(record.visible_column_keys).to     eq([:date, :amount])
      expect(record.visible_detail_row_keys).to eq([:amount, :vendor])
      expect(record.visible_section_keys).to    eq([:primary])
    end

    it "returns nil for visible_*_keys when empty (overlay does not narrow)" do
      record = described_class.create!(customer: customer, surface_key: "payments")
      expect(record.visible_column_keys).to be_nil
      record.write_overlay(visible_column_keys: [])
      record.save! && record.reload
      expect(record.visible_column_keys).to be_nil
    end
  end

  describe "position_or" do
    it "returns descriptor default when position is 0" do
      record = described_class.create!(customer: customer, surface_key: "payments", position: 0)
      expect(record.position_or(30)).to eq(30)
    end

    it "returns the row's position when set" do
      record = described_class.create!(customer: customer, surface_key: "payments", position: 50)
      expect(record.position_or(30)).to eq(50)
    end
  end

  describe ".for_customer_surface" do
    it "creates a row when missing and returns existing on second call" do
      a = described_class.for_customer_surface(customer_id: customer.id, surface_key: :payments)
      b = described_class.for_customer_surface(customer_id: customer.id, surface_key: :payments)
      expect(a.id).to eq(b.id)
    end
  end
end
```

- [ ] **Step 2: Run, confirm red**

```
bundle exec rspec spec/models/member/surface_setting_spec.rb
```

- [ ] **Step 3: Implementation**

Create `app/models/member/surface_setting.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Per-tenant overlay for one Member::Surface descriptor.
  # The descriptor declares the maximum capability; this row narrows it
  # (visibility, label, icon, subtitle, position, page size, visible columns,
  # visible detail rows / sections, empty-state copy override).
  #
  # Anything that can be re-shaped without a schema change lives in `config`
  # as a JSON blob — same idiom as Captcha::ProviderSettings#config.
  class SurfaceSetting < ApplicationRecord
    self.table_name = "member_surface_settings"

    include JsonSerializable

    belongs_to :customer
    json_attribute :config, default: {}

    validates :surface_key, presence: true,
                            uniqueness: { scope: :customer_id }

    def self.for_customer_surface(customer_id:, surface_key:)
      find_or_create_by!(customer_id: customer_id, surface_key: surface_key.to_s)
    end

    # ---- Overlay accessors. *_or returns the override or the supplied default
    # when no override is set; the same surface a NullSurfaceSetting offers, so
    # EffectiveSurface can hand the same message off to either object. ----

    def label_or(default)          = config_value(:label).presence    || default
    def icon_or(default)           = (config_value(:icon).presence || default).to_sym
    def subtitle_or(default)       = config_value(:subtitle).presence || default
    def empty_headline_or(default) = config_value(:empty_headline).presence || default
    def empty_body_or(default)     = config_value(:empty_body).presence || default

    def per_page_or(default)
      raw = config_value(:per_page).to_i
      raw.positive? ? raw : default
    end

    def position_or(default) = position.to_i.zero? ? default : position.to_i

    def visible_column_keys
      keys = Array(config_value(:visible_column_keys)).map(&:to_sym)
      keys.empty? ? nil : keys
    end

    def visible_detail_row_keys
      keys = Array(config_value(:visible_detail_row_keys)).map(&:to_sym)
      keys.empty? ? nil : keys
    end

    def visible_section_keys
      keys = Array(config_value(:visible_section_keys)).map(&:to_sym)
      keys.empty? ? nil : keys
    end

    def write_overlay(label: nil, icon: nil, subtitle: nil,
                      empty_headline: nil, empty_body: nil,
                      per_page: nil,
                      visible_column_keys: nil,
                      visible_detail_row_keys: nil,
                      visible_section_keys: nil)
      next_config = (config_json || {}).dup
      next_config["label"]                   = label                            unless label.nil?
      next_config["icon"]                    = icon.to_s                        unless icon.nil?
      next_config["subtitle"]                = subtitle                         unless subtitle.nil?
      next_config["empty_headline"]          = empty_headline                   unless empty_headline.nil?
      next_config["empty_body"]              = empty_body                       unless empty_body.nil?
      next_config["per_page"]                = per_page.to_i                    unless per_page.nil?
      next_config["visible_column_keys"]     = Array(visible_column_keys).map(&:to_s)     unless visible_column_keys.nil?
      next_config["visible_detail_row_keys"] = Array(visible_detail_row_keys).map(&:to_s) unless visible_detail_row_keys.nil?
      next_config["visible_section_keys"]    = Array(visible_section_keys).map(&:to_s)    unless visible_section_keys.nil?
      self.config_json = next_config
    end

    private

    def config_value(key) = (config_json || {})[key.to_s]
  end
end
```

- [ ] **Step 4: Run, confirm green**

```
bundle exec rspec spec/models/member/surface_setting_spec.rb
```

- [ ] **Step 5: Commit**

```
git add app/models/member/surface_setting.rb spec/models/member/surface_setting_spec.rb
git commit -m "feat(member): add SurfaceSetting model with overlay accessors"
```

---

## Phase 2 — Effective overlay layer

### Task 4 — `Member::NullSurfaceSetting` + `Member::EffectiveSurface`

**Files:**
- Create: `app/services/member/null_surface_setting.rb`
- Create: `app/services/member/effective_surface.rb`
- Create: `spec/services/member/effective_surface_spec.rb`

- [ ] **Step 1: Failing spec**

Create `spec/services/member/effective_surface_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::EffectiveSurface do
  let(:customer) { create(:customer) }

  let(:descriptor) do
    Member::Surface.new(
      key: :widgets, label: "Widgets", icon: :sparkles,
      default_position: 30,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title:    "Widgets",
        subtitle: "All widgets",
        scope:    ->(_u) { [] },
        columns: [
          { key: :a, label: "A", value: ->(r) { r.a } },
          { key: :b, label: "B", value: ->(r) { r.b } },
          { key: :c, label: "C", value: ->(r) { r.c }, hideable: false }
        ],
        empty_state: { headline: "Nothing", body: "yet", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(_r) { "T" },
        sections: [
          { key: :primary,
            rows: [
              { key: :x, label: "X", value: ->(_r) { "x" } },
              { key: :y, label: "Y", value: ->(_r) { "y" }, hideable: false }
            ] },
          { key: :secondary,
            rows: [{ key: :z, label: "Z", value: ->(_r) { "z" } }] },
          { key: :pinned,
            hideable: false,
            rows: [{ key: :pin, label: "Pin", value: ->(_r) { "p" } }] }
        ]
      )
    )
  end

  context "with NullSurfaceSetting (no overrides)" do
    subject(:effective) do
      described_class.new(descriptor: descriptor, settings: Member::NullSurfaceSetting.new)
    end

    it "delegates label, icon, subtitle, position to the descriptor" do
      expect(effective.label).to eq("Widgets")
      expect(effective.icon).to eq(:sparkles)
      expect(effective.position).to eq(30)
    end

    it "is enabled? true by default" do
      expect(effective).to be_enabled
    end

    it "AND's enabled? with descriptor.enabled_for? in enabled_for?" do
      expect(effective.enabled_for?(double)).to be(true)
    end

    it "exposes all descriptor columns" do
      expect(effective.index.columns.map { |c| c[:key] }).to eq([:a, :b, :c])
    end

    it "exposes all descriptor sections" do
      expect(effective.detail.sections.map { |s| s[:key] }).to eq([:primary, :secondary, :pinned])
    end

    it "delegates per_page to the descriptor" do
      expect(effective.index.per_page).to eq(20)
    end

    it "exposes empty_state from the descriptor" do
      expect(effective.index.empty_state).to eq(headline: "Nothing", body: "yet", icon: :sparkles)
    end
  end

  context "with a SurfaceSetting that overrides label / icon / subtitle / per_page / position" do
    let(:setting) do
      Member::SurfaceSetting.create!(customer: customer, surface_key: "widgets", position: 50)
    end

    before do
      setting.write_overlay(label: "Gadgets", icon: :gift, subtitle: "All gadgets", per_page: 5)
      setting.save!
    end

    subject(:effective) { described_class.new(descriptor: descriptor, settings: setting) }

    it "returns overridden label / icon / subtitle / per_page / position" do
      expect(effective.label).to eq("Gadgets")
      expect(effective.icon).to eq(:gift)
      expect(effective.position).to eq(50)
      expect(effective.index.subtitle).to eq("All gadgets")
      expect(effective.index.per_page).to eq(5)
    end
  end

  context "with empty-state copy override" do
    let(:setting) do
      Member::SurfaceSetting.create!(customer: customer, surface_key: "widgets")
    end

    before do
      setting.write_overlay(empty_headline: "Nothing here yet, friend.", empty_body: "Soon!")
      setting.save!
    end

    subject(:effective) { described_class.new(descriptor: descriptor, settings: setting) }

    it "merges empty_state copy" do
      expect(effective.index.empty_state).to eq(
        headline: "Nothing here yet, friend.", body: "Soon!", icon: :sparkles
      )
    end
  end

  context "with visible_column_keys narrowing" do
    let(:setting) { Member::SurfaceSetting.create!(customer: customer, surface_key: "widgets") }
    before do
      setting.write_overlay(visible_column_keys: [:a]) # admin chooses only :a
      setting.save!
    end
    subject(:effective) { described_class.new(descriptor: descriptor, settings: setting) }

    it "narrows columns to visible keys" do
      expect(effective.index.columns.map { |c| c[:key] }).to include(:a)
    end

    it "always retains hideable: false columns" do
      keys = effective.index.columns.map { |c| c[:key] }
      expect(keys).to include(:c)
    end

    it "drops other columns" do
      keys = effective.index.columns.map { |c| c[:key] }
      expect(keys).not_to include(:b)
    end
  end

  context "with visible_section_keys + visible_detail_row_keys narrowing" do
    let(:setting) { Member::SurfaceSetting.create!(customer: customer, surface_key: "widgets") }
    before do
      setting.write_overlay(visible_section_keys: [:primary], visible_detail_row_keys: [:x])
      setting.save!
    end
    subject(:effective) { described_class.new(descriptor: descriptor, settings: setting) }

    it "narrows sections, but always retains hideable: false sections" do
      keys = effective.detail.sections.map { |s| s[:key] }
      expect(keys).to include(:primary)
      expect(keys).to include(:pinned)         # locked
      expect(keys).not_to include(:secondary)  # hidden
    end

    it "narrows rows in retained sections, but always retains hideable: false rows" do
      primary = effective.detail.sections.find { |s| s[:key] == :primary }
      keys    = primary[:rows].map { |r| r[:key] }
      expect(keys).to include(:x)
      expect(keys).to include(:y) # locked
    end
  end

  context "when settings.enabled? is false" do
    let(:setting) { Member::SurfaceSetting.create!(customer: customer, surface_key: "widgets", enabled: false) }
    subject(:effective) { described_class.new(descriptor: descriptor, settings: setting) }

    it "is not enabled?" do
      expect(effective).not_to be_enabled
    end

    it "fails enabled_for? regardless of descriptor.enabled_for?" do
      expect(effective.enabled_for?(double)).to be(false)
    end
  end
end
```

- [ ] **Step 2: Run, confirm red**

```
bundle exec rspec spec/services/member/effective_surface_spec.rb
```

- [ ] **Step 3: Implement NullSurfaceSetting**

Create `app/services/member/null_surface_setting.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Stand-in when no SurfaceSetting row exists yet for (customer, surface).
  # Exposes the same overlay surface as Member::SurfaceSetting so the
  # EffectiveSurface wrapper can polymorphically delegate to either object.
  class NullSurfaceSetting
    def enabled?                            ; true  ; end
    def label_or(default)                   ; default ; end
    def icon_or(default)                    ; default ; end
    def subtitle_or(default)                ; default ; end
    def empty_headline_or(default)          ; default ; end
    def empty_body_or(default)              ; default ; end
    def per_page_or(default)                ; default ; end
    def position_or(default)                ; default ; end
    def visible_column_keys                 ; nil   ; end
    def visible_detail_row_keys             ; nil   ; end
    def visible_section_keys                ; nil   ; end
  end
end
```

- [ ] **Step 4: Implement EffectiveSurface**

Create `app/services/member/effective_surface.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Descriptor + per-tenant overlay merged into a single object that exposes
  # the same surface interface (label, icon, index, detail) the kit
  # components and the controller already consume. The scope lambda is
  # security-critical and never overridable — it always comes from the
  # descriptor.
  class EffectiveSurface
    def initialize(descriptor:, settings:)
      @descriptor = descriptor
      @settings   = settings
    end

    def key      ; @descriptor.key                               ; end
    def label    ; @settings.label_or(@descriptor.label)         ; end
    def icon     ; @settings.icon_or(@descriptor.icon)           ; end
    def position ; @settings.position_or(@descriptor.default_position_or_default) ; end
    def enabled? ; @settings.enabled?                            ; end

    def enabled_for?(user)
      enabled? && @descriptor.enabled_for?(user)
    end

    def index  ; @effective_index  ||= EffectiveIndex.new(descriptor: @descriptor.index,  settings: @settings, descriptor_default_subtitle: @descriptor.index.subtitle)  ; end
    def detail ; @effective_detail ||= EffectiveDetail.new(descriptor: @descriptor.detail, settings: @settings) ; end

    attr_reader :descriptor, :settings

    # Wrapper exposing the same shape as Member::Surface::Index, with
    # overlay logic applied for visibility-narrowing fields. Scope, columns
    # signature, and per-column callables are NEVER altered.
    class EffectiveIndex
      def initialize(descriptor:, settings:, descriptor_default_subtitle:)
        @descriptor = descriptor
        @settings   = settings
        @default_subtitle = descriptor_default_subtitle
      end

      def title       ; @descriptor.title                                          ; end
      def subtitle    ; @settings.subtitle_or(@default_subtitle)                   ; end
      def scope       ; @descriptor.scope                                          ; end
      def per_page    ; @settings.per_page_or(@descriptor.per_page_or_default)     ; end
      def per_page_or_default ; per_page ; end

      def empty_state
        original = @descriptor.empty_state || {}
        original.merge(
          headline: @settings.empty_headline_or(original[:headline]),
          body:     @settings.empty_body_or(original[:body])
        )
      end

      def columns
        visible = @settings.visible_column_keys
        @descriptor.columns.select { |c|
          c[:hideable] == false || visible.nil? || visible.include?(c[:key])
        }
      end
    end

    # Wrapper exposing the same shape as Member::Surface::Detail.
    class EffectiveDetail
      def initialize(descriptor:, settings:)
        @descriptor = descriptor
        @settings   = settings
      end

      def title    ; @descriptor.title    ; end
      def subtitle ; @descriptor.subtitle ; end
      def meta     ; @descriptor.meta     ; end

      def sections
        visible_section_keys = @settings.visible_section_keys
        visible_row_keys     = @settings.visible_detail_row_keys

        @descriptor.sections
          .select { |s|
            s[:hideable] == false || visible_section_keys.nil? || visible_section_keys.include?(s[:key])
          }
          .map { |s| narrow_rows(s, visible_row_keys) }
      end

      private

      def narrow_rows(section, visible_row_keys)
        return section unless section[:rows].is_a?(Array)
        return section if visible_row_keys.nil?

        narrowed = section[:rows].select { |r|
          r[:hideable] == false || visible_row_keys.include?(r[:key])
        }
        section.merge(rows: narrowed)
      end
    end
  end
end
```

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/services/member/effective_surface_spec.rb
```

- [ ] **Step 6: Commit**

```
git add app/services/member/null_surface_setting.rb \
        app/services/member/effective_surface.rb \
        spec/services/member/effective_surface_spec.rb
git commit -m "feat(member): add EffectiveSurface overlay wrapper"
```

---

## Phase 3 — Customer-aware registry

### Task 5 — `Surfaces.for(customer:)`, `Surfaces.fetch(key, customer:)`, descriptor helpers

**Files:**
- Modify: `app/services/member/surfaces.rb`
- Modify: `spec/services/member/surfaces_spec.rb`
- Modify: `app/controllers/member/surfaces_controller.rb`
- Modify: `app/services/member/navigation.rb`
- Modify: `spec/services/member/navigation_spec.rb` (if needed)
- Modify: `spec/components/member/top_nav_component_spec.rb` (only if asserts on path/icons that the overlay would change — should be safe)
- Modify: `spec/system/member/payments_spec.rb` (rebuild controller code path)

- [ ] **Step 1: Update `Surfaces` registry**

Replace `app/services/member/surfaces.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Registry of member surface descriptors + customer-aware accessor.
  #
  # `register(...)` and `reset!` exist for tests; auto-discovery scans
  # FeatureModules::Module.all on first descriptor access.
  module Surfaces
    class << self
      # Test/manual registration of a descriptor (validated on register).
      def register(surface)
        surface.validate!
        registry[surface.key.to_sym] = surface
      end

      # Raw descriptors (no overlay). Used by the admin settings page so the
      # admin sees a row per descriptor regardless of the customer's overlay.
      def all_descriptors
        ensure_discovered!
        registry.values
      end
      alias_method :all, :all_descriptors

      def descriptor_keys
        all_descriptors.map(&:key)
      end

      def descriptor_for(key)
        ensure_discovered!
        registry[key.to_sym]
      end

      # Customer-aware effective surfaces, sorted by overlay position
      # (falls back to descriptor's default_position).
      def for(customer:)
        descriptors = all_descriptors
        settings_by_key = SurfaceSetting
          .where(customer_id: customer.id)
          .index_by { |s| s.surface_key.to_sym }

        descriptors.map { |descriptor|
          EffectiveSurface.new(
            descriptor: descriptor,
            settings:   settings_by_key.fetch(descriptor.key) { NullSurfaceSetting.new }
          )
        }.sort_by(&:position)
      end

      def fetch(key, customer:)
        found = self.for(customer: customer).find { |s| s.key == key.to_sym }
        return found if found

        raise ActiveRecord::RecordNotFound, "no member surface for #{key.inspect}"
      end

      def reset!
        @registry   = {}
        @discovered = false
      end

      private

      def registry
        @registry ||= {}
      end

      def ensure_discovered!
        return if @discovered

        @discovered = true
        FeatureModules::Module.all.find_each do |fm|
          ns_name = "FeatureModules::#{fm.key.camelize}"
          ns      = ns_name.safe_constantize or next
          surface = ns.const_defined?(:MemberSurface, false) ? ns.const_get(:MemberSurface) : nil
          next unless surface.is_a?(Member::Surface)

          surface.validate!
          registry[surface.key.to_sym] ||= surface
        end
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
        @discovered = false
      end
    end
  end
end
```

- [ ] **Step 2: Update `SurfacesController#load_surface`**

Replace the body of `app/controllers/member/surfaces_controller.rb` `load_surface`:

```ruby
def load_surface
  @surface = Member::Surfaces.fetch(params[:key], customer: current_customer)
  raise ActiveRecord::RecordNotFound unless @surface.enabled_for?(current_user)
end
```

(`@surface` is now an `EffectiveSurface`. Its `index` / `detail` interface is identical from the kit's perspective.)

- [ ] **Step 3: Update `Navigation.items_for(user)`**

Replace `app/services/member/navigation.rb`:

```ruby
# frozen_string_literal: true

require_relative "navigation/item"

module Member
  # Registry of member navigation items.
  #
  # Bespoke entries (Home / Profile / Security) are pinned at the top.
  # Descriptor-driven entries come from Member::Surfaces.for(customer:),
  # which already applies the per-tenant overlay (visibility, label, icon,
  # position).
  module Navigation
    BESPOKE_ITEMS = [
      Item.new(
        key: :home, label: "Home", icon: :home,
        path:    ->(customer) { "/#{customer.id}/member" },
        visible: ->(_user) { true }
      ),
      Item.new(
        key: :profile, label: "Profile", icon: :user,
        path:    ->(customer) { "/#{customer.id}/member/profile" },
        visible: ->(_user) { true }
      ),
      Item.new(
        key: :security, label: "Security", icon: :shield_check,
        path:    ->(customer) { "/#{customer.id}/member/security" },
        visible: ->(_user) { true }
      )
    ].freeze

    def self.items_for(user)
      surfaces = Member::Surfaces
        .for(customer: user.customer)
        .map { |effective| item_from_effective(effective) }

      (BESPOKE_ITEMS + surfaces).select { |item| item.visible_to?(user) }
    end

    def self.item_from_effective(effective)
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
```

- [ ] **Step 4: Update Surfaces spec**

In `spec/services/member/surfaces_spec.rb`, update the `.fetch` examples to call `fetch(key, customer:)` and add new examples:

- `.for(customer:)` returns descriptors as EffectiveSurface, sorted by position
- `.for(customer:)` honors a stored SurfaceSetting (override label flows through)
- `.descriptor_keys` returns all descriptor keys (raw)
- `.descriptor_for(:unknown)` returns nil

The existing `:test_widget` register/reset pattern can stay; add `customer = create(:customer)` and call `fetch(:test_widget, customer: customer)`.

- [ ] **Step 5: Run, confirm green**

```
bundle exec rspec spec/services/member spec/components/member spec/requests/member spec/system/member
```

If a top_nav_component or system spec was relying on raw descriptor `.label` and the overlay now flows through, update assertions per stale-test policy (rare — they all currently use the descriptor defaults).

- [ ] **Step 6: Commit**

```
git add app/services/member/surfaces.rb \
        app/controllers/member/surfaces_controller.rb \
        app/services/member/navigation.rb \
        spec/services/member
git commit -m "feat(member): customer-aware Surfaces.for/fetch + Navigation overlay"
```

---

## Phase 4 — Admin settings page

### Task 6 — Routes + ability allow-list

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/models/ability.rb`

- [ ] **Step 1: Add the admin route**

In `config/routes.rb`, locate the admin `namespace :settings do` block (around line 131) and add the new resource at the top of the block (so it's matched before the generic `module_configs` route below it):

```ruby
namespace :settings do
  resource :member, only: %i[show update],
                         controller: "settings/member"

  namespace :modules do
    # ... existing payments / authentication / captcha sub-routes ...
  end
end
```

This generates path helpers `admin_settings_member_path` and routes:
- `GET  /:cid/admin/settings/member`
- `PATCH /:cid/admin/settings/member`

- [ ] **Step 2: Add the route subject to the admin allow-list**

In `app/models/ability.rb`, the platform-owner block (`can :manage, :all`) and the admin block (`can :manage, :all`) already grant access. No allow-list additions needed for admin/owner. However, if `RouteAuthorization` requires an explicit subject for /:cid/admin paths, examine — admin routes are gated by URL prefix not by ability subject. Skip ability changes.

- [ ] **Step 3: Verify route**

```
bundle exec rails routes -g admin/settings/member
```

Expected output: a `show` and `update` line under `admin_settings_member`.

- [ ] **Step 4: Commit**

```
git add config/routes.rb
git commit -m "feat(admin): add /:cid/admin/settings/member route"
```

---

### Task 7 — Reform contract

**Files:**
- Create: `app/concepts/member/settings/contract/update.rb`

- [ ] **Step 1: Implement contract**

Create `app/concepts/member/settings/contract/update.rb`:

```ruby
# frozen_string_literal: true

module Member
  module Settings
    module Contract
      class Update < Reform::Form
        # The form binds to a wrapper struct that exposes a `rows` collection.
        # Each row corresponds to one descriptor surface's settings overlay.
        collection :rows, populate_if_empty: OpenStruct do
          property :surface_key
          property :enabled,     virtual: true
          property :position,    virtual: true
          property :label,       virtual: true
          property :icon,        virtual: true
          property :subtitle,    virtual: true
          property :empty_headline, virtual: true
          property :empty_body,     virtual: true
          property :per_page,    virtual: true
          property :visible_column_keys,     virtual: true
          property :visible_detail_row_keys, virtual: true
          property :visible_section_keys,    virtual: true

          validates :surface_key, presence: true,
                                  inclusion: {
                                    in: ->(_) { Member::Surfaces.descriptor_keys.map(&:to_s) }
                                  }
          validates :per_page,
                    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 200 },
                    allow_blank: true
          validates :position,
                    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                    allow_blank: true
        end
      end
    end
  end
end
```

- [ ] **Step 2: Commit (with operation in next task — same logical change)**

(No commit yet; commit with Task 8.)

---

### Task 8 — Trailblazer Operation

**Files:**
- Create: `app/concepts/member/settings/operation/update.rb`
- Create: `spec/concepts/member/settings/operation/update_spec.rb`

- [ ] **Step 1: Failing spec**

Create `spec/concepts/member/settings/operation/update_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Settings::Operation::Update do
  let(:customer) { create(:customer) }

  before do
    payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: payment_module
    ) { |a| a.status = :active }
    Member::Surfaces.reset!
  end

  it "creates a SurfaceSetting row when none exists for the (customer, surface)" do
    expect {
      described_class.call(
        customer: customer,
        params: ActionController::Parameters.new(
          rows: [{ surface_key: "payments", enabled: "1", label: "Donations" }]
        )
      )
    }.to change(Member::SurfaceSetting, :count).by(1)
  end

  it "writes label / icon / subtitle / per_page / position into the row" do
    result = described_class.call(
      customer: customer,
      params: ActionController::Parameters.new(
        rows: [{
          surface_key: "payments",
          enabled: "1",
          position: "50",
          label: "Donations", icon: "heart", subtitle: "Past donations",
          empty_headline: "No donations yet",
          empty_body:     "Once you donate it'll show up here.",
          per_page: "5",
          visible_column_keys: %w[date amount],
          visible_detail_row_keys: %w[amount],
          visible_section_keys: %w[primary]
        }]
      )
    )
    expect(result.success?).to be(true)

    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.enabled).to be(true)
    expect(row.position).to eq(50)
    expect(row.label_or("X")).to eq("Donations")
    expect(row.icon_or(:credit_card)).to eq(:heart)
    expect(row.subtitle_or("X")).to eq("Past donations")
    expect(row.empty_headline_or("X")).to eq("No donations yet")
    expect(row.per_page_or(20)).to eq(5)
    expect(row.visible_column_keys).to eq([:date, :amount])
    expect(row.visible_detail_row_keys).to eq([:amount])
    expect(row.visible_section_keys).to eq([:primary])
  end

  it "rejects an unknown surface_key" do
    result = described_class.call(
      customer: customer,
      params: ActionController::Parameters.new(rows: [{ surface_key: "xyzzy", enabled: "1" }])
    )
    expect(result.success?).to be(false)
  end

  it "rejects per_page over 200" do
    result = described_class.call(
      customer: customer,
      params: ActionController::Parameters.new(
        rows: [{ surface_key: "payments", enabled: "1", per_page: "9999" }]
      )
    )
    expect(result.success?).to be(false)
  end

  it "is idempotent — calling twice does not create duplicate rows" do
    described_class.call(
      customer: customer,
      params: ActionController::Parameters.new(rows: [{ surface_key: "payments", enabled: "1" }])
    )
    expect {
      described_class.call(
        customer: customer,
        params: ActionController::Parameters.new(rows: [{ surface_key: "payments", enabled: "0", label: "Different" }])
      )
    }.not_to change(Member::SurfaceSetting, :count)

    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.enabled).to be(false)
    expect(row.label_or("X")).to eq("Different")
  end
end
```

- [ ] **Step 2: Run, confirm red**

```
bundle exec rspec spec/concepts/member/settings/operation/update_spec.rb
```

- [ ] **Step 3: Implement operation**

Create `app/concepts/member/settings/operation/update.rb`:

```ruby
# frozen_string_literal: true

module Member
  module Settings
    module Operation
      class Update
        Result = Struct.new(:success?, :errors, keyword_init: true) do
          def [](k) = send(k)
        end

        # @param customer [Customer]
        # @param params [ActionController::Parameters | Hash] expects { rows: [...] }
        def self.call(customer:, params:)
          payload  = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
          rows     = Array(payload[:rows] || payload["rows"]).map { |r| OpenStruct.new(r.transform_keys(&:to_sym)) }

          form = Member::Settings::Contract::Update.new(OpenStruct.new(rows: rows))
          unless form.validate(rows: rows.map { |r| r.to_h.transform_keys(&:to_s) })
            return Result.new(success?: false, errors: form.errors)
          end

          form.rows.each do |row|
            descriptor = Member::Surfaces.descriptor_for(row.surface_key)
            next if descriptor.nil?

            setting = Member::SurfaceSetting.for_customer_surface(
              customer_id: customer.id, surface_key: row.surface_key
            )
            setting.enabled  = truthy?(row.enabled)
            setting.position = row.position.to_i if row.position.present?
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

          Result.new(success?: true, errors: nil)
        end

        def self.truthy?(value)
          ActiveModel::Type::Boolean.new.cast(value) ? true : false
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run, confirm green**

```
bundle exec rspec spec/concepts/member/settings/operation/update_spec.rb
```

- [ ] **Step 5: Commit**

```
git add app/concepts/member/settings spec/concepts/member/settings
git commit -m "feat(member): Reform contract + Trailblazer Operation for settings update"
```

---

### Task 9 — Admin controller + presenter

**Files:**
- Create: `app/controllers/admin/settings/member_controller.rb`
- Create: `app/presenters/admin/settings/member_row_presenter.rb`
- Create: `spec/requests/admin/settings/member_spec.rb`

- [ ] **Step 1: Failing request spec**

Create `spec/requests/admin/settings/member_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Settings — Member", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:member)   { create(:user, :member, customer: customer) }

  before do
    payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: payment_module
    ) { |a| a.status = :active }
    Member::Surfaces.reset!
  end

  describe "GET /:cid/admin/settings/member" do
    it "renders for an admin" do
      sign_in admin
      get "/#{customer.id}/admin/settings/member"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payments") # descriptor row appears
      expect(response.body).to include("Profile")  # bespoke locked row appears
    end

    it "denies a member (URL gate)" do
      sign_in member
      get "/#{customer.id}/admin/settings/member"
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "PATCH /:cid/admin/settings/member" do
    it "saves overlay rows for an admin and round-trips them on next GET" do
      sign_in admin
      patch "/#{customer.id}/admin/settings/member",
            params: {
              member_settings: {
                rows: [{
                  surface_key: "payments",
                  enabled:     "1",
                  position:    "30",
                  label:       "Donations",
                  icon:        "heart",
                  subtitle:    "Past donations",
                  per_page:    "5",
                  visible_column_keys: %w[date amount]
                }]
              }
            }
      expect(response).to redirect_to("/#{customer.id}/admin/settings/member")

      get "/#{customer.id}/admin/settings/member"
      expect(response.body).to include("Donations")
    end

    it "rejects bad input and re-renders show with 422" do
      sign_in admin
      patch "/#{customer.id}/admin/settings/member",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "1", per_page: "99999" }]
              }
            }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

- [ ] **Step 2: Implement presenter**

Create `app/presenters/admin/settings/member_row_presenter.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    # Adapts an EffectiveSurface (descriptor + tenant overlay) into the form
    # field values the admin settings card needs. Pure value object.
    class MemberRowPresenter
      def initialize(effective:)
        @effective = effective
      end

      attr_reader :effective

      def surface_key  ; effective.key.to_s ; end
      def descriptor   ; effective.descriptor ; end
      def settings     ; effective.settings   ; end

      def enabled?     ; settings.enabled?    ; end
      def label        ; settings.label_or(descriptor.label) ; end
      def icon         ; settings.icon_or(descriptor.icon).to_s ; end
      def subtitle     ; settings.subtitle_or(descriptor.index.subtitle).to_s ; end
      def position     ; settings.position_or(descriptor.default_position_or_default) ; end
      def per_page     ; settings.per_page_or(descriptor.index.per_page_or_default) ; end
      def empty_headline ; settings.empty_headline_or(descriptor.index.empty_state[:headline]).to_s ; end
      def empty_body     ; settings.empty_body_or(descriptor.index.empty_state[:body]).to_s ; end

      def column_choices
        descriptor.index.columns.map { |c|
          {
            key:     c[:key],
            label:   c[:label],
            locked:  c[:hideable] == false,
            checked: c[:hideable] == false || (settings.visible_column_keys || all_column_keys).include?(c[:key])
          }
        }
      end

      def detail_row_choices
        descriptor.detail.sections.flat_map { |section|
          Array(section[:rows]).map { |row|
            {
              key:     row[:key],
              label:   row[:label],
              section_label: section[:title].to_s,
              locked:  row[:hideable] == false,
              checked: row[:hideable] == false || (settings.visible_detail_row_keys || all_row_keys).include?(row[:key])
            }
          }
        }
      end

      def section_choices
        descriptor.detail.sections.map { |section|
          {
            key:     section[:key],
            label:   (section[:title].presence || section[:key].to_s.titleize),
            locked:  section[:hideable] == false,
            checked: section[:hideable] == false || (settings.visible_section_keys || all_section_keys).include?(section[:key])
          }
        }
      end

      private

      def all_column_keys  ; descriptor.index.columns.map { |c| c[:key] } ; end
      def all_row_keys     ; descriptor.detail.sections.flat_map { |s| Array(s[:rows]).map { |r| r[:key] } } ; end
      def all_section_keys ; descriptor.detail.sections.map { |s| s[:key] } ; end
    end
  end
end
```

- [ ] **Step 3: Implement controller**

Create `app/controllers/admin/settings/member_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    # Admin page — /:cid/admin/settings/member
    # Lists every member surface descriptor (plus locked bespoke entries
    # Home / Profile / Security) with editable overlay fields.
    class MemberController < ApplicationController
      dashboard_menu_item :settings

      def show
        @rows = build_rows
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
          @rows   = build_rows
          @errors = result.errors
          render :show, status: :unprocessable_entity
        end
      end

      private

      def build_rows
        ::Member::Surfaces.for(customer: current_customer).map { |effective|
          ::Admin::Settings::MemberRowPresenter.new(effective: effective)
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run request spec, confirm red on view (no view yet) — that's expected**

The view is the next task. Skip running for now or expect view-missing.

- [ ] **Step 5: Commit**

```
git add app/controllers/admin/settings/member_controller.rb \
        app/presenters/admin/settings/member_row_presenter.rb \
        spec/requests/admin/settings/member_spec.rb
git commit -m "feat(admin): add Settings::MemberController + row presenter"
```

---

### Task 10 — ViewComponent + view + bespoke locked rows

**Files:**
- Create: `app/components/admin/settings/member_surface_card_component.rb`
- Create: `app/components/admin/settings/member_surface_card_component.html.erb`
- Create: `app/components/admin/settings/member_bespoke_card_component.rb`
- Create: `app/components/admin/settings/member_bespoke_card_component.html.erb`
- Create: `app/views/admin/settings/member/show.html.erb`
- Create: `spec/components/admin/settings/member_surface_card_component_spec.rb`

- [ ] **Step 1: Failing component spec**

Create `spec/components/admin/settings/member_surface_card_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::MemberSurfaceCardComponent, type: :component do
  let(:customer) { create(:customer) }

  let(:descriptor) { FeatureModules::Payment::MemberSurface }
  let(:effective)  do
    Member::EffectiveSurface.new(
      descriptor: descriptor, settings: Member::NullSurfaceSetting.new
    )
  end
  let(:presenter)  { Admin::Settings::MemberRowPresenter.new(effective: effective) }

  it "renders the surface label" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_text("Payments")
  end

  it "renders the visibility checkbox" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_css("input[type='checkbox'][name='member_settings[rows][0][enabled]']")
  end

  it "renders label / icon / subtitle text inputs" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_css("input[name='member_settings[rows][0][label]']")
    expect(page).to have_css("input[name='member_settings[rows][0][subtitle]']")
  end

  it "renders position + per_page number inputs" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_css("input[type='number'][name='member_settings[rows][0][position]']")
    expect(page).to have_css("input[type='number'][name='member_settings[rows][0][per_page]']")
  end

  it "renders empty-state copy overrides" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_css("input[name='member_settings[rows][0][empty_headline]']")
    expect(page).to have_css("textarea[name='member_settings[rows][0][empty_body]']")
  end

  it "renders one column checkbox per descriptor column" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    %i[date vendor amount status].each do |key|
      expect(page).to have_css("input[name='member_settings[rows][0][visible_column_keys][]'][value='#{key}']")
    end
  end

  it "marks hideable: false columns as disabled (locked always-on)" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    locked = page.find("input[name='member_settings[rows][0][visible_column_keys][]'][value='amount']")
    expect(locked[:disabled]).to eq("disabled")
  end

  it "renders one detail-row checkbox per descriptor row" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_css("input[name='member_settings[rows][0][visible_detail_row_keys][]'][value='amount']")
    expect(page).to have_css("input[name='member_settings[rows][0][visible_detail_row_keys][]'][value='vendor']")
  end

  it "renders one section checkbox per descriptor section" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_css("input[name='member_settings[rows][0][visible_section_keys][]'][value='primary']")
    expect(page).to have_css("input[name='member_settings[rows][0][visible_section_keys][]'][value='refunds']")
  end

  it "always renders surface_key as a hidden field" do
    render_inline(described_class.new(presenter: presenter, index: 0))
    expect(page).to have_css("input[type='hidden'][name='member_settings[rows][0][surface_key]'][value='payments']")
  end
end
```

- [ ] **Step 2: Implement card component (descriptor surfaces)**

Create `app/components/admin/settings/member_surface_card_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    # One editable card per descriptor-driven surface on the admin settings
    # page. Bound to a row index so multiple cards live under the same form.
    class MemberSurfaceCardComponent < ApplicationComponent
      attr_reader :presenter, :index

      def initialize(presenter:, index:)
        @presenter = presenter
        @index     = index
      end

      def name_for(field)
        "member_settings[rows][#{index}][#{field}]"
      end

      def array_name_for(field)
        "member_settings[rows][#{index}][#{field}][]"
      end
    end
  end
end
```

Create `app/components/admin/settings/member_surface_card_component.html.erb`:

```erb
<section class="card p-6 mb-4" data-surface-key="<%= presenter.surface_key %>">
  <input type="hidden" name="<%= name_for(:surface_key) %>" value="<%= presenter.surface_key %>"/>

  <header class="flex items-center justify-between mb-4 pb-4 border-b border-border-subtle">
    <div>
      <h2 class="text-lg font-semibold"><%= presenter.descriptor.label %></h2>
      <p class="text-xs text-text-muted">Surface key: <code class="font-mono"><%= presenter.surface_key %></code></p>
    </div>
    <label class="inline-flex items-center gap-2 text-sm">
      <input type="hidden" name="<%= name_for(:enabled) %>" value="0"/>
      <input type="checkbox"
             name="<%= name_for(:enabled) %>"
             value="1"
             <%= "checked" if presenter.enabled? %>
             class="rounded"/>
      <span>Visible to members</span>
    </label>
  </header>

  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
    <div>
      <label class="form-label">Label</label>
      <input type="text"
             name="<%= name_for(:label) %>"
             value="<%= presenter.label %>"
             placeholder="<%= presenter.descriptor.label %>"
             class="input-field"/>
    </div>

    <div>
      <label class="form-label">Icon</label>
      <input type="text"
             name="<%= name_for(:icon) %>"
             value="<%= presenter.icon %>"
             placeholder="<%= presenter.descriptor.icon %>"
             class="input-field"/>
    </div>

    <div class="md:col-span-2">
      <label class="form-label">Subtitle</label>
      <input type="text"
             name="<%= name_for(:subtitle) %>"
             value="<%= presenter.subtitle %>"
             class="input-field"/>
    </div>

    <div>
      <label class="form-label">Navigation position</label>
      <input type="number"
             name="<%= name_for(:position) %>"
             value="<%= presenter.position %>"
             min="0"
             class="input-field"/>
      <p class="text-xs text-text-muted mt-1">Lower = higher in nav. Bespoke entries are pinned (Home=0, Profile=10, Security=20).</p>
    </div>

    <div>
      <label class="form-label">Page size</label>
      <input type="number"
             name="<%= name_for(:per_page) %>"
             value="<%= presenter.per_page %>"
             min="1"
             max="200"
             class="input-field"/>
    </div>

    <div>
      <label class="form-label">Empty-state headline</label>
      <input type="text"
             name="<%= name_for(:empty_headline) %>"
             value="<%= presenter.empty_headline %>"
             class="input-field"/>
    </div>

    <div>
      <label class="form-label">Empty-state body</label>
      <textarea name="<%= name_for(:empty_body) %>"
                rows="2"
                class="input-field"><%= presenter.empty_body %></textarea>
    </div>
  </div>

  <div class="mt-6">
    <h3 class="text-sm font-semibold mb-2">Visible index columns</h3>
    <div class="grid grid-cols-2 gap-2">
      <% presenter.column_choices.each do |choice| %>
        <label class="inline-flex items-center gap-2 text-sm <%= 'opacity-60' if choice[:locked] %>">
          <input type="checkbox"
                 name="<%= array_name_for(:visible_column_keys) %>"
                 value="<%= choice[:key] %>"
                 <%= "checked" if choice[:checked] %>
                 <%= "disabled" if choice[:locked] %>
                 class="rounded"/>
          <span><%= choice[:label] %><% if choice[:locked] %> <em class="text-xs text-text-muted">(always shown)</em><% end %></span>
        </label>
      <% end %>
    </div>
  </div>

  <div class="mt-6">
    <h3 class="text-sm font-semibold mb-2">Visible detail sections</h3>
    <div class="grid grid-cols-2 gap-2">
      <% presenter.section_choices.each do |choice| %>
        <label class="inline-flex items-center gap-2 text-sm <%= 'opacity-60' if choice[:locked] %>">
          <input type="checkbox"
                 name="<%= array_name_for(:visible_section_keys) %>"
                 value="<%= choice[:key] %>"
                 <%= "checked" if choice[:checked] %>
                 <%= "disabled" if choice[:locked] %>
                 class="rounded"/>
          <span><%= choice[:label] %><% if choice[:locked] %> <em class="text-xs text-text-muted">(always shown)</em><% end %></span>
        </label>
      <% end %>
    </div>
  </div>

  <div class="mt-6">
    <h3 class="text-sm font-semibold mb-2">Visible detail rows</h3>
    <div class="grid grid-cols-2 gap-2">
      <% presenter.detail_row_choices.each do |choice| %>
        <label class="inline-flex items-center gap-2 text-sm <%= 'opacity-60' if choice[:locked] %>">
          <input type="checkbox"
                 name="<%= array_name_for(:visible_detail_row_keys) %>"
                 value="<%= choice[:key] %>"
                 <%= "checked" if choice[:checked] %>
                 <%= "disabled" if choice[:locked] %>
                 class="rounded"/>
          <span>
            <% if choice[:section_label].present? %>
              <span class="text-text-muted text-xs"><%= choice[:section_label] %> /</span>
            <% end %>
            <%= choice[:label] %>
            <% if choice[:locked] %><em class="text-xs text-text-muted">(always shown)</em><% end %>
          </span>
        </label>
      <% end %>
    </div>
  </div>
</section>
```

- [ ] **Step 3: Bespoke locked card (Home / Profile / Security read-only)**

Create `app/components/admin/settings/member_bespoke_card_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    class MemberBespokeCardComponent < ApplicationComponent
      BESPOKE = [
        { label: "Home",     position: 0,  description: "Member landing page; always visible." },
        { label: "Profile",  position: 10, description: "Account profile; always visible." },
        { label: "Security", position: 20, description: "Password & MFA; always visible." }
      ].freeze

      attr_reader :entries
      def initialize ; @entries = BESPOKE ; end
    end
  end
end
```

Create `app/components/admin/settings/member_bespoke_card_component.html.erb`:

```erb
<section class="card p-6 mb-4 bg-surface-active/30">
  <header class="mb-3">
    <h2 class="text-lg font-semibold">Built-in surfaces</h2>
    <p class="text-xs text-text-muted">These are always visible to members and cannot be relabelled or hidden.</p>
  </header>
  <ul class="divide-y divide-border-subtle">
    <% entries.each do |entry| %>
      <li class="py-3 flex items-center justify-between text-sm">
        <div>
          <span class="font-medium"><%= entry[:label] %></span>
          <span class="ml-2 text-text-muted"><%= entry[:description] %></span>
        </div>
        <span class="text-xs text-text-muted font-mono">position <%= entry[:position] %></span>
      </li>
    <% end %>
  </ul>
</section>
```

- [ ] **Step 4: Show view**

Create `app/views/admin/settings/member/show.html.erb`:

```erb
<%= render BreadcrumbsComponent.new(crumbs: [
      { label: "Settings",     path: "/#{current_customer.id}/admin/settings" },
      { label: "Member",  path: nil }
    ]) %>

<div class="mb-8">
  <h1 class="text-subtitle">Member surfaces</h1>
  <p class="mt-1 text-body-sm">Control which read-only surfaces appear in your members' navigation, what they're called, and what they show.</p>
</div>

<% if @errors.present? %>
  <div class="rounded-lg bg-danger-subtle border border-danger/20 p-3 mb-4">
    <ul class="text-sm text-danger list-disc pl-5 space-y-1">
      <% @errors.full_messages.each do |msg| %>
        <li><%= msg %></li>
      <% end %>
    </ul>
  </div>
<% end %>

<%= render Admin::Settings::MemberBespokeCardComponent.new %>

<%= form_with url: "/#{current_customer.id}/admin/settings/member",
              method: :patch,
              local:  true do %>
  <% @rows.each_with_index do |row_presenter, idx| %>
    <%= render Admin::Settings::MemberSurfaceCardComponent.new(presenter: row_presenter, index: idx) %>
  <% end %>

  <div class="flex justify-end gap-3 mt-6">
    <button type="submit" class="btn btn-primary">Save settings</button>
  </div>
<% end %>
```

- [ ] **Step 5: Run all newly added specs**

```
bundle exec rspec spec/components/admin/settings/member_surface_card_component_spec.rb \
                  spec/requests/admin/settings/member_spec.rb \
                  spec/concepts/member/settings
```

Expected: green.

- [ ] **Step 6: Commit**

```
git add app/components/admin/settings \
        app/views/admin/settings/member \
        spec/components/admin/settings
git commit -m "feat(admin): add Member settings view + ViewComponent"
```

---

## Phase 5 — System spec for round-trip

### Task 11 — End-to-end overlay round-trip

**Files:**
- Create: `spec/system/admin/settings/member_spec.rb`

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Settings — Member (system)", type: :system do
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:member)   { create(:user, :member, customer: customer) }

  before do
    payment_module = FeatureModules::Module.find_or_create_by!(key: "payment") { |m| m.name = "Payments" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: payment_module
    ) { |a| a.status = :active }
    Member::Surfaces.reset!
  end

  it "renames Payments to Donations and the member's nav reflects it" do
    sign_in admin
    visit "/#{customer.id}/admin/settings/member"

    fill_in "member_settings[rows][0][label]", with: "Donations"
    click_button "Save settings"

    expect(page).to have_text("Member surface settings saved.")

    # Sign out admin, sign in as member, see "Donations" in nav.
    visit "/#{customer.id}/auth/sign_out"
    sign_in member
    visit "/#{customer.id}/member"
    expect(page).to have_link("Donations")
  end
end
```

- [ ] **Step 2: Run**

```
bundle exec rspec spec/system/admin/settings/member_spec.rb
```

Expected: green.

- [ ] **Step 3: Commit**

```
git add spec/system/admin/settings/member_spec.rb
git commit -m "test(admin): system spec for member settings round-trip"
```

---

## Phase 6 — Verification

### Task 12 — Full suite + dev smoke

- [ ] **Step 1: Full member + admin suite**

```
bundle exec rspec spec/services/member spec/components/member \
                  spec/requests/member spec/system/member \
                  spec/models/member spec/concepts/member \
                  spec/components/admin/settings spec/requests/admin/settings \
                  spec/system/admin/settings
```

Expected: all green.

- [ ] **Step 2: Boot dev server and smoke**

```
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &
```

Visit `/<cid>/admin/settings/member`:
- Bespoke card lists Home / Profile / Security as locked.
- Payments card has all configurable fields rendered.
- Save with a renamed label; reload — values persist.
- Visit `/<cid>/member` — nav reflects the renamed label.
- Visit `/<cid>/member/payments` — page-header subtitle reflects the override; if a column was unchecked, the table is missing it.

Stop the server.

- [ ] **Step 3: Final commit (only if anything was tweaked)**

```
git add -A
git commit -m "chore(member): final dev smoke fixes"
```

---

## Plan self-review

**Spec coverage check:**

- §4.1 `default_position` on Surface — Task 1 ✓
- §4.2 column `:key` + `:hideable` — Task 1 ✓
- §4.3 section `:key`, `:hideable`, row `:key`, `:hideable` — Task 1 ✓
- §5.1 EffectiveSurface delegating + EffectiveIndex/Detail filtering — Task 4 ✓
- §5.2 NullSurfaceSetting — Task 4 ✓
- §5.3 `Surfaces.for(customer:)` + customer-aware fetch + descriptor helpers — Task 5 ✓
- §6.1 migration — Task 2 ✓
- §6.2 model with overlay accessors + `for_customer_surface` upsert — Task 3 ✓
- §7.1 routes — Task 6 ✓
- §7.1 controller — Task 9 ✓
- §7.2 contract + Operation — Tasks 7, 8 ✓
- §7.3 view + ViewComponent + bespoke locked card — Task 10 ✓
- §7.4 admin-controlled vs not — Task 9 + Task 10 (we add max knobs: enabled, label, icon, subtitle, position, per_page, empty_headline, empty_body, visible_column_keys, visible_detail_row_keys, visible_section_keys; we never let the admin override scope or format) ✓
- §10 acceptance criterion #6 — Task 11 system spec ✓

**Maximum-configurability ledger** (per the user's directive "as many as possible"):
1. enabled (visibility) ✓
2. label ✓
3. icon ✓
4. subtitle ✓
5. empty_headline ✓
6. empty_body ✓
7. position ✓
8. per_page ✓
9. visible_column_keys ✓
10. visible_detail_row_keys ✓
11. visible_section_keys ✓
12. hideable: false guard preserves load-bearing fields ✓

**Type consistency check:**
- `EffectiveSurface#index` returns an object exposing `title / subtitle / scope / columns / per_page / per_page_or_default / empty_state` — same surface as `Surface::Index` consumed by `SurfaceIndexComponent`, `SurfacesController`. ✓
- `EffectiveSurface#detail` returns an object exposing `title / subtitle / meta / sections` — same surface as `Surface::Detail` consumed by `SurfaceDetailComponent`. ✓
- `Surfaces.fetch(key, customer:)` matches `SurfacesController#load_surface`. ✓
- Reform contract `:rows` collection matches the form input names emitted by `MemberSurfaceCardComponent` (`member_settings[rows][N][...]`). ✓
- Operation reads from `params[:rows]`; controller passes `params.fetch(:member_settings)`. ✓

Plan is self-consistent.
