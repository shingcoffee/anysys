require "rails_helper"

RSpec.describe Payments::Refund, type: :model do
  let_it_be(:customer) { create(:customer) }
  let(:order) { create(:payment_order, external_ref: "o", amount: 5.00, subject: "s") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "t1", amount: 5.00, status: "succeeded")
  end

  let(:succeed_args) { { at: Time.zone.now, psp_refund_id: "P", notify: {} } }

  before { Current.customer = customer }

  # Pure keyword-splat helper — callers pass keywords, so no bare-hash pitfall.
  def create_refund(**attrs)
    described_class.create!({ payment: payment }.merge(attrs))
  end

  it "requires out_refund_no unique" do
    create_refund(out_refund_no: "r1", amount: 1.00)
    dup = described_class.new(payment: payment, out_refund_no: "r1", amount: 1.00)
    expect(dup).not_to be_valid
  end

  it "validates status inclusion" do
    r = described_class.new(payment: payment, out_refund_no: "r2", amount: 1.00, status: "bogus")
    expect(r).not_to be_valid
    expect(r.errors[:status]).to be_present
  end

  it "rounds amounts using the payment's zero-decimal currency" do
    jpy_order = create(:payment_order,
      external_ref: "jpy-order", amount: 1000, subject: "s", currency: "JPY"
    )
    jpy_payment = create(:payment,
      payment_order: jpy_order, provider: "stripe", flow: "card",
      out_trade_no: "jpy-payment", amount: 1000, status: "succeeded"
    )
    refund = described_class.new(
      payment: jpy_payment, out_refund_no: "jpy-refund", amount: "500.50"
    )

    expect(refund).to be_valid
    expect(refund.amount).to eq(501.00)
  end

  it "marks order partial_refund when less than full amount refunded" do
    r = create_refund(out_refund_no: "r3", amount: 2.00)
    r.mark_succeeded!(**succeed_args)
    expect(order.reload.status).to eq("partial_refund")
  end

  it "marks order refunded when full amount refunded" do
    r = create_refund(out_refund_no: "r4", amount: 5.00)
    r.mark_succeeded!(**succeed_args)
    expect(order.reload.status).to eq("refunded")
  end

  it "mark_succeeded! is idempotent" do
    r = create_refund(out_refund_no: "r5", amount: 1.00)
    r.mark_succeeded!(**succeed_args)
    expect { r.mark_succeeded!(**succeed_args) }.not_to raise_error
  end

  describe "concurrency locking" do
    it "acquires with_lock on self and on the order during mark_succeeded!" do
      r = create_refund(out_refund_no: "r6", amount: 2.50)
      expect(r).to receive(:with_lock).and_call_original
      expect_any_instance_of(Payments::Order).to receive(:with_lock).and_call_original
      r.mark_succeeded!(**succeed_args)
      expect(r.reload.status).to eq("succeeded")
      expect(order.reload.status).to eq("partial_refund")
    end
  end

  describe "idempotent transitions" do
    it "mark_processing! returns self when already processing" do
      r = create_refund(out_refund_no: "r7", amount: 1.00, status: "processing")
      result = r.mark_processing!
      expect(result).to eq(r)
      expect(r.reload.status).to eq("processing")
    end

    it "mark_processing! transitions from requested to processing" do
      r = create_refund(out_refund_no: "r8", amount: 1.00)
      r.mark_processing!
      expect(r.reload.status).to eq("processing")
    end

    it "mark_failed! is idempotent when already failed" do
      r = create_refund(out_refund_no: "r9", amount: 1.00)
      r.mark_failed!(notify: {})
      expect { r.mark_failed!(notify: {}) }.not_to raise_error
      expect(r.reload.status).to eq("failed")
    end

    it "mark_failed! transitions from requested to failed" do
      r = create_refund(out_refund_no: "r10", amount: 1.00)
      r.mark_failed!(notify: { "reason" => "declined" })
      expect(r.reload.status).to eq("failed")
    end
  end

  describe "terminal-state guard (M1)" do
    it "preserves a webhook success when a stale synchronous response marks processing" do
      stale = create_refund(out_refund_no: "stale-processing", amount: 5.00)
      settled = described_class.find(stale.id)
      settled.mark_succeeded!(**succeed_args.merge(notify: { "settled" => true }))

      stale.mark_processing!(psp_refund_id: "late", notify: { "pending" => true })

      expect(stale.reload.status).to eq("succeeded")
      expect(stale.psp_refund_id).to eq("P")
      expect(stale.raw_notify).to eq("settled" => true)
      expect(order.reload.status).to eq("refunded")
    end

    it "mark_failed! leaves a succeeded refund untouched" do
      r = create_refund(out_refund_no: "r11", amount: 1.00)
      r.mark_succeeded!(**succeed_args)
      r.mark_failed!(notify: {})
      expect(r.reload.status).to eq("succeeded")
    end

    it "mark_processing! leaves a succeeded refund untouched" do
      r = create_refund(out_refund_no: "r12", amount: 1.00)
      r.mark_succeeded!(**succeed_args)
      r.mark_processing!
      expect(r.reload.status).to eq("succeeded")
    end

    it "mark_processing! leaves a failed refund untouched" do
      r = create_refund(out_refund_no: "r13", amount: 1.00)
      r.mark_failed!(notify: {})
      r.mark_processing!
      expect(r.reload.status).to eq("failed")
    end
  end
end
