# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::BindingCounts do
  let(:customer) { create(:customer) }
  let!(:alpha) { create(:entity, customer: customer, name: "Alpha") }
  let!(:beta) { create(:entity, customer: customer, name: "Beta") }
  let!(:empty) { create(:entity, customer: customer, name: "Empty") }

  def counts = described_class.call(customer_id: customer.id)

  def unbind(page, entity_id)
    page.entity_id = entity_id
    page.save!(validate: false)
    page
  end

  it "counts every and live form per bound entity" do
    create(:page, customer: customer, entity: alpha, launched: true)
    create(:page, customer: customer, entity: alpha)
    create(:page, customer: customer, entity: beta, launched: true)

    result = counts
    expect(result[alpha.id]).to eq(described_class::Count.new(total: 2, live: 1))
    expect(result[beta.id]).to eq(described_class::Count.new(total: 1, live: 1))
    expect(result[empty.id]).to eq(described_class::Count.empty)
  end

  it "folds forms with no entity, a bridge entity or a missing entity under nil" do
    bridge = create(:entity, customer: customer, category: :bridge)
    create(:page, customer: customer, entity: bridge, launched: true)
    unbind(create(:page, customer: customer, entity: alpha), nil)
    unbind(create(:page, customer: customer, entity: alpha), 99_999_999)

    result = counts
    expect(result[nil]).to eq(described_class::Count.new(total: 3, live: 1))
    expect(result[bridge.id]).to eq(described_class::Count.empty)
    expect(result[alpha.id]).to eq(described_class::Count.empty)
  end

  it "includes shared forms but never another tenant's" do
    shared = create(:entity, :shared)
    create(:page, :shared, entity: shared)
    other = create(:customer)
    create(:page, customer: other, entity: create(:entity, customer: other))

    result = counts
    expect(result[shared.id].total).to eq(1)
    expect(result.values.sum(&:total)).to eq(1)
  end
end
