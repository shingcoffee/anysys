# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::DerivedExpressions do
  let_it_be(:customer) { create(:customer) }
  let!(:student) { create(:entity, name: "Student", customer: customer) }
  let!(:klass) { create(:entity, name: "Class", customer: customer) }
  let!(:bridge) do
    create(:entity, name: "assoc_student_class", customer: customer, category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id.to_s },
      { "name" => "Class", "name_slug" => "class", "type" => "EntityReference", "entity_id" => klass.id.to_s },
      { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  let(:average) do
    { "name" => "Average", "name_slug" => "average_score", "type" => "Computed",
      "config" => { "bridge_entity_id" => bridge.id, "bridge_role" => "source", "source_slug" => "score", "function" => "avg" } }
  end

  def calculated(slug, formula)
    { "name" => slug.titleize, "name_slug" => slug, "type" => "Calculated", "html_type" => "number", "formula" => formula }
  end

  def with_schema(*fields)
    student.property_schema_json = fields
    student.save(validate: false)
    student.reload
  end

  def expressions = described_class.for(student, customer_id: customer.id)

  it "lists computed subqueries, then calculated formulas that may read them" do
    with_schema(average, calculated("double_average", "average_score * 2"))

    expect(expressions.map { |row| [row[:name], row[:kind]] }).to eq([["average_score", :computed], ["double_average", :calculated]])
    computed_sql = expressions.first[:sql]
    expect(expressions.first[:definition]).to be_a(Entities::ComputedDefinition)
    expect(expressions.last[:sql]).to include("(#{computed_sql})")
  end

  it "drops every calculated field when a formula does not compile, keeping computed ones" do
    with_schema(average, calculated("broken", "average_score +"))

    expect(expressions.map { |row| row[:name] }).to eq(%w[average_score])
  end

  it "drops a computed field that does not resolve and a name that is not a safe alias" do
    with_schema(average.merge("config" => { "bridge_entity_id" => 0 }), calculated("bad-name", "1 + 1"))

    expect(expressions).to eq([])
  end

  it "is empty for a nil entity or an entity without derived fields" do
    expect(described_class.for(nil, customer_id: customer.id)).to eq([])
    expect(described_class.for(klass, customer_id: customer.id)).to eq([])
  end
end
