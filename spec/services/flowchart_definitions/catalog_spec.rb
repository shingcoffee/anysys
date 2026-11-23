# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Catalog do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  it "lists live customer-owned flowcharts for this tenant only" do
    create(:flowchart, customer: customer, name: "Create Student")
    create(:flowchart, customer: other, name: "Create Student")

    docs = described_class.for_customer(customer.id)
    expect(docs.map { |row| row["name"] }).to eq(["Create Student"])
    expect(docs.first).to include(
      "name" => "Create Student",
      "status" => "draft"
    )
    expect(docs.first.keys).not_to include("entity_name", "crud_type")
  end
end
