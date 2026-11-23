# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Dispute do
  let_it_be(:customer) { create(:customer) }
  let(:order) { create(:payment_order, external_ref: "d-ord", amount: 5.00, subject: "s") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "stripe", flow: "card",
           out_trade_no: "d-ot-1", amount: 5.00, status: "succeeded")
  end

  before { Current.customer = customer }

  it "enforces one row per (provider, psp_dispute_id)" do
    described_class.create!(payment: payment, provider: "stripe", psp_dispute_id: "dp_1",
                              status: "open", amount: 5.00)
    dup = described_class.new(payment: payment, provider: "stripe", psp_dispute_id: "dp_1",
                                status: "open", amount: 5.00)
    expect(dup).not_to be_valid
    expect(dup.errors[:psp_dispute_id]).to be_present
  end

  it "allows the same psp_dispute_id across different providers" do
    described_class.create!(payment: payment, provider: "stripe", psp_dispute_id: "dp_shared",
                              status: "open", amount: 5.00)
    other_payment = create(:payment, payment_order: order, provider: "paypal", flow: "card",
                           out_trade_no: "d-ot-2", amount: 5.00, status: "succeeded")
    cross = described_class.new(payment: other_payment, provider: "paypal", psp_dispute_id: "dp_shared",
                                  status: "open", amount: 5.00)
    expect(cross).to be_valid
    expect { cross.save! }.not_to raise_error
  end

  it "resolved? is true only for terminal statuses" do
    d = described_class.new(status: "under_review")
    expect(d.resolved?).to be(false)
    d.status = "lost"
    expect(d.resolved?).to be(true)
  end

  it "rounds amounts using the payment's zero-decimal currency" do
    jpy_order = create(:payment_order,
      external_ref: "jpy-order", amount: 1000, subject: "s", currency: "JPY"
    )
    jpy_payment = create(:payment,
      payment_order: jpy_order, provider: "stripe", flow: "card",
      out_trade_no: "jpy-payment", amount: 1000, status: "succeeded"
    )
    dispute = described_class.new(
      payment: jpy_payment, provider: "stripe", psp_dispute_id: "jpy-dispute",
      status: "open", amount: "500.50"
    )

    expect(dispute).to be_valid
    expect(dispute.amount).to eq(501.00)
  end

  it "open/resolved scopes partition by status" do
    open = described_class.create!(payment: payment, provider: "stripe",
                                     psp_dispute_id: "dp_open", status: "under_review", amount: 5.00)
    lost = described_class.create!(payment: payment, provider: "stripe",
                                     psp_dispute_id: "dp_lost", status: "lost", amount: 5.00)
    expect(described_class.open).to include(open)
    expect(described_class.open).not_to include(lost)
    expect(described_class.resolved).to include(lost)
  end
end
