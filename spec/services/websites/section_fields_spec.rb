# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::SectionFields do
  it "registers the preview component in the showcase picker with its complete editable content" do
    expect(Websites::SectionKit.component_class("ai_preview")).to eq(Websites::Sections::AiPreviewComponent)
    expect(Websites::SectionKit.groups.fetch("showcase")).to include("ai_preview")
    fields = described_class.schema_for("ai_preview")
    expect(fields.reject { |field| field[:kind] == :array }.pluck(:key)).to eq(
      %w[kicker heading subhead example_label prompt_label prompt review_note output_label]
    )
    expect(fields.last).to include(key: "items", kind: :array, min: 1, max: 4)
    expect(fields.last[:item_fields].pluck(:key)).to eq(%w[title body status])
  end

  it "exposes optional hero media and pricing badge controls" do
    expect(described_class.schema_for("hero_centered")).to include(key: "media_mode", kind: :select, options: %w[image none])
    expect(described_class.schema_for("pricing")).to include(key: "featured_label", kind: :string)
  end

  %w[en zh-CN].each do |locale|
    it "translates every new editor field, media option, and picker entry in #{locale}" do
      I18n.with_locale(locale) do
        keys = %w[kicker heading subhead example_label prompt_label prompt review_note output_label title body status media_mode featured_label]
        keys.each { |key| expect(I18n.t(described_class::LABEL_KEYS.fetch(key), raise: true)).to be_present }
        described_class::OPTION_LABEL_KEYS.fetch("media_mode").each_value do |key|
          expect(I18n.t(key, raise: true)).to be_present
        end
        %w[sections.ai_preview.name sections.ai_preview.description sections.groups.showcase].each do |key|
          expect(I18n.t("website.#{key}", raise: true)).to be_present
        end
      end
    end
  end
end
