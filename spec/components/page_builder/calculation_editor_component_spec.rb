# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::CalculationEditorComponent, type: :component do
  let(:fields) { [{ "id" => "price", "label" => "Price", "property_type" => "number" }] }
  let(:pages)  { [{ "id" => "p1", "name" => "Page 1", "fields" => fields }] }

  before { render_inline(described_class.new(calculation: nil, fields: fields, pages: pages)) }

  it "keeps target select and all four format controls" do
    expect(page).to have_css("[data-page-builder-target='calculationTargetField']")
    %w[type decimals prefix suffix].each do |k|
      expect(page).to have_css("[data-calc-format='#{k}']")
    end
  end

  it "keeps the formula-editor pill surface and sample values" do
    expect(page).to have_css("[data-controller='formula-editor']")
    expect(page).to have_css("[data-formula-editor-target='surface']")
    expect(page).to have_css("[data-calc-sample-values]")
  end

  it "renders the categorized function inserter with all 31 functions" do
    # Math 12 + Logic 5 + Text 7 + Date 7 = 31. Non-Math chips start hidden
    # (style=display:none) until their tab is selected, so count all of them.
    expect(page).to have_css("[data-fn-insert]", count: 31, visible: :all)
  end

  it "shows only the Math category by default and hides the rest" do
    expect(page).to have_css("[data-fn-insert][data-category='Math']", count: 12)
    expect(page).to have_css("[data-fn-insert][data-category='Text']", visible: :hidden)
  end

  it "excludes layout elements and field groups from referenceable/target fields" do
    fields = [
      { "id" => "f_price", "label" => "Price", "property_type" => "number" },
      { "id" => "f_sec", "label" => "Section Header", "property_type" => "layout", "field_type" => "section" },
      { "id" => "f_div", "label" => "Divider", "property_type" => "layout", "field_type" => "divider" },
      { "id" => "f_grp", "label" => "Group", "type" => "field_group" }
    ]
    render_inline(described_class.new(calculation: nil, fields: fields, pages: [{ "id" => "p1", "name" => "P1", "fields" => fields }]))
    # The "+ Insert field" picker and the target select should list only the value field
    expect(page).to have_css("option[value='f_price']")
    expect(page).not_to have_css("option[value='f_sec']")
    expect(page).not_to have_css("option[value='f_div']")
    expect(page).not_to have_css("option[value='f_grp']")
    # The pill editor's field map (autocomplete source) excludes them too
    fields_value = page.find("[data-controller='formula-editor']")["data-formula-editor-fields-value"]
    expect(fields_value).to include("f_price")
    expect(fields_value).not_to include("f_sec")
    expect(fields_value).not_to include("f_grp")
  end

  it "renders save and cancel buttons" do
    expect(page).to have_button("Save")
    expect(page).to have_button("Cancel")
  end

  it "wires save to page-builder#saveCalculation" do
    expect(page).to have_css("[data-action='click->page-builder#saveCalculation']")
  end

  it "wires cancel to page-builder#closeFormulaEditor" do
    expect(page).to have_css("[data-action='click->page-builder#closeFormulaEditor']")
  end

  it "renders format type options including all four" do
    described_class::FORMAT_TYPES.each do |ft|
      expect(page).to have_css("option[value='#{ft[:value]}']")
    end
  end

  it "exposes fnGrid target for the function inserter" do
    expect(page).to have_css("[data-formula-editor-target='fnGrid']")
  end

  it "exposes fnSearch target" do
    expect(page).to have_css("[data-formula-editor-target='fnSearch']")
  end

  context "with multi-page fields" do
    let(:pages_multi) do
      [
        { "id" => "p1", "name" => "Page 1", "fields" => [{ "id" => "price" }] },
        { "id" => "p2", "name" => "Page 2", "fields" => [] }
      ]
    end

    it "groups fields by page when multiple pages" do
      render_inline(described_class.new(calculation: nil, fields: fields, pages: pages_multi))
      expect(page).to have_css("optgroup[label='Page 1']")
    end
  end

  context "pre-fills target field" do
    it "selects the correct option when calculation has target_field_id" do
      render_inline(described_class.new(
        calculation: { "target_field_id" => "price", "formula" => "" },
        fields: fields
      ))
      expect(page).to have_css("option[value='price'][selected]")
    end
  end
end
