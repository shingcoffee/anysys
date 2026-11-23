# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::ElementPaletteComponent, type: :component do
  let(:flowchart) { create(:flowchart) }

  before { render_inline(described_class.new(flowchart: flowchart)) }

  it "renders the element-palette Stimulus controller wrapper" do
    expect(page).to have_css("[data-controller='element-palette']")
  end

  it "sets the current flowchart id value on the controller element" do
    expect(page).to have_css(
      "[data-element-palette-current-flowchart-id-value='#{flowchart.id}']"
    )
  end

  it "renders the search input wired to the element-palette controller" do
    expect(page).to have_css(
      "input[data-action='input->element-palette#searchFlowcharts'][data-element-palette-target='searchInput']"
    )
  end

  it "renders the Elements section heading" do
    expect(page).to have_css("h3", text: "Elements")
  end

  it "renders the Flows section heading" do
    expect(page).to have_css("h3", text: "Flows")
  end

  it "renders the basicElements target grid" do
    expect(page).to have_css("[data-element-palette-target='basicElements']")
  end

  it "renders the flowchartsList target" do
    expect(page).to have_css("[data-element-palette-target='flowchartsList']")
  end

  it "renders the flowchartsPlaceholder target with loading text" do
    expect(page).to have_css(
      "[data-element-palette-target='flowchartsPlaceholder']",
      text: "Loading..."
    )
  end

  it "renders the Start element tile inside the palette" do
    # FlowchartElements::StartElementComponent renders a draggable tile
    expect(page).to have_css("[data-element-palette-target='basicElements'] [data-element-type='start']")
  end

  it "renders the End element tile inside the palette" do
    expect(page).to have_css("[data-element-palette-target='basicElements'] [data-element-type='end']")
  end

  it "renders the Decision element tile inside the palette" do
    expect(page).to have_css("[data-element-palette-target='basicElements'] [data-element-type='decision']")
  end

  it "renders the Loop element tile inside the palette" do
    expect(page).to have_css("[data-element-palette-target='basicElements'] [data-element-type='loop']")
  end

  it "does not render removed structural element tiles" do
    expect(page).not_to have_css("[data-element-type='switch']")
    expect(page).not_to have_css("[data-element-type='join']")
    expect(page).not_to have_css("[data-element-type='timer']")
  end
end
