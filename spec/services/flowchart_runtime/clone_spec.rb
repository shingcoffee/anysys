# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowchartRuntime::Clone" do
  subject(:facade) { "FlowchartRuntime::Clone".constantize }

  it "uses Rails deep duplication when deep cloning" do
    source = { "items" => [{ "name" => "first" }] }

    clone = facade.copy(source, deep: true)
    clone["items"].first["name"] = "changed"

    expect(source.dig("items", 0, "name")).to eq("first")
  end

  it "rejects a missing source before calling Rails duplication" do
    expect { facade.copy(nil, deep: true) }.to raise_error do |error|
      expect(error.class.name).to eq("FlowchartRuntime::Clone::Error")
      expect(error.message).to eq("source is required")
    end
  end

  it "clears excluded hash keys on the copy" do
    source = { "email" => "a@x.io", "status" => "open" }

    clone = facade.copy(source, exclude: ["email"])

    expect(clone).to eq("status" => "open")
    expect(source).to eq("email" => "a@x.io", "status" => "open")
  end

  it "keeps the source's stored files on the copy unless a file field is excluded" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Contract", "name_slug" => "contract", "html_type" => "file" },
      { "name" => "Scans", "name_slug" => "scans", "html_type" => "file", "config" => { "multiple" => true } }
    ].to_json)
    model = EntityEntry.build_for(entity)
    source = model.create!(customer_id: customer.id, contract: { io: StringIO.new("a"), filename: "a.pdf" },
                           scans: [{ io: StringIO.new("b"), filename: "b.pdf" }])
    source = model.find(source.id)

    copy = facade.copy(source, exclude: ["scans"]).tap(&:save!)

    copy = model.find(copy.id)
    expect(copy.contract.blob).to eq(source.contract.blob)
    expect(copy.scans).not_to be_attached
    expect(model.find(source.id).contract).to be_attached

    perform_enqueued_jobs { copy.destroy! }
    expect(model.find(source.id).contract.download).to eq("a")
  end
end
