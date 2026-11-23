# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::ToolbarComponent, type: :component do
  let(:customer_id) { 96546124 }
  let(:page) { create(:page, name: "Test Page") }
  let(:entity) { create(:entity, name: "Order") }

  # `page` here is the AR record under test; assertions read `rendered_content`.
  def render_toolbar(**opts)
    render_inline(described_class.new(page: page, customer_id: customer_id, **opts))
  end

  describe "basic rendering" do
    before { render_toolbar }

    it "renders the toolbar header" do
      expect(rendered_content).to have_css("header")
    end

    it "displays the page name" do
      expect(rendered_content).to have_text("Test Page")
    end

    it "renders back link to pages index" do
      expect(rendered_content).to have_link(href: %r{/\d+/admin/maintenance/pages})
    end
  end

  describe "entity breadcrumb" do
    it "shows entity name when entity is present" do
      render_toolbar(selected_entity: entity)

      expect(rendered_content).to have_text("Order")
      expect(rendered_content).to have_link("Order")
    end

    it "hides entity breadcrumb when no entity" do
      render_toolbar(selected_entity: nil)

      expect(rendered_content).not_to have_text("Order")
    end
  end

  describe "tab buttons" do
    before { render_toolbar }

    it "renders all 5 icon-only tab buttons" do
      expect(rendered_content).to have_css("[data-page-builder-target='tabButton']", count: 5)
    end

    it "renders tabs with correct data-tab attributes" do
      %w[templates theme rules calculations settings].each do |tab|
        expect(rendered_content).to have_css("[data-tab='#{tab}']")
      end
    end

    it "renders tabs with title tooltips" do
      %w[Templates Theme Rules Calculations Settings].each do |title|
        expect(rendered_content).to have_css("[title='#{title}']")
      end
    end

    it "does not render text labels in tab buttons" do
      %w[Templates Theme Rules Calculations Settings].each do |label|
        expect(rendered_content).not_to have_css("[data-page-builder-target='tabButton']", text: label)
      end
    end
  end

  describe "embedded component palette" do
    before { render_toolbar }

    it "renders the layout-components palette inside the toolbar" do
      expect(rendered_content).to have_css("[data-page-builder-target='quickAddToolbar']")
    end

    it "renders icon-only insert buttons for each component type" do
      %w[section card columns heading paragraph image button alert].each do |type|
        expect(rendered_content).to have_css("[data-component-type='#{type}']")
      end
    end

    it "renders the contextual field-width group" do
      expect(rendered_content).to have_css("[data-page-builder-target='toolbarWidthGroup']")
      expect(rendered_content).to have_css("[data-page-builder-target='toolbarWidthBtn']", count: 4)
    end
  end

  describe "viewport toggle" do
    before { render_toolbar }

    it "renders desktop, tablet, and mobile buttons" do
      %w[desktop tablet mobile].each do |viewport|
        expect(rendered_content).to have_css("[data-viewport='#{viewport}']")
      end
    end
  end

  describe "action buttons" do
    before { render_toolbar }

    it "renders undo and redo buttons" do
      expect(rendered_content).to have_css("[data-page-builder-target='undoBtn']")
      expect(rendered_content).to have_css("[data-page-builder-target='redoBtn']")
    end

    it "renders undo/redo as disabled by default" do
      expect(rendered_content).to have_css("[data-page-builder-target='undoBtn'][disabled]")
      expect(rendered_content).to have_css("[data-page-builder-target='redoBtn'][disabled]")
    end

    it "renders preview button with tooltip" do
      expect(rendered_content).to have_css("button[title='Preview']")
    end

    it "renders hidden preview form" do
      expect(rendered_content).to have_css("form[data-page-builder-target='previewForm'].hidden")
    end

    it "renders save button" do
      expect(rendered_content).to have_css("[data-page-builder-target='saveBtn']", text: "Save")
    end
  end

  describe "slate color palette" do
    before { render_toolbar }

    it "uses slate colors instead of gray" do
      expect(rendered_content).to have_css("header.border-slate-200")
      expect(rendered_content).not_to have_css(".border-gray-200", visible: :all)
    end
  end
end
