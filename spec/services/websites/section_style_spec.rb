# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Website section style overrides" do
  describe Websites::SectionFields do
    it "offers surface on every type, spacing except on full-bleed types, and alignment only on header-led types" do
      expect(described_class.style_fields("feature_grid").pluck(:key)).to eq(%w[surface spacing align])
      expect(described_class.style_fields("cta_band").pluck(:key)).to eq(%w[surface spacing])
      expect(described_class.style_fields("hero_cinematic").pluck(:key)).to eq(%w[surface])
      expect(described_class.style_fields("not_a_type")).to eq([])
    end

    it "keeps style out of the content schema but in the full schema" do
      expect(described_class.schema_for("faq").pluck(:key)).not_to include("surface")
      expect(described_class.full_schema_for("faq").last(3).pluck(:key)).to eq(%w[surface spacing align])
    end

    %w[en zh-CN].each do |locale|
      it "labels every field and option of every type in #{locale}" do
        I18n.with_locale(locale) do
          Websites::SectionKit::TYPES.each do |type|
            expect(I18n.t("website.sections.#{type}.name", raise: true)).to be_present
            described_class.full_schema_for(type).each do |field|
              [field, *Array(field[:item_fields])].each do |entry|
                expect(I18n.t(described_class::LABEL_KEYS.fetch(entry[:key]), raise: true)).to be_present
                Array(entry[:options]).each do |option|
                  expect(I18n.t(described_class::OPTION_LABEL_KEYS.fetch(entry[:key]).fetch(option), raise: true)).to be_present
                end
              end
            end
          end
        end
      end
    end
  end

  describe Websites::PropSchema do
    it "accepts known style values and rejects unknown keys for the type" do
      expect(described_class.valid?("faq", { "heading" => "Q", "surface" => "contrast", "spacing" => "roomy", "align" => "center" })).to be(true)
      expect(described_class.valid?("cta_band", { "headline" => "Go", "align" => "center" })).to be(false)
    end
  end

  describe Websites::Contracts::Section do
    def contract(props)
      described_class.new(described_class::Input.new("s1", "faq", props))
    end

    it "rejects a style value outside its options and allows blank" do
      expect(contract({ "surface" => "neon" }).validate({})).to be(false)
      expect(contract({ "surface" => "" }).validate({})).to be(true)
    end
  end

  describe Websites::SectionKit do
    it "falls back to default for blank or unknown style values" do
      expect(described_class.style_value({ "surface" => "accent" }, "surface")).to eq("accent")
      expect(described_class.style_value({ "surface" => "neon" }, "surface")).to eq("default")
      expect(described_class.style_value(nil, "spacing")).to eq("default")
    end
  end

  describe Websites::Theme do
    let(:light) { described_class.new("appearance" => "light", "accent" => "violet") }

    it "flips appearance only for the contrast surface" do
      expect(light.for_surface("contrast")).to be_dark
      expect(light.for_surface("contrast").accent).to eq("violet")
      expect(light.for_surface("muted")).to equal(light)
      expect(described_class.new("appearance" => "dark").for_surface("contrast")).not_to be_dark
    end

    it "maps each surface to a band class" do
      expect(light.surface_class("default")).to be_nil
      expect(light.surface_class("muted")).to eq(light.band_class)
      expect(light.for_surface("contrast").surface_class("contrast")).to eq("bg-neutral-950 text-white")
      expect(light.surface_class("accent")).to eq("bg-violet-50/70")
      expect(described_class.new("appearance" => "dark", "accent" => "violet").surface_class("accent")).to eq("bg-violet-400/[0.07]")
    end
  end
end
