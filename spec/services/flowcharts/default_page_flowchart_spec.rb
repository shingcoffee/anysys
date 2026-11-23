# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::DefaultPageFlowchart do
  def stored = Flowchart.unscoped.find_by(uuid: described_class::UUID)

  it "creates the shared, launched page-record flowchart on first use and reuses it" do
    stored&.update_column(:uuid, SecureRandom.uuid)

    flowchart = described_class.fetch

    expect(flowchart).to be_shared
    expect(flowchart).to be_launched
    expect(flowchart.elements.flat_map { |element| Array(element.dig("properties", "steps")).pluck("action") })
      .to eq(%w[build_contract validate_contract save_model])
    expect(described_class.fetch).to eq(flowchart)
    expect(Flowchart.unscoped.where(uuid: described_class::UUID).count).to eq(1)
  end

  it "commits its definition to the global line when a tenant's page creates it" do
    stored&.update_column(:uuid, SecureRandom.uuid)
    tenant = create(:customer)

    flowchart = Current.set(customer: tenant) { create(:page, customer: tenant).flowchart }

    expect(flowchart.customer_id).to be_nil
    expect(flowchart.current_version).to have_attributes(customer_id: nil)
    expect(flowchart.flowchart_customer_heads).to be_empty
    expect(Current.set(customer: create(:customer)) { flowchart.reload.resolved_current_version })
      .to eq(flowchart.current_version)

    tenant.destroy!
    expect(flowchart.reload.current_version).to be_present
  end

  it "is created even when a tenant has its own flowchart by the same name" do
    stored&.update_column(:uuid, SecureRandom.uuid)
    tenant = create(:customer)
    Flowcharts::CustomerCopy.fetch(tenant, described_class).update_columns(status: Flowchart.statuses[:deleted])

    expect(described_class.fetch).to be_shared
    expect(Current.set(customer: tenant) { create(:page, customer: tenant).flowchart }).to eq(described_class.fetch)
  end

  it "stays deleted once the platform owner deletes it" do
    described_class.fetch.update_columns(status: Flowchart.statuses[:deleted])

    expect(described_class.fetch).to be_nil
    expect(stored).to be_deleted
  end

  it "leaves new pages unbound while the default is deleted" do
    described_class.fetch.update_columns(status: Flowchart.statuses[:deleted])

    expect(create(:page).flowchart).to be_nil
  end

  it "recognises only the shared default" do
    expect(described_class.default?(described_class.fetch)).to be(true)
    expect(described_class.default?(create(:flowchart, :simple))).to be(false)
    expect(described_class.default?(nil)).to be(false)
  end
end
