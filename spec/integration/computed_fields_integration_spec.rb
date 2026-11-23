# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Computed fields integration", type: :model do
  let(:customer) { create(:customer) }
  let(:student) { create(:entity, name: "Student", customer: customer, display_label: "Student") }
  let(:klass) do
    create(:entity, name: "Class", customer: customer, display_label: "Class",
           property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end

  let(:score_attr) do
    { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
  end
  let(:status_attr) do
    { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
  end

  let!(:bridge) do
    student.associations_json = [{
      "target_entity_id" => klass.id,
      "target_entity_name" => klass.name,
      "display_field" => "name",
      "display_field_label" => "Name",
      "additional_attributes" => [score_attr, status_attr]
    }]
    student.save!
    student.sync_bridge_entities!
    student.reload
    Entity.find_by!(name: "assoc_student_class", customer_id: customer.id)
  end

  let!(:john) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:jane) { create(:entity_entry, entity: student, customer: customer, data: {}.to_json) }
  let!(:math) { create(:entity_entry, entity: klass, customer: customer, data: {}.to_json) }
  let!(:science) { create(:entity_entry, entity: klass, customer: customer, data: {}.to_json) }

  def enroll(pupil, course, score:, status: nil, host: customer, junction: bridge)
    data = {
      "student" => pupil.id.to_s,
      "class" => course.id.to_s,
      "score" => score.to_s
    }
    data["status"] = status unless status.nil?
    create(:entity_entry, entity: junction, customer: host, data: data.to_json)
  end

  def computed_field(slug, function, host_role:, source_slug: "score", precision: 2, filter: nil)
    config = {
      "bridge_entity_id" => bridge.id,
      "bridge_role" => host_role,
      "source_slug" => source_slug,
      "function" => function,
      "precision" => precision
    }
    config["filter"] = filter if filter
    {
      "name" => slug.titleize,
      "display_label" => slug.titleize,
      "name_slug" => slug,
      "type" => "Computed",
      "html_type" => "number",
      "readonly" => true,
      "storage" => "computed",
      "config" => config
    }
  end

  def attach_student_computed_fields!
    student.property_schema_json = [
      computed_field("average_score", "avg", host_role: "source"),
      computed_field("total_score", "sum", host_role: "source"),
      computed_field("lowest_score", "min", host_role: "source"),
      computed_field("highest_score", "max", host_role: "source"),
      computed_field("enrollment_count", "count", host_role: "source", source_slug: "")
    ]
    student.save!
    student.reload
  end

  def attach_class_computed!
    klass.property_schema_json = [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
      computed_field("average_score", "avg", host_role: "target")
    ]
    klass.save!
    klass.reload
  end

  def load(entity, *entries)
    Entities::DerivedValues.call(entity: entity.reload, customer_id: customer.id, entry_ids: entries.map(&:id))
  end

  before do
    enroll(john, math, score: 90)
    enroll(john, science, score: 85)
    enroll(jane, math, score: 80)
    attach_student_computed_fields!
    attach_class_computed!
  end

  it "computes the student's average score across bridge rows" do
    result = load(student, john, jane)
    expect(result[john.id]["average_score"]).to eq(87.5)
    expect(result[jane.id]["average_score"]).to eq(80.0)
  end

  it "computes sum, count, min, and max on the same bridge" do
    result = load(student, john)
    expect(result[john.id]["total_score"]).to eq(175.0)
    expect(result[john.id]["enrollment_count"]).to eq(2)
    expect(result[john.id]["lowest_score"]).to eq(85.0)
    expect(result[john.id]["highest_score"]).to eq(90.0)
  end

  it "computes the reverse-direction class average over the same bridge" do
    result = load(klass, math, science)
    expect(result[math.id]["average_score"]).to eq(85.0)
    expect(result[science.id]["average_score"]).to eq(85.0)
  end

  it "never aggregates another customer's bridge rows" do
    other = create(:customer)
    other_student = create(:entity, name: "Student", customer: other, display_label: "Student")
    other_klass = create(:entity, name: "Class", customer: other, display_label: "Class",
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
    other_bridge = Entity.find_by!(name: "assoc_student_class", customer_id: other.id)

    other_john = create(:entity_entry, entity: other_student, customer: other, data: {}.to_json)
    other_math = create(:entity_entry, entity: other_klass, customer: other, data: {}.to_json)
    enroll(other_john, other_math, score: 10, host: other, junction: other_bridge)

    other_student.property_schema_json = [{
      "name" => "Average Score",
      "name_slug" => "average_score",
      "type" => "Computed",
      "html_type" => "number",
      "readonly" => true,
      "storage" => "computed",
      "config" => {
        "bridge_entity_id" => other_bridge.id,
        "bridge_role" => "source",
        "source_slug" => "score",
        "function" => "avg",
        "precision" => 2
      }
    }]
    other_student.save!

    ours = load(student, john)
    theirs = Entities::DerivedValues.call(
      entity: other_student.reload, customer_id: other.id, entry_ids: [other_john.id]
    )

    expect(ours[john.id]["average_score"]).to eq(87.5)
    expect(theirs[other_john.id]["average_score"]).to eq(10.0)

    leaked = Entities::DerivedValues.call(
      entity: student.reload, customer_id: customer.id, entry_ids: [john.id, other_john.id]
    )
    expect(leaked[john.id]["average_score"]).to eq(87.5)
    expect(leaked[other_john.id]["average_score"]).to be_nil
  end

  it "still resolves after the host entity is renamed" do
    computed_field = student.computed_fields.find { |f| f["name_slug"] == "average_score" }

    student.update!(name: "Pupil")
    sql = Entities::ComputedCompiler.compile(computed_field, student.reload, customer_id: customer.id)
    expect(sql).to include("'$.pupil'")
    expect(Entities::DerivedValues.call(entity: student.reload, customer_id: customer.id, entry_ids: [john.id])[john.id]["average_score"]).to eq(87.5)
  end

  it "does not lose a colliding additional-attribute value when the host is renamed" do
    row = EntityEntry.where(entity_id: bridge.id, customer_id: customer.id).detect do |entry|
      entry.data_json["student"] == john.id.to_s && entry.data_json["score"] == "90"
    end
    expect(row).to be_present
    expect(row.data_json["score"]).to eq("90")

    student.update!(name: "Score")

    reloaded = row.reload.data_json
    expect(reloaded["score"]).to eq("90")
    expect(reloaded["student"]).to eq(john.id.to_s)
  end

  describe "computed filters against persisted rows" do
    before do
      EntityEntry.where(entity_id: bridge.id, customer_id: customer.id).find_each do |row|
        data = row.data_json
        next unless data["student"] == john.id.to_s

        data["status"] = "completed"
        row.update_columns(data: data.to_json)
      end
      enroll(john, math, score: 40, status: "pending")

      student.property_schema_json = [
        computed_field("average_score", "avg", host_role: "source"),
        computed_field("completed_avg", "avg", host_role: "source",
          filter: { "slug" => "status", "op" => "=", "value" => "completed" }),
        computed_field("above_fifty_avg", "avg", host_role: "source",
          filter: { "slug" => "score", "op" => ">", "value" => 50 }),
        computed_field("completed_count", "count", host_role: "source", source_slug: "",
          filter: { "slug" => "status", "op" => "=", "value" => "completed" }),
        computed_field("ghost_avg", "avg", host_role: "source",
          filter: { "slug" => "status", "op" => "=", "value" => "ghost" }),
        computed_field("ghost_count", "count", host_role: "source", source_slug: "",
          filter: { "slug" => "status", "op" => "=", "value" => "ghost" })
      ]
      student.save!
      student.reload
    end

    it "averages only completed rows when filtered by status text" do
      result = load(student, john)
      unfiltered = result[john.id]["average_score"]
      completed = result[john.id]["completed_avg"]

      expect(unfiltered).to eq(71.67)
      expect(completed).to eq(87.5)
      expect(completed).not_to eq(unfiltered)
      expect(completed).not_to be_nil
      expect(completed).not_to eq(0)
    end

    it "averages only rows with score > 50 using a numeric comparison" do
      result = load(student, john)
      unfiltered = result[john.id]["average_score"]
      above_fifty = result[john.id]["above_fifty_avg"]

      # Old quoted-text comparison (`> '50'`) matched zero SQLite rows.
      expect(unfiltered).to eq(71.67)
      expect(above_fifty).to eq(87.5)
      expect(above_fifty).not_to eq(unfiltered)
      expect(above_fifty).not_to be_nil
      expect(above_fifty).not_to eq(0)
    end

    it "counts only rows matching the filter" do
      result = load(student, john)
      expect(result[john.id]["completed_count"]).to eq(2)
    end

    it "yields the empty-set default when the filter matches nothing" do
      result = load(student, john)
      expect(result[john.id]["ghost_avg"]).to be_nil
      expect(result[john.id]["ghost_count"]).to eq(0)
    end
  end
end
