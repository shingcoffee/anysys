# frozen_string_literal: true

require "rails_helper"

RSpec.describe InlineSearchComponent, type: :component do
  let(:customer_id) { 123 }

  def render_search(**opts)
    render_inline(described_class.new(**{ customer_id: customer_id }.merge(opts)))
  end

  describe "desktop mode (default)" do
    it "renders a trigger button with search label and ⌘K hint" do
      render_search
      expect(page).to have_css("button[aria-label='Open search']")
      expect(page).to have_css("button", text: "Search")
      expect(page).to have_css("kbd", text: "⌘")
      expect(page).to have_css("kbd", text: "K")
    end

    it "wires the trigger to expand action" do
      render_search
      expect(page).to have_css("button[data-action*='inline-search#expand']")
    end

    it "has hidden expanded state with input field" do
      render_search
      expect(page).to have_css("[data-inline-search-target='expanded'].hidden", visible: :all)
      expect(page).to have_css("input[data-inline-search-target='input']", visible: :all)
    end

    it "passes customer_id as a stimulus value" do
      render_search
      expect(page).to have_css("[data-inline-search-customer-id-value='#{customer_id}']")
    end
  end

  describe "mobile mode" do
    it "renders a compact icon-only trigger" do
      render_search(mobile: true)
      expect(page).to have_css("button[aria-label='Open search']")
      expect(page).to have_no_text("Search")
      expect(page).to have_no_css("kbd")
    end
  end
end
