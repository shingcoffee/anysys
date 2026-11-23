# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchableSelectComponent, type: :component do
  let(:grouped_options) do
    [
      ["Technology & Digital", [["Software", "software"], ["Gaming", "gaming"]]],
      ["Finance & Insurance", [["Banking", "banking"], ["Insurance", "insurance"]]]
    ]
  end

  def build_component(**opts)
    described_class.new(**{ name: "field", grouped_options: grouped_options }.merge(opts))
  end

  def render_select(**opts)
    render_inline(build_component(**opts))
  end

  describe "#initialize" do
    it "exposes the given name and grouped_options" do
      component = build_component(name: "customer[industry]")
      expect(component.name).to eq("customer[industry]")
      expect(component.grouped_options).to eq(grouped_options)
    end

    it "defaults placeholder to 'Search...'" do
      component = build_component(grouped_options: [])
      expect(component.placeholder).to eq("Search...")
    end

    it "accepts a custom placeholder" do
      component = build_component(grouped_options: [], placeholder: "Find industry...")
      expect(component.placeholder).to eq("Find industry...")
    end
  end

  describe "#options_json" do
    it "converts grouped options to JSON format" do
      parsed = JSON.parse(build_component.options_json)
      expect(parsed.length).to eq(2)
      expect(parsed.first["group"]).to eq("Technology & Digital")
      expect(parsed.first["items"]).to eq([["Software", "software"], ["Gaming", "gaming"]])
    end
  end

  describe "#has_selection?" do
    it "returns true when selected_value is present" do
      expect(build_component(grouped_options: [], selected_value: "software").has_selection?).to be true
    end

    it "returns false when selected_value is nil" do
      expect(build_component(grouped_options: [], selected_value: nil).has_selection?).to be false
    end

    it "returns false when selected_value is blank" do
      expect(build_component(grouped_options: [], selected_value: "").has_selection?).to be false
    end
  end

  describe "rendering" do
    it "renders the Stimulus controller wrapper" do
      render_select(name: "customer[industry]")
      expect(page).to have_css("[data-controller='searchable-select']")
    end

    it "renders hidden input with correct name" do
      render_select(name: "customer[industry]")
      expect(page).to have_css("input[type='hidden'][name='customer[industry]']", visible: :all)
    end

    it "renders hidden input with field_id" do
      render_select(name: "customer[industry]", field_id: "customer_industry")
      expect(page).to have_css("input#customer_industry[type='hidden']", visible: :all)
    end

    it "renders search input with placeholder" do
      render_select(placeholder: "Search industries...")
      expect(page).to have_css("input[type='text'][placeholder='Search industries...']")
    end

    it "renders hidden input with selected value" do
      render_select(selected_value: "software")
      expect(page).to have_css("input[type='hidden'][value='software']", visible: :all)
    end

    it "renders search icon" do
      render_select
      expect(page).to have_css("svg")
    end

    it "renders clear button" do
      render_select
      expect(page).to have_css("[data-searchable-select-target='clear']")
    end

    it "shows clear button when value is selected" do
      render_select(selected_value: "software")
      clear_btn = page.find("[data-searchable-select-target='clear']")
      expect(clear_btn[:class]).not_to include("hidden")
    end

    it "hides clear button when no value is selected" do
      render_select
      clear_btn = page.find("[data-searchable-select-target='clear']")
      expect(clear_btn[:class]).to include("hidden")
    end

    it "renders dropdown panel" do
      render_select
      expect(page).to have_css("[data-searchable-select-target='dropdown']")
    end

    it "passes options as JSON data attribute" do
      render_select
      wrapper = page.find("[data-controller='searchable-select']")
      parsed = JSON.parse(wrapper["data-searchable-select-options-value"])
      expect(parsed.length).to eq(2)
    end
  end
end
