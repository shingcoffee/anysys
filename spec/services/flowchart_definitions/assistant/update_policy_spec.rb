# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Assistant::UpdatePolicy do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:entity) { create(:entity, customer: customer) }

  def decide(name, confirmed: false, tenant: customer)
    described_class.call(flowchart: { "name" => name }, customer: tenant, confirmed: confirmed)
  end

  it "allows a create when the name is new in this tenant" do
    result = decide("Create Student")
    expect(result).to be_permitted
    expect(result.existing_names).to eq([])
  end

  it "blocks an unconfirmed update of a live customer-owned flowchart" do
    create(:flowchart, customer: customer, name: "Create Student")
    result = decide("Create Student")
    expect(result).not_to be_permitted
    expect(result.existing_names).to eq(["Create Student"])
  end

  it "allows a confirmed update" do
    create(:flowchart, customer: customer, name: "Create Student")
    result = decide("Create Student", confirmed: true)
    expect(result).to be_permitted
  end

  it "allows rewriting only the flowchart the caller approved" do
    create(:flowchart, customer: customer, name: "Create Student")
    create(:flowchart, customer: customer, name: "Notify Registrar")

    approved = described_class.call(flowchart: { "name" => "Create Student" }, customer: customer, replaceable: "Create Student")
    other = described_class.call(flowchart: { "name" => "Notify Registrar" }, customer: customer, replaceable: "Create Student")

    expect([approved.permitted?, other.permitted?]).to eq([true, false])
  end

  it "does not treat another tenant's same name as an update" do
    other_entity = create(:entity, customer: other)
    create(:flowchart, customer: other, name: "Create Student")
    result = decide("Create Student")
    expect(result).to be_permitted
    expect(result.existing_names).to eq([])
  end
end
