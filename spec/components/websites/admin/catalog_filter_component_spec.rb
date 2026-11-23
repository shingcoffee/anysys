# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::CatalogFilterComponent, type: :component do
  let(:items) do
    [
      { id: "business", label: "Business", path: "/?category=business" },
      { id: "product", label: "Product", path: "/?category=product" }
    ]
  end

  it "marks All as current when no filter is selected" do
    render_inline(described_class.new(label: "Category", all_path: "/", items: items))

    expect(page).to have_css("nav[data-catalog-filter='true'][aria-label='Category']")
    expect(page).to have_css("[data-filter-id='all'][aria-current='page']", text: I18n.t("website.platform.catalog.filter.all"))
    expect(page).to have_link("Business", href: "/?category=business")
    expect(page).not_to have_css("[data-filter-id='business'][aria-current='page']")
  end

  it "marks the selected chip as current" do
    render_inline(described_class.new(label: "Category", all_path: "/", items: items, current: "product"))

    expect(page).to have_css("[data-filter-id='product'][aria-current='page']", text: "Product")
    expect(page).not_to have_css("[data-filter-id='all'][aria-current='page']")
  end

  it "renders quiet counts and a solid selected fill at a consistent height" do
    counted = [
      { id: "business", label: "Business", path: "/?category=business", count: 4 },
      { id: "product", label: "Product", path: "/?category=product", count: 2 }
    ]
    render_inline(described_class.new(
      label: "Category",
      all_path: "/",
      items: counted,
      current: "business",
      all_count: 6
    ))

    expect(page).to have_css("[data-filter-id='all'][class*='h-8'][class*='text-sm']", text: "6")
    expect(page).to have_css("[data-filter-id='business'][class*='bg-accent'][class*='font-semibold']", text: "4")
    expect(page).to have_css("[data-filter-id='product'][class*='font-medium']", text: "2")
  end
end
