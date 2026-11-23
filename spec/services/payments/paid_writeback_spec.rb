# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::PaidWriteback do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "select",
        "config" => { "options" => %w[Open Paid] } },
      { "name" => "Paid on", "name_slug" => "paid_on", "type" => "String", "html_type" => "date" },
      { "name" => "Paid at", "name_slug" => "paid_at", "type" => "String", "html_type" => "datetime-local" },
      { "name" => "Payment reference", "name_slug" => "payment_reference", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:entry) { create(:entity_entry, entity: entity, customer: customer, data: { "status" => "Open" }.to_json) }
  let(:paid_at) { Time.zone.parse("2026-11-19 09:30:00") }

  def payment_for(plan, cust: customer)
    order = create(:payment_order, customer: cust, on_success: plan)
    create(:payment, customer: cust, payment_order: order, out_trade_no: "otn-#{order.id}", paid_at: paid_at)
  end

  def plan(**extra)
    { "entity_id" => entity.id, "entry_id" => entry.id, "fields" => { "status" => "Paid" } }.merge(extra.stringify_keys)
  end

  it "sets the fields, the payment time and the reference on the paid record" do
    payment = payment_for(plan(paid_at_field: "paid_on", reference_field: "payment_reference"))

    expect(described_class.call(payment: payment)).to be(true)
    expect(entry.reload.data_json).to include(
      "status" => "Paid", "paid_on" => "2026-11-19", "payment_reference" => payment.out_trade_no
    )
  end

  it "writes the payment time the way a date-and-time field stores it" do
    payment = payment_for(plan(paid_at_field: "paid_at"))
    described_class.call(payment: payment)
    expect(entry.reload.data_json["paid_at"]).to eq("2026-11-19T09:30")
  end

  it "does nothing for an order with no record changes" do
    payment = payment_for({})
    expect(described_class.call(payment: payment)).to be(false)
    expect(entry.reload.data_json["status"]).to eq("Open")
  end

  it "never writes another tenant's record" do
    payment = payment_for(plan, cust: other)
    expect(Rails.logger).to receive(:warn).with(/\[payments.paid_writeback\].*not found/)

    expect(described_class.call(payment: payment)).to be(false)
    expect(entry.reload.data_json["status"]).to eq("Open")
  end

  it "logs and leaves the record unchanged when a field cannot be set" do
    payment = payment_for(plan(reference_field: "missing"))
    expect(Rails.logger).to receive(:warn).with(/\[payments.paid_writeback\]/)

    expect(described_class.call(payment: payment)).to be(false)
    expect(entry.reload.data_json["status"]).to eq("Open")
  end

  context "when the status field has a lifecycle" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "select",
          "config" => { "source" => "manual", "options" => [
            { "label" => "Open", "value" => "Open", "default" => true }, { "label" => "Paid", "value" => "Paid" }
          ] },
          "lifecycle" => { "transitions" => [{ "from" => "Open", "to" => "Paid", "by" => by }] } }
      ].to_json)
    end

    context "and lets system mark it paid" do
      let(:by) { %w[system] }

      it "writes the status as the system" do
        expect(described_class.call(payment: payment_for(plan))).to be(true)
        expect(entry.reload.data_json["status"]).to eq("Paid")
      end
    end

    context "and leaves that change to admins" do
      let(:by) { %w[admin] }

      it "is refused and leaves the record unchanged" do
        expect(Rails.logger).to receive(:warn).with(/\[payments.paid_writeback\]/)

        expect(described_class.call(payment: payment_for(plan))).to be(false)
        expect(entry.reload.data_json["status"]).to eq("Open")
      end
    end
  end

  it "keeps the settled payment when the record write fails" do
    order = create(:payment_order, customer: customer, on_success: plan(reference_field: "missing"))
    payment = create(:payment, customer: customer, payment_order: order, status: "created")
    allow(Rails.logger).to receive(:warn)

    payment.mark_succeeded!(psp_id: "X", at: paid_at, notify: {})

    expect(payment.reload.status).to eq("succeeded")
    expect(order.reload.status).to eq("paid")
    expect(entry.reload.data_json["status"]).to eq("Open")
  end
end
