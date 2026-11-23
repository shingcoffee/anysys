# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::EntitiesSource do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:user)           { create(:user, customer: customer, role: :admin) }

  def build(query)
    described_class.new(customer: customer, query: query, user: user).to_group
  end

  it "returns entities for the customer matching the query" do
    entity = create(:entity, customer: customer, name: "Invoice")
    create(:entity, customer: customer, name: "Product")
    group = build("inv")
    expect(group[:key]).to eq(:entities)
    expect(group[:label]).to eq("Entities")
    expect(group[:items].map { |i| i[:label] }).to eq(["Invoice"])
    expect(group[:items].first[:path]).to eq("/#{customer.id}/admin/entities/#{entity.id}")
    expect(group[:items].first[:type]).to eq(:entity)
  end

  it "excludes other customers' entities" do
    create(:entity, customer: other_customer, name: "Invoice")
    expect(build("Invoice")[:items]).to be_empty
  end

  it "caps results at 5" do
    7.times { |i| create(:entity, customer: customer, name: "Row #{i}") }
    expect(build("Row")[:items].size).to eq(5)
  end
end
