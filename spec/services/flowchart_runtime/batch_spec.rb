# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Batch do
  it "fails through Step.fail when the named entity is not reachable" do
    customer = create(:customer)
    entity = create(:entity, customer: customer)
    ctx = { bound_entity: entity, customer_id: customer.id, errors: [], error_details: [] }

    expect(
      described_class.run(ctx, source: EntityEntry.all, operation: "destroy_all", batch_size: 10, entity: "Missing")
    ).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.batch_operation.entity_not_accessible"))
  end

  it "raises Error when the source cannot be ANDed with the tenant scope" do
    customer = create(:customer)
    entity = create(:entity, customer: customer)
    ctx = { bound_entity: entity, customer_id: customer.id }

    expect {
      described_class.run(ctx, source: EntityEntry.all.limit(1), operation: "destroy_all", batch_size: 10)
    }.to raise_error(FlowchartRuntime::Batch::Error, "incompatible_scope")
  end

  it "stops after max_records" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [{ "name_slug" => "email", "type" => "String" }].to_json)
    2.times { create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: {}) }
    ctx = { bound_entity: entity, customer_id: customer.id }

    expect(
      described_class.run(ctx, source: EntityEntry.all, operation: "destroy_all", batch_size: 10, max_records: 1)
    ).to eq(1)
    expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count).to eq(1)
  end

  describe "failed writes" do
    let(:customer) { create(:customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [{ "name" => "Email", "name_slug" => "email", "data_type" => "string" }].to_json)
    end
    let(:ctx) { { bound_entity: entity, customer_id: customer.id, errors: [] } }

    before do
      3.times { create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: {}) }
      allow(FlowchartRuntime::Entries).to receive(:save) do |run_ctx, _record|
        FlowchartRuntime::Step.fail(run_ctx, :record_invalid, errors: "email is invalid")
      end
    end

    def update_all(**opts)
      described_class.run(ctx, source: FlowchartRuntime::Entries.scope(ctx), operation: "update_all", batch_size: 10,
                               assignments: { "email" => "x" }, **opts)
    end

    it "fails the batch on the first failed save when errors are not collected" do
      expect(update_all).to be(false)
      expect(FlowchartRuntime::Entries).to have_received(:save).once
      expect(ctx[:error_details].last["code"]).to eq("record_invalid")
    end

    it "collects failed saves without failing the step and honours stop_on_error" do
      expect(update_all(collect_errors: true)).to eq(0)
      expect(ctx[:_batch_errors].size).to eq(3)
      expect(ctx[:_batch_errors].first[:class]).to eq("record_invalid")
      expect(ctx[:errors]).to be_empty

      ctx[:_batch_errors] = nil
      update_all(collect_errors: true, stop_on_error: true)
      expect(ctx[:_batch_errors].size).to eq(1)
    end

    it "caps each_batch slices at max_records" do
      sizes = []
      described_class.run(ctx, source: EntityEntry.all, operation: "each_batch", batch_size: 2, max_records: 3) do |rel|
        sizes << rel.to_a.size
      end
      expect(sizes).to eq([2, 1])
    end
  end
end
