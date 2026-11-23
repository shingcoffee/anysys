require "rails_helper"

RSpec.describe PageBuilder::ContextMenuComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders a hidden context menu container" do
    expect(page).to have_css("[data-page-builder-target='contextMenu']")
    expect(page).to have_css(".hidden")
  end

  it "has a content container" do
    expect(page).to have_css("[data-page-builder-target='contextMenuContent']")
  end

  it "renders with correct styling classes" do
    expect(page).to have_css(".fixed.z-50")
    expect(page).to have_css(".bg-white.rounded-lg.shadow-xl.border.border-gray-200")
  end

  it "renders the content container with correct width" do
    expect(page).to have_css(".w-48.text-sm")
  end
end
