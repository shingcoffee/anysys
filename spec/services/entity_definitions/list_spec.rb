# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::List do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  def call_for(tenant)
    Current.with_customer(tenant) do
      signal, (ctx, *) = described_class.call({})
      [signal, ctx]
    end
  end

  it "returns catalog fields plus the resolved definition body, ordered by name" do
    later = create(:entity, customer: customer, name: "Zeta", display_label: "Zeta Label",
                            description: "Zeta desc", icon: "user", color: "#111111")
    create(:entity, :with_name_status_schema, customer: customer, name: "Alpha")

    signal, ctx = call_for(customer)
    expect(signal.to_h[:semantic]).to eq(:success)

    names = ctx[:json][:entities].map { |item| item[:name] }
    expect(names).to eq(%w[Alpha Zeta])

    zeta = ctx[:json][:entities].last
    expect(zeta[:id]).to eq(later.id)
    expect(zeta[:display_label]).to eq("Zeta Label")
    expect(zeta).not_to have_key(:name_slug)
    expect(zeta[:shared]).to be(false)
    expect(zeta[:category]).to eq("plain")
    expect(zeta[:status]).to eq("active")
    expect(zeta[:extended_model]).to be_nil
    expect(zeta[:icon]).to eq("user")
    expect(zeta[:color]).to eq("#111111")
    expect(zeta[:description]).to eq("Zeta desc")
    expect(zeta[:property_schema]).to eq([])
    expect(zeta[:attribute_groups]).to eq([])
    expect(zeta[:associations]).to eq([])
    expect(zeta[:default_properties]).to eq({})
    expect(zeta[:referenced_template]).to be_nil
    expect(zeta[:current_version][:id]).to eq(later.resolved_current_version.id)
    expect(zeta[:current_version][:version_number]).to eq(later.resolved_current_version.version_number)
  end

  it "includes shared definitions resolved for the current tenant" do
    shared = Current.with_customer(nil) do
      create(:entity, :shared, name: "GlobalWidget", description: "global v1")
    end
    Current.with_customer(customer) do
      entity = Entity.find(shared.id)
      entity.description = "tenant override"
      entity.save!
    end

    _, ctx = call_for(customer)
    item = ctx[:json][:entities].find { |row| row[:id] == shared.id }
    expect(item[:shared]).to be(true)
    expect(item[:description]).to eq("tenant override")

    _, other_ctx = call_for(other)
    other_item = other_ctx[:json][:entities].find { |row| row[:id] == shared.id }
    expect(other_item[:description]).to eq("global v1")
  end

  it "omits inactive definitions and other tenants' customer-specific rows" do
    create(:entity, customer: customer, name: "Visible")
    hidden = create(:entity, customer: customer, name: "Hidden")
    hidden.inactive!
    create(:entity, customer: other, name: "Foreign")

    _, ctx = call_for(customer)
    names = ctx[:json][:entities].map { |item| item[:name] }
    expect(names).to include("Visible")
    expect(names).not_to include("Hidden", "Foreign")
  end

  it "returns an empty list when the tenant has no definitions" do
    signal, ctx = call_for(customer)
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:json]).to eq(entities: [])
  end
end
