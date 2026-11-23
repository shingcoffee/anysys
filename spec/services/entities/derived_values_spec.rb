# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::DerivedValues do
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
  let!(:john) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:jane) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:empty) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:math) { create(:entity_entry, entity: klass, customer: customer, data: {}.to_json) }

  def enroll(pupil_id, score:, owner: customer)
    create(:entity_entry, entity: bridge, customer: owner,
                          data: { "student" => pupil_id, "class" => math.id.to_s, "score" => score.to_s }.to_json)
  end

  def computed(slug, function, source_slug: "score")
    { "name" => slug.titleize, "name_slug" => slug, "type" => "Computed",
      "config" => { "bridge_entity_id" => bridge.id, "bridge_role" => "source", "source_slug" => source_slug,
                    "function" => function, "precision" => 2 } }
  end

  def calculated(slug, formula)
    { "name" => slug.titleize, "name_slug" => slug, "type" => "Calculated", "html_type" => "number", "formula" => formula }
  end

  def with_schema(*fields)
    student.property_schema_json = fields
    student.save(validate: false)
    student.reload
  end

  def load_for(*entries) = described_class.call(entity: student.reload, customer_id: customer.id, entry_ids: entries.map(&:id))

  def value_queries(&block)
    sqls = []
    subscriber = ->(*, payload) { sqls << payload[:sql].to_s if payload[:sql].to_s.match?(/\ASELECT "entity_entries"\."id", /) }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
    sqls
  end

  before do
    enroll(john.id.to_s, score: 90)
    enroll(john.id.to_s, score: 85)
    enroll(jane.id.to_s, score: 80)
  end

  it "counts a link whose parent id is stored as a JSON number (P1)" do
    with_schema(computed("enrolments", "count", source_slug: ""))
    enroll(jane.id, score: 70)

    expect(load_for(jane)[jane.id]["enrolments"]).to eq(2)
  end

  it "keeps today's coercion and empty defaults" do
    with_schema(computed("average_score", "avg"), computed("lowest", "min"), computed("total_score", "sum"),
                computed("enrolments", "count", source_slug: ""))

    result = load_for(john, empty)
    expect(result[john.id]).to eq("average_score" => 87.5, "lowest" => 85.0, "total_score" => 175.0, "enrolments" => 2)
    expect(result[empty.id]).to eq("average_score" => nil, "lowest" => nil, "total_score" => 0, "enrolments" => 0)
  end

  it "returns a calculated field that reads a computed one" do
    with_schema(computed("average_score", "avg"), calculated("double_average", "average_score * 2"))

    expect(load_for(john)[john.id]["double_average"]).to eq(175.0)
  end

  it "leaves calculated values blank when a formula does not compile" do
    with_schema(computed("average_score", "avg"), calculated("broken", "average_score +"))

    expect(load_for(john)[john.id]).to eq("average_score" => 87.5, "broken" => nil)
  end

  it "uses the definition's default for a computed field that does not resolve" do
    with_schema(computed("enrolments", "count").merge("config" => { "function" => "count" }),
                computed("odd", "avg").merge("config" => "nope"))

    expect(load_for(john)[john.id]).to eq("enrolments" => 0, "odd" => nil)
  end

  it "never counts another tenant's link rows" do
    with_schema(computed("enrolments", "count", source_slug: ""))
    enroll(john.id.to_s, score: 10, owner: create(:customer))

    expect(load_for(john)[john.id]["enrolments"]).to eq(2)
  end

  it "reads any number of entries in one query" do
    with_schema(computed("average_score", "avg"), computed("total_score", "sum"), calculated("double_average", "average_score * 2"))
    many = [john, jane, empty] + Array.new(5) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }

    expect(value_queries { load_for(*many) }.size).to eq(1)
  end

  it "returns {} for no ids or a nil entity, and empty hashes without derived fields" do
    expect(described_class.call(entity: student, customer_id: customer.id, entry_ids: [])).to eq({})
    expect(described_class.call(entity: nil, customer_id: customer.id, entry_ids: [john.id])).to eq({})
    expect(load_for(john)).to eq(john.id => {})
  end

  describe ".prime!" do
    it "memoizes values on each entry of the tenant and skips the rest" do
      with_schema(computed("average_score", "avg"))
      fresh = EntityEntry.find(john.id)
      foreign = create(:entity_entry, entity: student, customer: create(:customer), data: {}.to_json)

      described_class.prime!([fresh, "skip", foreign], customer_id: customer.id)

      expect(value_queries { expect(fresh.derived_values["average_score"]).to eq(87.5) }).to eq([])
      expect(foreign.instance_variable_get(:@derived_values)).to be_nil
      expect { described_class.prime!(nil, customer_id: customer.id) }.not_to raise_error
    end
  end

  describe "EntityEntry#derived_values" do
    it "resolves a lone entry in one query" do
      with_schema(computed("average_score", "avg"), calculated("double_average", "average_score * 2"))

      expect(EntityEntry.find(john.id).derived_values).to eq("average_score" => 87.5, "double_average" => 175.0)
    end
  end
end
