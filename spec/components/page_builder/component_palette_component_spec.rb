# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::ComponentPaletteComponent, type: :component do
  describe "rendering" do
    before { render_inline(described_class.new) }

    it "renders the quick-add toolbar root with the page-builder target" do
      expect(page).to have_css("[data-page-builder-target='quickAddToolbar']")
    end

    it "renders an insert button for every component type" do
      %w[section card columns divider spacer
         heading paragraph list quote code_block
         image video button
         alert callout progress_bar].each do |type|
        expect(page).to have_css(
          "button[data-component-type='#{type}'][data-action='click->page-builder#insertFromToolbar']"
        )
      end
    end

    it "exposes a data-component-label on each insert button for the Stimulus controller" do
      expect(page).to have_css("button[data-component-type='section'][data-component-label='Section']")
    end

    it "renders icon-only buttons (no visible text labels)" do
      expect(page).not_to have_css("button[data-component-type='section']", text: "Section")
    end

    it "keeps title tooltips for accessibility now that labels are hidden" do
      ["Section", "Heading", "Image", "Alert"].each do |label|
        expect(page).to have_css("button[title='#{label}']")
      end
    end

    it "renders the contextual field-width group disabled by default" do
      expect(page).to have_css(
        "[data-page-builder-target='toolbarWidthGroup'].opacity-30.cursor-not-allowed"
      )
      expect(page).to have_css("[data-page-builder-target='toolbarWidthBtn']", count: 4)
    end

    it "wires each width button to setFieldWidth with a width value" do
      %w[full half two_thirds third].each do |width|
        expect(page).to have_css(
          "button[data-width='#{width}'][data-action='click->page-builder#setFieldWidth']"
        )
      end
    end
  end
end
