# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::EntriesCsv do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    e = Entity.new(customer_id: customer.id, name: "Student")
    e.property_schema_json = [
      { "name_slug" => "first_name", "name" => "first name", "html_type" => "text", "type" => "String" },
      { "name_slug" => "grade", "name" => "grade", "html_type" => "select", "type" => "String",
        "config" => { "options" => [{ "label" => "A", "value" => "A" }, { "label" => "B", "value" => "B" }] } }
    ]
    e.save!
    e
  end
  let(:columns) do
    [
      { key: :id, label: "ID" },
      { key: :first_name, label: "First name", cell: ->(r) { r["first_name"] } },
      { key: :grade, label: "Grade", cell: ->(r) { r["grade"] } }
    ]
  end

  it "renders headers and rows" do
    a = create(:entity_entry, customer: customer, entity: entity, data: { "first_name" => "Alice", "grade" => "A" }.to_json)
    b = create(:entity_entry, customer: customer, entity: entity, data: { "first_name" => "Bob", "grade" => "B" }.to_json)
    csv = described_class.call(rows: [a, b], columns: columns)
    expect(csv).to include("ID,First name,Grade")
    expect(csv).to include("Alice")
    expect(csv).to include("Bob")
  end

  it "honours the columns list (visible columns only)" do
    a = create(:entity_entry, customer: customer, entity: entity, data: { "first_name" => "Alice", "grade" => "A" }.to_json)
    csv = described_class.call(rows: [a], columns: columns.first(2))
    expect(csv).to include("ID,First name")
    expect(csv).not_to include("Grade")
  end

  it "exports display text" do
    entity.property_schema_json = [
      { "name_slug" => "mode", "name" => "Mode", "html_type" => "select", "type" => "String",
        "config" => { "options" => [{ "label" => "In person", "value" => "in_person" }] } }
    ]
    entity.save!
    setting = EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id)
    setting.write_overlay(visible_column_keys: %w[mode])
    setting.save!
    row = create(:entity_entry, customer: customer, entity: entity, data: { "mode" => "in_person" }.to_json)
    display = Entities::EntryDisplay.new(
      entity: entity,
      entries: [row],
      customer_id: entity.customer_id,
      audience: EntityAttributeAudience::ADMIN
    )
    built = Admin::Entities::ColumnsBuilder.call(
      entity: entity,
      setting: setting,
      customer_id: entity.customer_id,
      display: display
    )
    csv = described_class.call(rows: [row], columns: built)
    expect(csv).to include("In person")
    expect(csv).not_to include("in_person")
  end

  it "neutralizes formulas in headers and text while preserving numeric cells" do
    values = ["=HYPERLINK(\"https://example.test\")", "+cmd", "-2+3", "@SUM(1)", "  =1+1", "\tplain", "\rplain", "\nplain", "\uFEFF=1", -12, "plain, quoted \"text\""]
    rows = values.map { |value| { value: value } }
    csv = described_class.call(rows: rows, columns: [{ key: :value, label: "=Header" }])
    parsed = CSV.parse(csv)

    expect(parsed.first).to eq(["'=Header"])
    expect(parsed.drop(1).flatten).to eq(values.map { |value| value.is_a?(String) && value != values.last ? "'#{value}" : value.to_s })
  end
end
