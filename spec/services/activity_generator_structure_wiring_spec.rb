# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "structure validator collision wiring" do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  def graph_for(target_id)
    {
      "elements" => [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        {
          "id" => "sf",
          "type" => "subflow",
          "label" => "Child flow",
          "properties" => { "flowchartId" => target_id }
        },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
      ],
      "connections" => [
        { "id" => "c1", "from" => "s", "to" => "sf" },
        { "id" => "c2", "from" => "sf", "to" => "e" }
      ],
      "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
    }.to_json
  end

  def collision_message
    I18n.t("maint_core.flowcharts.structure_errors.class_name_collision", name: "EnrolStudentActivity")
  end

  it "reports class_name_collision when a same-customer subflow derives the same class name" do
    child = create(:flowchart, customer: customer, name: "Enrol Student")
    parent = build(
      :flowchart,
      customer: customer,
      name: "enrol student",
      configuration: graph_for(child.id)
    )
    generator = described_class.new(parent)

    expect(generator.structure_errors).to include(collision_message)
    expect(generator.generate).to be_nil
  end

  it "does not report class_name_collision for another customer's flowchart" do
    foreign = create(:customer)
    foreign_child = create(
      :flowchart,
      customer: foreign,
      name: "Enrol Student"
    )
    parent = build(
      :flowchart,
      customer: customer,
      name: "enrol student",
      configuration: graph_for(foreign_child.id)
    )
    generator = described_class.new(parent)

    expect(generator.structure_errors).not_to include(collision_message)
  end

  def two_child_graph(first_id, second_id)
    {
      "elements" => [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        {
          "id" => "sf1",
          "type" => "subflow",
          "label" => "First",
          "properties" => { "flowchartId" => first_id }
        },
        {
          "id" => "sf2",
          "type" => "subflow",
          "label" => "Second",
          "properties" => { "flowchartId" => second_id }
        },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
      ],
      "connections" => [
        { "id" => "c1", "from" => "s", "to" => "sf1" },
        { "id" => "c2", "from" => "sf1", "to" => "sf2" },
        { "id" => "c3", "from" => "sf2", "to" => "e" }
      ],
      "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
    }.to_json
  end

  it "reports class_name_collision when sibling children Helper and helper share a class name" do
    child_a = create(:flowchart, customer: customer, name: "Helper")
    child_b = create(:flowchart, customer: customer, name: "helper")
    parent = build(
      :flowchart,
      customer: customer,
      name: "Parent Flow",
      configuration: two_child_graph(child_a.id, child_b.id)
    )
    generator = described_class.new(parent)
    message = I18n.t("maint_core.flowcharts.structure_errors.class_name_collision", name: "HelperActivity")

    expect(generator.structure_errors).to include(message)
    expect(generator.generate).to be_nil
  end

  it "does not report class_name_collision for two references to the same child" do
    child = create(:flowchart, customer: customer, name: "Helper")
    parent = build(
      :flowchart,
      customer: customer,
      name: "Parent Flow",
      configuration: two_child_graph(child.id, child.id)
    )
    generator = described_class.new(parent)

    expect(generator.structure_errors.grep(/collides with a sub-flow/)).to be_empty
    expect(generator.generate).to be_present
  end
end
