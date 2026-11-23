# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PaginationComponent, type: :component do
  def pagy(count:, page: 1, limit: 20)
    Pagy.new(count: count, page: page, limit: limit)
  end

  def render_pagination(pagy, base_path: "/x")
    render_inline(described_class.new(pagy: pagy, base_path: base_path))
  end

  it "renders nothing when total_count fits on one page" do
    render_pagination(pagy(count: 5))
    expect(page.native.to_html).not_to include("Previous")
    expect(page.native.to_html).not_to include("Next")
  end

  it "renders Pagy info and a Next link on page 1" do
    render_pagination(pagy(count: 50, page: 1))
    expect(page).to have_text("Displaying items 1-20 of 50 in total")
    expect(page).to have_link("Next", href: "/x?page=2")
    expect(page.native.to_html).not_to include("Previous")
  end

  it "renders Previous on the last page" do
    render_pagination(pagy(count: 50, page: 3))
    expect(page).to have_text("Displaying items 41-50 of 50 in total")
    expect(page).to have_link("Previous", href: "/x?page=2")
    expect(page.native.to_html).not_to include("Next")
  end

  it "preserves an existing query string on the base path" do
    render_pagination(pagy(count: 50, page: 1), base_path: "/x?foo=bar")
    expect(page).to have_link("Next", href: "/x?foo=bar&page=2")
  end

  it "has Pagy aria-label on the nav element" do
    render_pagination(pagy(count: 50, page: 1))
    expect(page).to have_css("nav[aria-label='Pages']")
  end
end
