# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::LayoutFamily do
  let(:layout_row) { Struct.new(:key) }

  describe ".of" do
    it "maps a layout to the longest matching starter key" do
      expect(described_class.of("presence_home")).to eq("presence")
      expect(described_class.of("saas_landing_pricing")).to eq("saas_landing")
      expect(described_class.of("cinematic")).to eq("cinematic")
      expect(described_class.of(:atelier_about)).to eq("atelier")
    end

    it "resolves aliased prefixes and falls back to standalone" do
      expect(described_class.of("saas_home")).to eq("saas_landing")
      expect(described_class.of("article")).to eq(described_class::STANDALONE)
      expect(described_class.of("")).to eq(described_class::STANDALONE)
    end
  end

  describe ".label" do
    it "uses the starter name and the general label for standalone layouts" do
      expect(described_class.label("presence")).to eq(I18n.t("website.skeletons.presence.name"))
      expect(described_class.label(described_class::STANDALONE)).to eq(I18n.t("website.admin.pages.new.filters.general"))
    end

    it "has a translated name for every starter family in both locales" do
      %i[en zh-CN].each do |locale|
        Websites::Skeletons.keys.each do |key|
          expect(I18n.exists?("website.skeletons.#{key}.name", locale)).to be(true), "#{locale} is missing website.skeletons.#{key}.name"
        end
      end
    end

    it "translates at call time" do
      I18n.with_locale(:"zh-CN") do
        expect(described_class.label(described_class::STANDALONE)).to eq(I18n.t("website.admin.pages.new.filters.general"))
      end
    end
  end

  describe ".group" do
    let(:layouts) { %w[article cinematic_home presence_home presence_about saas_home].map { |key| layout_row.new(key) } }

    it "orders families by starter with standalone layouts last" do
      groups = described_class.group(layouts)

      expect(groups.map(&:first)).to eq(%w[presence saas_landing cinematic standalone])
      expect(groups.first.last.map(&:key)).to eq(%w[presence_home presence_about])
    end

    it "pulls the requested family to the front and ignores unknown or blank ones" do
      expect(described_class.group(layouts, first: "cinematic").map(&:first)).to eq(%w[cinematic presence saas_landing standalone])
      expect(described_class.group(layouts, first: "unknown").map(&:first).first).to eq("presence")
      expect(described_class.group(layouts, first: "").map(&:first).first).to eq("presence")
      expect(described_class.group([])).to eq([])
    end
  end
end
