# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ComputedOptions do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let!(:student) { create(:entity, name: "Student", customer: customer, display_label: "Student") }
  let!(:klass) do
    create(:entity, name: "Class", customer: customer, display_label: "Class",
           property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end

  let(:score_attr) do
    { "name" => "Score", "name_slug" => "score", "display_label" => "Score", "type" => "Float", "html_type" => "number" }
  end
  let(:weight_attr) do
    { "name" => "Weight", "name_slug" => "weight", "display_label" => "Weight", "type" => "Float", "html_type" => "range" }
  end
  let(:note_attr) do
    { "name" => "Note", "name_slug" => "note", "display_label" => "Note", "type" => "String", "html_type" => "text" }
  end

  let!(:bridge) do
    student.associations_json = [{
      "target_entity_id" => klass.id,
      "target_entity_name" => klass.name,
      "target_entity_display_label" => klass.display_label,
      "display_field" => "name",
      "display_field_label" => "Name",
      "additional_attributes" => [score_attr, weight_attr, note_attr]
    }]
    student.save!
    student.sync_bridge_entities!
    student.reload
    Entity.find_by!(name: "assoc_student_class", customer_id: customer.id)
  end

  def options_for(entity)
    described_class.call(entity: entity, customer_id: customer.id)
  end

  it "returns a forward option from associations_list with role source" do
    option = options_for(student).find { |o| o["bridge_role"] == "source" }
    expect(option).to include(
      "bridge_entity_id" => bridge.id,
      "bridge_role" => "source",
      "related_entity_label" => "Class",
      "bridge_label" => bridge.display_label.presence || bridge.name
    )
    expect(option["attributes"]).to include(
      { "slug" => "score", "label" => "Score", "numeric" => true },
      { "slug" => "weight", "label" => "Weight", "numeric" => true },
      { "slug" => "note", "label" => "Note", "numeric" => false }
    )
  end

  it "discovers a reverse option from bridges where the host is at schema index 1" do
    option = options_for(klass).find { |o| o["bridge_role"] == "target" }
    expect(option).to include(
      "bridge_entity_id" => bridge.id,
      "bridge_role" => "target",
      "related_entity_label" => "Student"
    )
    expect(option["attributes"].map { |a| a["slug"] }).to contain_exactly("score", "weight", "note")
  end

  it "sets numeric from html_type number/range" do
    attrs = options_for(student).first["attributes"].index_by { |a| a["slug"] }
    expect(attrs["score"]["numeric"]).to be true
    expect(attrs["weight"]["numeric"]).to be true
    expect(attrs["note"]["numeric"]).to be false
  end

  it "returns [] for a new record" do
    expect(described_class.call(entity: Entity.new(customer: customer), customer_id: customer.id)).to eq([])
  end

  it "returns [] for a bridge entity" do
    expect(options_for(bridge)).to eq([])
  end

  it "only includes same-tenant bridges" do
    other_student = create(:entity, name: "Student", customer: other_customer, display_label: "Student")
    other_klass = create(:entity, name: "Class", customer: other_customer, display_label: "Class",
                         property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    other_student.associations_json = [{
      "target_entity_id" => other_klass.id,
      "target_entity_name" => other_klass.name,
      "display_field" => "name",
      "display_field_label" => "Name",
      "additional_attributes" => [score_attr]
    }]
    other_student.save!
    other_student.sync_bridge_entities!
    other_bridge = Entity.find_by!(name: "assoc_student_class", customer_id: other_customer.id)

    ids = options_for(student).map { |o| o["bridge_entity_id"] }
    expect(ids).to include(bridge.id)
    expect(ids).not_to include(other_bridge.id)

    foreign = described_class.call(entity: other_student.reload, customer_id: other_customer.id)
    expect(foreign.map { |o| o["bridge_entity_id"] }).to eq([other_bridge.id])
  end

  it "flags attributes.numeric from the canonical html types the filter UI consumes" do
    expect(described_class::NUMERIC_HTML_TYPES).to eq(Entities::ComputedCompiler::NUMERIC_HTML_TYPES)
    expect(described_class::NUMERIC_HTML_TYPES).to contain_exactly("number", "range")

    attrs = options_for(student).first["attributes"].index_by { |a| a["slug"] }
    expect(attrs.fetch("score")).to include("numeric" => true)
    expect(attrs.fetch("weight")).to include("numeric" => true)
    expect(attrs.fetch("note")).to include("numeric" => false)
  end
end
