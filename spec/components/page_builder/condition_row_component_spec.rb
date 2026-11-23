# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::ConditionRowComponent, type: :component do
  let(:fields) do
    [
      { "id" => "country", "label" => "Country", "property_type" => "select",
        "options" => [{ "value" => "US", "label" => "United States" }] },
      { "id" => "age", "label" => "Age", "property_type" => "number" },
      { "id" => "name", "label" => "Name", "property_type" => "text" },
      { "id" => "active", "label" => "Active", "property_type" => "boolean" }
    ]
  end

  # `item` is passed positionally (a local var, never a bare literal) so it can't
  # be swallowed as keywords; `fields` falls back to the let when not overridden.
  def render_row(item, group_index: 0, item_index: 0, fields: nil)
    render_inline(described_class.new(
      item: item, fields: fields || self.fields,
      group_index: group_index, item_index: item_index
    ))
  end

  it "renders a select value editor for a select field" do
    render_row({ "field_id" => "country", "operator" => "equals", "value" => "US" })
    expect(page).to have_css('select[data-condition-value]')
    expect(page).to have_css('option[value="US"]')
  end

  it "renders no value input for is_empty" do
    render_row({ "field_id" => "age", "operator" => "is_empty", "value" => "" })
    expect(page).not_to have_css('[data-condition-value]')
  end

  it "renders no value input for is_not_empty" do
    render_row({ "field_id" => "name", "operator" => "is_not_empty", "value" => "" })
    expect(page).not_to have_css('[data-condition-value]')
  end

  it "renders a number input for number fields with a non-range operator" do
    render_row({ "field_id" => "age", "operator" => "greater_than", "value" => "18" })
    expect(page).to have_css('input[type="number"][data-condition-value]')
  end

  it "renders two number inputs for between operator on number field" do
    render_row({ "field_id" => "age", "operator" => "between", "value" => [18, 65] }, group_index: 1, item_index: 2)
    expect(page).to have_css('input[type="number"][data-condition-value]')
    expect(page).to have_css('input[type="number"][data-condition-value-max]')
  end

  it "renders a boolean select for boolean fields" do
    # is_selected is NO_VALUE for boolean so no value editor
    render_row({ "field_id" => "active", "operator" => "is_selected", "value" => "" })
    expect(page).not_to have_css('[data-condition-value]')
  end

  it "renders text input by default" do
    render_row({ "field_id" => "name", "operator" => "contains", "value" => "foo" })
    expect(page).to have_css('input[type="text"][data-condition-value]')
  end

  it "renders the field selector wired to rule-builder#onConditionFieldChange" do
    render_row({ "field_id" => "name", "operator" => "equals", "value" => "" })
    expect(page).to have_css('[data-action*="onConditionFieldChange"]')
  end

  it "renders the remove button" do
    render_row({ "field_id" => "name", "operator" => "equals", "value" => "" }, group_index: 2, item_index: 1)
    expect(page).to have_css('[data-action*="removeConditionItem"]')
    expect(page).to have_css('[data-group-index="2"][data-item-index="1"]')
  end

  it "renders a boolean value editor for boolean field with a non-no-value operator (equals)" do
    # value_editor_kind should return :boolean when field_type is 'boolean' and operator is 'equals'
    render_row({ "field_id" => "active", "operator" => "equals", "value" => "true" })
    expect(page).to have_css('select[data-condition-value]')
  end

  it "renders a date input for date fields with a non-between operator" do
    date_fields = fields + [{ "id" => "birthday", "label" => "Birthday", "property_type" => "date" }]
    render_row({ "field_id" => "birthday", "operator" => "greater_than", "value" => "2000-01-01" }, fields: date_fields)
    expect(page).to have_css('input[type="date"][data-condition-value]')
  end

  it "renders two date inputs for between operator on date field" do
    date_fields = fields + [{ "id" => "birthday", "label" => "Birthday", "property_type" => "date" }]
    render_row({ "field_id" => "birthday", "operator" => "between", "value" => ["2000-01-01", "2010-12-31"] }, fields: date_fields)
    expect(page).to have_css('input[type="date"][data-condition-value]')
    expect(page).to have_css('input[type="date"][data-condition-value-max]')
  end

  it "renders a select value editor for radio fields" do
    radio_fields = fields + [{ "id" => "color", "label" => "Color", "property_type" => "radio",
                                "options" => [{ "value" => "red", "label" => "Red" }] }]
    render_row({ "field_id" => "color", "operator" => "equals", "value" => "red" }, fields: radio_fields)
    expect(page).to have_css('select[data-condition-value]')
    expect(page).to have_css('option[value="red"]')
  end

  it "renders text input when field_id does not match any field (nil field => default type)" do
    render_row({ "field_id" => "nonexistent_field", "operator" => "contains", "value" => "x" })
    expect(page).to have_css('input[type="text"][data-condition-value]')
  end

  it "field_options returns empty array when field is not found" do
    item = { "field_id" => "ghost", "operator" => "equals" }
    component = described_class.new(item: item, fields: fields, group_index: 0, item_index: 0)
    expect(component.field_options).to eq([])
  end

  it "renders no value input for is_selected on boolean field" do
    item = { "field_id" => "active", "operator" => "is_not_selected", "value" => "" }
    render_inline(described_class.new(item: item, fields: fields, group_index: 0, item_index: 0))
    expect(page).not_to have_css('[data-condition-value]')
  end

  it "current_value returns empty string when item has no value key" do
    # Covers the `|| ""` RHS in `item["value"]&.to_s || ""`
    item = { "field_id" => "name", "operator" => "contains" }
    component = described_class.new(item: item, fields: fields, group_index: 0, item_index: 0)
    expect(component.send(:current_value)).to eq("")
  end
end
