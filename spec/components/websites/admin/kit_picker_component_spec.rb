# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::KitPickerComponent, type: :component do
  it "lists every kit type with i18n name, description, and data-type Add buttons" do
    render_inline(described_class.new)

    expect(page).to have_css("[data-action='click->website-builder#addSection']", count: Websites::SectionKit::TYPES.size)
    expect(page).to have_css("[role='list'][aria-label='#{I18n.t("website.admin.pages.edit.kit_catalog")}']")
    Websites::SectionKit.groups.each do |group_key, types|
      expect(page).to have_css("h3", text: I18n.t("website.sections.groups.#{group_key}"))
      types.each do |type|
        expect(page).to have_css("button[data-type='#{type}']")
        next unless I18n.exists?("website.sections.#{type}.name")

        expect(page).to have_css("button[data-type='#{type}']", text: I18n.t("website.sections.#{type}.name"))
        expect(page).to have_text(I18n.t("website.sections.#{type}.description"))
      end
    end
  end

  it "places unrecognized types in the more group" do
    groups = described_class.new(types: %w[quote leftover_type]).grouped_types

    expect(groups["proof"]).to eq(%w[quote])
    expect(groups["more"]).to eq(%w[leftover_type])
  end

  it "accepts a subset of types" do
    render_inline(described_class.new(types: %w[quote faq]))

    expect(page).to have_css("button[data-type='quote']")
    expect(page).to have_css("button[data-type='faq']")
    expect(page).not_to have_css("button[data-type='hero_split']")
  end
end
