# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::CatalogCardComponent, type: :component do
  it "renders a skeleton card with hover edit action and category data" do
    render_inline(described_class.new(
      key: "presence",
      kind: :skeleton,
      edit_path: "/edit",
      category: "business"
    )) do |card|
      card.with_thumbnail { "<div data-thumb></div>".html_safe }
      "Meta"
    end

    expect(page).to have_css("article[data-catalog-card='true'][data-skeleton-key='presence'][data-category='business']")
    expect(page).to have_css("[data-thumb]")
    expect(page).to have_link(I18n.t("common.actions.edit"), href: "/edit")
    expect(page).to have_css("[class*='sm:opacity-0'][class*='sm:group-hover:opacity-100'][class*='duration-150']")
    expect(page).to have_text("Meta")
    expect(page).not_to have_css("a > article")
    expect(page).not_to have_css("article[data-catalog-card] > a")
  end

  it "renders a layout card without overlay when there is no edit path" do
    render_inline(described_class.new(key: "article", kind: :layout, family: "standalone", lazy: true)) do |card|
      card.with_thumbnail { "<div data-thumb></div>".html_safe }
    end

    expect(page).to have_css("article[data-layout-key='article'][data-family='standalone']")
    expect(page).not_to have_link(I18n.t("common.actions.edit"))
    expect(page.find("article")[:class]).to include("content-visibility")
  end
end
