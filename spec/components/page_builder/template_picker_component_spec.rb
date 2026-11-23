# spec/components/page_builder/template_picker_component_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::TemplatePickerComponent, type: :component do
  let(:category_counts) { { "all" => 3, "contact" => 1 } }
  let(:base_args) do
    {
      selected_template: nil,
      category_counts: category_counts,
      cards_url: "/1/admin/maintenance/template_picker_cards?scope=industry",
      field_name: "entity[referenced_template]",
      field_value: "",
      field_key: "",
      confirm_label: "Use Template"
    }
  end

  def build_picker(**overrides)
    described_class.new(**base_args.merge(overrides))
  end

  def render_picker(**overrides)
    render_inline(build_picker(**overrides))
  end

  it "renders the empty trigger when nothing is selected" do
    render_picker
    expect(page).to have_css("[data-template-selector-target='triggerEmpty']")
    expect(page).to have_text("Choose Template")
  end

  it "renders the selected trigger summary when a template is selected" do
    render_picker(
      selected_template: { key: "contact_basic", name: "Basic Contact", theme_preset: "modern" },
      field_key: "contact_basic"
    )
    expect(page).to have_css("[data-template-selector-target='triggerSelected']:not(.hidden)")
    expect(page).to have_text("Basic Contact")
  end

  it "renders an empty grid container (cards are lazy-loaded)" do
    render_picker
    expect(page).to have_css("[data-template-selector-target='templateContainer']")
    expect(page).not_to have_css("[data-template-key]") # no cards rendered server-side
  end

  it "renders the hidden field with the given name, value and template key" do
    render_picker(field_name: "page[layout_template]", field_value: "blank", field_key: "blank")
    input = page.find("input[type='hidden'][name='page[layout_template]']", visible: :all)
    expect(input[:value]).to eq("blank")
    expect(input["data-template-key"]).to eq("blank")
    expect(input["data-template-selector-target"]).to eq("selectedTemplate")
  end

  it "renders the change/clear affordances and a (hidden) locked note for the lock toggle" do
    render_picker(
      selected_template: { key: "contact_basic", name: "Basic Contact", theme_preset: "modern" },
      field_key: "contact_basic"
    )
    # Targets the Stimulus controller toggles when the bound entity locks the choice.
    expect(page).to have_css("[data-template-selector-target='changeBtn']")
    expect(page).to have_css("[data-template-selector-target='clearTemplateBtn']")
    # The locked note ships hidden; it is revealed only when an entity sets the template.
    expect(page).to have_css("[data-template-selector-target='lockedNote'].hidden", visible: :all)
  end

  it "renders the confirm button with the given label" do
    render_picker(confirm_label: "Apply Layout")
    expect(page).to have_button("Apply Layout")
  end

  it "exposes the cards url for the Stimulus controller to read" do
    render_picker
    expect(page).to have_css("[data-template-picker-cards-url='#{base_args[:cards_url]}']")
  end

  describe "#selected_name" do
    it "returns template name from symbol key" do
      component = build_picker(
        selected_template: { key: "basic", name: "Basic Form", theme_preset: "modern" },
        field_key: "basic"
      )
      expect(component.selected_name).to eq("Basic Form")
    end

    it "returns template name from string key" do
      component = build_picker(
        selected_template: { "key" => "basic", "name" => "Basic Form String", "theme_preset" => "modern" },
        field_key: "basic"
      )
      expect(component.selected_name).to eq("Basic Form String")
    end

    it "falls back to field_key when template has no name" do
      component = build_picker(selected_template: nil, field_key: "fallback_key")
      expect(component.selected_name).to eq("fallback_key")
    end
  end

  describe "#selected_theme" do
    it "returns theme from symbol key" do
      component = build_picker(selected_template: { theme_preset: "bold" }, field_key: "x")
      expect(component.selected_theme).to eq("bold")
    end

    it "returns theme from string key" do
      component = build_picker(selected_template: { "theme_preset" => "minimal" }, field_key: "x")
      expect(component.selected_theme).to eq("minimal")
    end

    it "returns nil when selected_template is nil" do
      component = build_picker(selected_template: nil, field_key: "")
      expect(component.selected_theme).to be_nil
    end
  end

  describe "#selected?" do
    it "returns false when field_key is blank" do
      component = build_picker(field_key: "")
      expect(component.selected?).to eq(false)
    end

    it "returns true when field_key is present" do
      component = build_picker(field_key: "some_key")
      expect(component.selected?).to eq(true)
    end
  end
end
