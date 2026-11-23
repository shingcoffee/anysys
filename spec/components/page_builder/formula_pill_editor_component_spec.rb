# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::FormulaPillEditorComponent, type: :component do
  let(:fields) { [{ "id" => "price", "label" => "Price", "property_type" => "number" }] }

  def render_editor(formula)
    render_inline(described_class.new(formula: formula, fields: fields))
  end

  it "renders a contentEditable surface wired to the formula_editor controller" do
    render_editor("{price} * 2")
    expect(page).to have_css('[data-controller~="formula-editor"]')
    expect(page).to have_css('[contenteditable="true"][data-formula-editor-target="surface"]')
  end

  it "passes field metadata as JSON for autocomplete" do
    render_editor("")
    expect(page).to have_css('[data-formula-editor-fields-value]')
  end

  it "renders the autocomplete dropdown target" do
    render_editor("")
    expect(page).to have_css('[data-formula-editor-target="autocomplete"]')
  end

  it "renders the validation status and preview targets" do
    render_editor("")
    expect(page).to have_css('[data-formula-editor-target="status"]')
    expect(page).to have_css('[data-formula-editor-target="preview"]')
    expect(page).to have_css('[data-formula-editor-target="errors"]')
  end

  it "stores formula value in data attribute" do
    render_editor("{price} * 2")
    expect(page).to have_css('[data-formula-editor-formula-value="{price} * 2"]')
  end
end
