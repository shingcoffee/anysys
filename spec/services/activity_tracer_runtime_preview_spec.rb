# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityTracer, "runtime owner preview" do
  let_it_be(:customer) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:entity) { create(:entity, customer: customer) }
  let(:child) do
    create(:flowchart, :launched_status, customer: customer, configuration: {
      "elements" => [
        { "id" => "start", "type" => "start", "properties" => {} },
        { "id" => "assign", "type" => "process", "label" => "Assign", "properties" => { "steps" => [
          { "action" => "assign_value", "config" => { "resultVar" => "preview_marker", "valueType" => "string", "stringValue" => "eligible-child" } }
        ] } },
        { "id" => "end", "type" => "end", "properties" => {} }
      ], "connections" => [{ "from" => "start", "to" => "assign" }, { "from" => "assign", "to" => "end" }], "metadata" => {}
    }.to_json)
  end

  def parent_configuration(child_id)
    {
      "elements" => [
        { "id" => "start", "type" => "start", "properties" => {} },
        { "id" => "child", "type" => "subflow", "properties" => { "flowchartId" => child_id } },
        { "id" => "end", "type" => "end", "properties" => {} }
      ], "connections" => [{ "from" => "start", "to" => "child" }, { "from" => "child", "to" => "end" }], "metadata" => {}
    }
  end

  let(:parent) { create(:flowchart, :draft, customer: customer, configuration: parent_configuration(child.id).to_json) }

  def preview(record = parent)
    Current.set(customer: customer, user: owner) { described_class.new(record).call(customer_id: customer.id) }
  end

  it "executes an unpublished parent with an accessible launched child" do
    result = preview
    expect(parent).to be_draft
    expect(result).to be_success
    expect(result.ctx[:preview_marker]).to eq("eligible-child")
    ids = result.trace_nodes.map { |n| n[:id] }
    expect(ids.count { |id| id == "Start.default" }).to eq(1)
    expect(ids.count { |id| id.to_s.start_with?("End.") }).to eq(1)
    expect(ids).not_to include("collect_errors", "assign")
  end

  it "retains the prepared unpublished parent definition without writing its artifact" do
    record = create(:flowchart, :simple, :draft, customer: customer)
    artifact = record.activity
    record.configuration_json = parent_configuration(child.id)
    record.activity = ActivityGenerator.new(record).generate
    result = preview(record)
    expect(result).to be_success
    expect(result.ctx[:preview_marker]).to eq("eligible-child")
    expect(record.reload.activity).to eq(artifact)
  end

  it "rejects a child taken offline even when the actor is the owner" do
    parent
    child.update!(status: :draft)
    result = preview
    expect(result).not_to be_success
    expect(result.error).to include("Failed to build activity class")
  end

  it "rejects a foreign-tenant child even when the actor is the owner" do
    parent
    foreign = create(:customer)
    child.update_columns(customer_id: foreign.id)
    result = preview
    expect(result).not_to be_success
    expect(result.error).to include("Failed to build activity class")
  end
end
