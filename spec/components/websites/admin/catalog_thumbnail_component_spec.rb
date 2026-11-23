# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::CatalogThumbnailComponent, type: :component do
  let(:theme) { Websites::Theme.for_catalog("presence") }
  let(:sections) do
    [
      { "type" => "hero_split", "props" => { "headline" => "Hello" } },
      { "type" => "proof_strip", "props" => {} },
      { "type" => "card_grid", "props" => {} },
      { "type" => "cta_band", "props" => {} }
    ]
  end

  it "renders a portrait frame on phones and a 16:10 browser frame from md up" do
    render_inline(described_class.new(sections: sections, theme: theme))

    expect(page).to have_css("[data-catalog-thumbnail='true'][aria-hidden='true'][class*='aspect-[4/5]'][class*='md:aspect-[16/10]']")
    expect(page).to have_css(".pointer-events-none.select-none.origin-top-left[inert][class*='scale-[0.4]']")
    expect(page).to have_css("main")
  end

  it "accepts a custom frame for cards that stay 16:10 at every width" do
    render_inline(described_class.new(sections: sections, theme: theme, frame_class: "aspect-[16/10]"))

    expect(page).to have_css("[data-catalog-thumbnail='true'].aspect-\\[16\\/10\\]")
    expect(page).not_to have_css("[data-catalog-thumbnail='true'][class*='aspect-[4/5]']")
  end

  it "limits the live preview to the first three sections" do
    component = described_class.new(sections: sections, theme: theme)

    expect(component.preview_sections.size).to eq(3)
    expect(component.preview_types).to eq(%w[hero_split proof_strip card_grid])
    expect(component.preview_types).not_to include("cta_band")
  end

  it "falls back to section type labels when no kit component exists" do
    allow(Websites::SectionKit).to receive(:component_class).and_return(nil)
    render_inline(described_class.new(sections: sections, theme: theme))

    expect(page).to have_text(I18n.t("website.sections.hero_split.name"))
    expect(page).not_to have_css("main")
    expect(page).not_to have_text(I18n.t("website.sections.cta_band.name"))
  end
end
