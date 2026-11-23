# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::FiltersBuilder do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    e = Entity.new(customer_id: customer.id, name: "Student")
    e.property_schema_json = [
      { "name_slug" => "grade", "name" => "grade", "display_label" => "grade",
        "html_type" => "select", "type" => "String",
        "config" => { "options" => [{ "label" => "A", "value" => "A" }, { "label" => "B", "value" => "B" }] } },
      { "name_slug" => "active", "name" => "active", "html_type" => "checkbox", "type" => "Boolean" },
      { "name_slug" => "notes", "name" => "notes", "html_type" => "textarea", "type" => "Text" }
    ]
    e.save!
    e
  end

  subject(:filters) { described_class.call(entity: entity) }

  it "builds filters for select/radio/checkbox only" do
    expect(filters.map { |f| f[:key] }).to eq(%i[grade active])
  end

  it "uses authored labels and maps options" do
    grade = filters.find { |f| f[:key] == :grade }
    expect(grade[:label]).to eq("grade")
    expect(grade[:options]).to eq([["A", "A"], ["B", "B"]])
  end

  it "falls back to the raw slug when a select has no name or display_label" do
    entity.property_schema_json = [
      { "name_slug" => "raw_choice", "html_type" => "select", "type" => "String",
        "config" => { "options" => [{ "label" => "A", "value" => "A" }] } }
    ]
    entity.save!
    filter = described_class.call(entity: entity).find { |f| f[:key] == :raw_choice }
    expect(filter[:label]).to eq("raw_choice")
  end

  it "skips a selection field that enumerates no options" do
    entity.property_schema_json = [
      { "name_slug" => "grade", "name" => "grade", "html_type" => "select", "type" => "String",
        "config" => { "options" => [{ "label" => "A", "value" => "A" }] } },
      { "name_slug" => "empty_select", "name" => "empty", "html_type" => "select", "type" => "String" },
      { "name_slug" => "blank_options", "name" => "blank", "html_type" => "radio", "type" => "String",
        "config" => { "options" => [] } }
    ]
    entity.save!
    keys = described_class.call(entity: entity).map { |f| f[:key] }
    expect(keys).to eq(%i[grade])
  end

  it "checkbox filter uses Yes/No" do
    active = filters.find { |f| f[:key] == :active }
    expect(active[:options]).to eq([
      [I18n.t("common.labels.yes"), "true"],
      [I18n.t("common.labels.no"), "false"]
    ])
  end

  it "scope filters via json_extract" do
    create(:entity_entry, customer: customer, entity: entity, data: { "grade" => "A" }.to_json)
    create(:entity_entry, customer: customer, entity: entity, data: { "grade" => "B" }.to_json)
    rel = EntityEntry.where(customer_id: customer.id, entity_id: entity.id)
    grade = filters.find { |f| f[:key] == :grade }
    expect(grade[:scope].call(rel, "A").count).to eq(1)
  end

  describe "checkbox scope" do
    let(:rel) { EntityEntry.where(customer_id: customer.id, entity_id: entity.id) }
    let(:active) { filters.find { |f| f[:key] == :active } }

    it "matches JSON boolean true when filtering for true" do
      entry = create(:entity_entry, customer: customer, entity: entity, data: { "active" => true }.to_json)
      expect(active[:scope].call(rel, "true")).to contain_exactly(entry)
    end

    it "matches JSON boolean false when filtering for false" do
      entry = create(:entity_entry, customer: customer, entity: entity, data: { "active" => false }.to_json)
      expect(active[:scope].call(rel, "false")).to contain_exactly(entry)
    end

    it "matches string true when filtering for true" do
      entry = create(:entity_entry, customer: customer, entity: entity, data: { "active" => "true" }.to_json)
      expect(active[:scope].call(rel, "true")).to contain_exactly(entry)
    end
  end
end
