# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::PageTabsComponent, type: :component do
  let(:pages) do
    [
      { "id" => "page_1", "name" => "Page 1", "order" => 1 },
      { "id" => "page_2", "name" => "Page 2", "order" => 2 }
    ]
  end

  def render_tabs(**opts)
    render_inline(described_class.new(**{ pages: pages, active_page_id: "page_1" }.merge(opts)))
  end

  it "renders tab for each page" do
    render_tabs

    expect(rendered_content).to have_text("Page 1")
    expect(rendered_content).to have_text("Page 2")
  end

  it "highlights active tab" do
    render_tabs

    expect(rendered_content).to have_css("[data-page-id='page_1'].bg-indigo-600")
  end

  it "renders add page button" do
    render_tabs

    expect(rendered_content).to have_css("button[data-action*='addPage']")
  end

  it "tabs are clickable to switch pages" do
    render_tabs

    expect(rendered_content).to have_css("div.page-tab[data-action*='switchPage']", count: 2)
  end

  it "renders add page button in empty state when no pages" do
    render_tabs(pages: [], active_page_id: nil)

    expect(rendered_content).to have_css("button[data-action*='addPage']")
  end

  it "orders tabs by page order" do
    unordered_pages = [
      { "id" => "page_2", "name" => "Second", "order" => 2 },
      { "id" => "page_1", "name" => "First", "order" => 1 }
    ]
    render_tabs(pages: unordered_pages)

    tabs = page.all("div.page-tab[data-action*='switchPage']")
    expect(tabs.first.text).to include("First")
  end

  it "shows delete button for tabs when multiple pages exist" do
    render_tabs

    expect(rendered_content).to have_css("[data-action*='deletePage']")
  end
end
