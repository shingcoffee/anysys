# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Surfaces do
  let_it_be(:customer) { create(:customer) }

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
