require "rails_helper"

RSpec.describe PageBuilder::ZoomControlsComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders zoom out button" do
    expect(page).to have_css("[data-action*='zoomOut']")
  end

  it "renders zoom in button" do
    expect(page).to have_css("[data-action*='zoomIn']")
  end

  it "shows zoom level display defaulting to 100%" do
    expect(page).to have_css("[data-page-builder-target='zoomLevel']", text: "100%")
  end

  it "renders mini-map toggle button" do
    expect(page).to have_css("[data-action*='toggleMiniMap']")
  end
end
