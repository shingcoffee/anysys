# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PaginationComponent, type: :component do
  def render_pagination(pagination, page_path: ->(n) { "/list?page=#{n}" }, turbo_frame: nil)
    render_inline(
      described_class.new(pagination: pagination, page_path: page_path, turbo_frame: turbo_frame)
    )
  end

  it "renders nothing when there is only one page" do
    render_pagination({ page: 1, per_page: 10, total: 5, total_pages: 1 })
    expect(page).not_to have_css("footer")
  end

  it "renders page summary and next link on page 1" do
    render_pagination({ page: 1, per_page: 10, total: 25, total_pages: 3 })
    expect(page.text).to include("Page").and include("1").and include("of").and include("3")
    expect(page).to have_link(href: "/list?page=2")
    expect(page).not_to have_link(href: "/list?page=0")
  end

  it "renders previous on later pages" do
    render_pagination({ page: 3, per_page: 10, total: 25, total_pages: 3 })
    expect(page).to have_link(href: "/list?page=2")
  end

  it "passes turbo_frame data when provided" do
    render_pagination(
      { page: 1, per_page: 10, total: 25, total_pages: 3 },
      turbo_frame: "entity-entries-table"
    )
    expect(page).to have_css("a[data-turbo-frame='entity-entries-table']")
  end

  it "renders a page-number window with gaps and marks the current page" do
    render_pagination({ page: 6, per_page: 10, total: 200, total_pages: 20 })
    numbers = page.all("nav .hidden > *").map { |n| n.text.strip }
    expect(numbers).to eq(%w[1 … 5 6 7 … 20])
    expect(page).to have_css("[aria-current='page']", text: "6")
    expect(page).to have_link("20", href: "/list?page=20")
  end

  it "lists every page when there are only a few" do
    render_pagination({ page: 2, per_page: 10, total: 50, total_pages: 5 })
    expect(page.all("nav .hidden > *").map { |n| n.text.strip }).to eq(%w[1 2 3 4 5])
  end

  describe "summary and rows-per-page (opt-in)" do
    def render_rich(pagination)
      render_inline(described_class.new(
        pagination: pagination, page_path: ->(n) { "/list?page=#{n}" }, summary: true,
        per_page_options: [10, 25, 50], per_page_path: ->(n) { "/list?per_page=#{n}" }
      ))
    end

    it "shows the visible range and a rows-per-page menu" do
      render_rich({ page: 3, per_page: 10, total: 25, total_pages: 3 })
      expect(page).to have_text("Showing 21–25 of 25")
      expect(page).to have_css("[aria-current='true']", text: "10", visible: :all)
      expect(page).to have_link("25", href: "/list?per_page=25", visible: :all)
    end

    it "keeps a count-only footer on a single page" do
      render_rich({ page: 1, per_page: 10, total: 4, total_pages: 1 })
      expect(page).to have_css("footer", text: "4 results")
      expect(page).not_to have_css("nav")
      expect(page).not_to have_css("[data-controller='dropdown']")
    end

    it "offers rows-per-page on one page when it holds more than the smallest size" do
      render_rich({ page: 1, per_page: 25, total: 18, total_pages: 1 })
      expect(page).to have_css("[data-controller='dropdown']")
    end

    it "renders nothing for an empty list" do
      render_rich({ page: 1, per_page: 10, total: 0, total_pages: 0 })
      expect(page).not_to have_css("footer")
    end
  end
end
