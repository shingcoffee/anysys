# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Audit do
  let(:customer) { create(:customer) }
  let(:ctx) { { customer_id: customer.id, flowchart_id: 42 } }

  it "writes a JSON line and returns true" do
    allow(Rails.logger).to receive(:info)
    expect(described_class.write({ customer_id: 49 }, event_type: "login", actor_id: "user-1")).to be(true)
    expect(Rails.logger).to have_received(:info).with(a_string_including("[AUDIT]", "login", "user-1"))
  end

  it "maps critical to the error logger method" do
    allow(Rails.logger).to receive(:error)
    described_class.write({}, event_type: "denied", severity: "critical")
    expect(Rails.logger).to have_received(:error).with(a_string_including("[AUDIT]", "critical"))
  end

  it "inserts a tenant-scoped audit event including flowchart_id from ctx" do
    allow(Rails.logger).to receive(:info)
    described_class.write(
      ctx,
      event_type: "record_updated",
      resource_type: "Order",
      resource_id: 7,
      actor_id: 11,
      ip_address: "1.1.1.1",
      user_agent: "rspec",
      metadata: { "sku" => "ABC" },
      severity: "info"
    )
    row = FlowchartAuditEvent.find_by!(customer_id: customer.id, event_type: "record_updated")
    expect(row.flowchart_id).to eq(42)
    expect(row.resource_type).to eq("Order")
    expect(row.resource_id).to eq("7")
    expect(row.actor_user_id).to eq(11)
    expect(row.ip).to eq("1.1.1.1")
    expect(row.user_agent).to eq("rspec")
    expect(row.severity).to eq("info")
    expect(row.metadata).to eq("sku" => "ABC", "outcome" => "success")
  end

  it "leaves no row when the surrounding transaction rolls back" do
    allow(Rails.logger).to receive(:info)
    FlowchartAuditEvent.transaction do
      described_class.write(ctx, event_type: "login")
      raise ActiveRecord::Rollback
    end
    expect(FlowchartAuditEvent.where(customer_id: customer.id)).to be_empty
  end

  it "skips persistence when customer_id is absent" do
    allow(Rails.logger).to receive(:info)
    expect { described_class.write({}, event_type: "login") }.not_to change(FlowchartAuditEvent, :count)
  end

  it "defaults actor, resource, IP, and user-agent from ctx" do
    allow(Rails.logger).to receive(:info)
    model = OpenStruct.new(id: 88)
    described_class.write(
      ctx.merge(current_user_id: 11, model: model, request_ip: "2.2.2.2", user_agent: "rspec"),
      event_type: "viewed"
    )
    row = FlowchartAuditEvent.find_by!(customer_id: customer.id, event_type: "viewed")
    expect(row.actor_user_id).to eq(11)
    expect(row.resource_id).to eq("88")
    expect(row.resource_type).to eq("OpenStruct")
    expect(row.ip).to eq("2.2.2.2")
    expect(row.user_agent).to eq("rspec")
  end
end
