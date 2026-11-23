# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::DesignEntity do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:flowchart) { create(:flowchart, customer: customer) }
  let(:student) { create(:entity, customer: customer, name: "Student") }
  let(:course) { create(:entity, customer: customer, name: "Course") }

  it "returns nil when the flowchart is not persisted" do
    expect(described_class.for(Flowchart.new, customer_id: customer.id)).to be_nil
  end

  it "returns nil when no page is bound" do
    expect(described_class.for(flowchart, customer_id: customer.id)).to be_nil
  end

  it "returns the one entity every visible page shares" do
    create(:page, customer: customer, entity: student, flowchart: flowchart)
    create(:page, customer: customer, entity: student, flowchart: flowchart)

    expect(described_class.for(flowchart, customer_id: customer.id)).to eq(student)
  end

  it "returns nil when bound pages submit different entities" do
    create(:page, customer: customer, entity: student, flowchart: flowchart)
    create(:page, customer: customer, entity: course, flowchart: flowchart)

    expect(described_class.for(flowchart, customer_id: customer.id)).to be_nil
  end

  it "ignores another tenant's pages when resolving for this customer" do
    shared = create(:flowchart, :shared_type)
    create(:page, customer: customer, entity: student, flowchart: shared)
    other_entity = create(:entity, customer: other)
    create(:page, customer: other, entity: other_entity, flowchart: shared)

    expect(described_class.for(shared, customer_id: customer.id)).to eq(student)
    expect(described_class.for(shared, customer_id: other.id)).to eq(other_entity)
  end

  it "counts only shared pages when customer_id is nil" do
    shared_entity = create(:entity, :shared, name: "Shared Student")
    shared_flowchart = create(:flowchart, :shared_type)
    create(:page, :shared, entity: shared_entity, flowchart: shared_flowchart)
    create(:page, customer: customer, entity: student, flowchart: shared_flowchart)

    expect(described_class.for(shared_flowchart, customer_id: nil)).to eq(shared_entity)
    expect(described_class.for(shared_flowchart, customer_id: customer.id)).to be_nil
  end
end
