require "rails_helper"

RSpec.describe PageBuilder::CommandPaletteComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders a hidden palette container" do
    expect(page).to have_css("[data-page-builder-target='commandPalette']")
    expect(page).to have_css(".hidden")
  end

  it "has a search input" do
    expect(page).to have_css("input[placeholder*='command']")
  end

  it "has a results container" do
    expect(page).to have_css("[data-page-builder-target='commandPaletteResults']")
  end

  it "renders the command palette input target" do
    expect(page).to have_css("[data-page-builder-target='commandPaletteInput']")
  end

  it "includes input action bindings for filtering and keydown" do
    input = page.find("input[data-page-builder-target='commandPaletteInput']")
    expect(input["data-action"]).to include("input->page-builder#filterCommandPalette")
    expect(input["data-action"]).to include("keydown->page-builder#commandPaletteKeydown")
  end

  it "includes backdrop click to close" do
    container = page.find("[data-page-builder-target='commandPalette']")
    expect(container["data-action"]).to include("click->page-builder#closeCommandPalette")
  end

  it "includes stop propagation on inner container" do
    inner = page.find(".bg-white.rounded-xl")
    expect(inner["data-action"]).to include("click->page-builder#stopPropagation")
  end
end
