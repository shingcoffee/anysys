# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::EffectiveSurface do
  subject(:effective) { described_class.new(descriptor: descriptor, settings: setting) }

  let_it_be(:customer) { create(:customer) }

  let(:setting) { Member::NullSurfaceSetting.new }

  def surface_setting(**attrs)
    Member::SurfaceSetting.create!(customer: customer, surface_key: "widgets", source_key: "modules", **attrs)
  end

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

  context "with NullSurfaceSetting (no overrides)" do
    it "delegates label, icon, subtitle, position to the descriptor" do
      expect(effective.label).to eq("Widgets")
      expect(effective.icon).to eq(:sparkles)
      expect(effective.position).to eq(30)
    end

    it "is enabled? true by default" do
      expect(effective).to be_enabled
    end

    it "inherits a descriptor that defaults to disabled" do
      descriptor.default_enabled = false
      expect(effective).not_to be_enabled
      expect(effective.enabled_for?(double)).to be(false)
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

    it "has no row_action when no overlay is set" do
      expect(effective.row_action).to be_nil
    end
  end

  context "with a row action overlay" do
    let(:setting) { surface_setting }

    it "returns the overlay pair and uses the translated default label" do
      setting.write_overlay(row_action_key: "enroll", row_action_field: "course")
      setting.save!

      expect(effective.row_action).to eq(
        action_key: "enroll",
        field: "course",
        label: I18n.t("member.entity_surfaces.row_action_default", default: "Open")
      )
    end

    it "uses a stored label when present" do
      setting.write_overlay(row_action_key: "enroll", row_action_field: "course", row_action_label: "Enroll")
      setting.save!

      expect(effective.row_action).to eq(action_key: "enroll", field: "course", label: "Enroll")
    end

    it "is nil when the pair is incomplete" do
      setting.write_overlay(row_action_key: "enroll")
      setting.save!

      expect(effective.row_action).to be_nil
    end
  end

  context "with a SurfaceSetting that overrides label / icon / subtitle / per_page / position" do
    let(:setting) { surface_setting(position: 50) }

    before do
      setting.write_overlay(label: "Gadgets", icon: :gift, subtitle: "All gadgets", per_page: 5)
      setting.save!
    end

    it "returns overridden label / icon / subtitle / per_page / position" do
      expect(effective.label).to eq("Gadgets")
      expect(effective.icon).to eq(:gift)
      expect(effective.position).to eq(50)
      expect(effective.index.subtitle).to eq("All gadgets")
      expect(effective.index.per_page).to eq(5)
    end
  end

  context "with empty-state copy override" do
    let(:setting) { surface_setting }

    before do
      setting.write_overlay(empty_headline: "Nothing here yet, friend.", empty_body: "Soon!")
      setting.save!
    end

    it "merges empty_state copy" do
      expect(effective.index.empty_state).to eq(
        headline: "Nothing here yet, friend.", body: "Soon!", icon: :sparkles
      )
    end
  end

  context "with visible_column_keys narrowing" do
    let(:setting) { surface_setting }

    before do
      setting.write_overlay(visible_column_keys: [:a]) # admin chooses only :a
      setting.save!
    end

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
    let(:setting) { surface_setting }

    before do
      setting.write_overlay(visible_section_keys: [:primary], visible_detail_row_keys: [:x])
      setting.save!
    end

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

  context "when settings.enabled is false" do
    let(:setting) { surface_setting(enabled: false) }

    it "is not enabled?" do
      expect(effective).not_to be_enabled
    end

    it "fails enabled_for? regardless of descriptor.enabled_for?" do
      expect(effective.enabled_for?(double)).to be(false)
    end
  end

  context "when a saved enabled flag is present" do
    it "lets a saved true win over a disabled descriptor default" do
      descriptor.default_enabled = false
      setting = surface_setting(enabled: true)
      expect(described_class.new(descriptor: descriptor, settings: setting)).to be_enabled
    end

    it "lets a saved false win over an enabled descriptor default" do
      setting = surface_setting(enabled: false)
      expect(described_class.new(descriptor: descriptor, settings: setting)).not_to be_enabled
    end
  end

  context "when a row is created by an overlay-only edit" do
    let(:setting) { surface_setting }

    before do
      setting.write_overlay(label: "Renamed")
      setting.save!
    end

    it "keeps enabled nil and inherits the descriptor default" do
      expect(setting.enabled).to be_nil
      expect(effective).to be_enabled

      descriptor.default_enabled = false
      expect(described_class.new(descriptor: descriptor, settings: setting)).not_to be_enabled
    end
  end

  context "with explicitly empty visibility selections" do
    let(:setting) { surface_setting }

    before do
      setting.write_overlay(visible_column_keys: [], visible_section_keys: [], visible_detail_row_keys: [])
      setting.save!
    end

    it "hides every optional column while retaining the locked column" do
      expect(effective.index.columns.map { |column| column[:key] }).to eq([:c])
    end

    it "hides optional sections and optional rows even within a locked section" do
      expect(effective.detail.sections.map { |section| section[:key] }).to eq([:pinned])
      expect(effective.detail.sections.first[:rows]).to eq([])
    end

    it "retains locked rows when the containing section is selected" do
      setting.write_overlay(visible_section_keys: [:primary])
      setting.save!
      primary = effective.detail.sections.find { |section| section[:key] == :primary }
      expect(primary[:rows].map { |row| row[:key] }).to eq([:y])
    end

    it "restores inheritance only when explicitly requested" do
      setting.write_overlay(visible_column_keys: nil, visible_section_keys: nil, visible_detail_row_keys: nil)
      setting.save!
      expect(effective.index.columns.map { |column| column[:key] }).to eq([:a, :b, :c])
      expect(effective.detail.sections.map { |section| section[:key] }).to eq([:primary, :secondary, :pinned])
    end
  end
end
