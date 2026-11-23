require "rails_helper"

RSpec.describe PageBuilder::MiniMapComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders a mini-map container" do
    expect(page).to have_css("[data-page-builder-target='miniMap']")
  end

  it "is hidden by default" do
    expect(page).to have_css("[data-page-builder-target='miniMap'].hidden")
  end

  it "renders a mini-map canvas target" do
    expect(page).to have_css("[data-page-builder-target='miniMapCanvas']")
  end
end
