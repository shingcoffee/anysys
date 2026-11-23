# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::BreadcrumbComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders a breadcrumb container" do
    expect(page).to have_css("[data-page-builder-target='breadcrumbBar']")
  end

  it "is hidden by default" do
    expect(page).to have_css(".hidden")
  end

  it "has a content container" do
    expect(page).to have_css("[data-page-builder-target='breadcrumbContent']")
  end
end
