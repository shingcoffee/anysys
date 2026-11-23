require "rails_helper"

RSpec.describe Payments::Payment, type: :model do
  let_it_be(:customer) { create(:customer) }
  let(:order) { create(:payment_order, external_ref: "o", amount: 1.00, subject: "s") }

  before { Current.customer = customer }

  # Pure keyword-splat helper — callers pass keywords, so no bare-hash pitfall.
  def create_payment(**attrs)
    described_class.create!(
      { payment_order: order, provider: "alipay", flow: "qr", amount: 1.00 }.merge(attrs)
    )
  end

  it "requires provider, flow, out_trade_no, amount" do
    p = described_class.new(payment_order: order)
    expect(p).not_to be_valid
  end

  it "validates provider and flow inclusion" do
    p = described_class.new(payment_order: order, provider: "visa", flow: "pos",
                            out_trade_no: "t1", amount: 1.00)
    expect(p).not_to be_valid
    expect(p.errors[:provider]).to be_present
    expect(p.errors[:flow]).to be_present
  end

  it "enforces out_trade_no uniqueness" do
    create_payment(out_trade_no: "t1")
    dup = described_class.new(payment_order: order, provider: "alipay", flow: "qr",
                              out_trade_no: "t1", amount: 1.00)
    expect(dup).not_to be_valid
  end

  it "rounds amounts using the order's zero-decimal currency" do
    jpy_order = create(:payment_order,
      external_ref: "jpy-order", amount: 1000, subject: "s", currency: "JPY"
    )
    payment = described_class.new(
      payment_order: jpy_order, provider: "stripe", flow: "card",
      out_trade_no: "jpy-payment", amount: "1000.50"
    )

    expect(payment).to be_valid
    expect(payment.amount).to eq(1001.00)
  end

  it "transitions succeeded idempotently and marks order paid" do
    p = create_payment(out_trade_no: "t2")
    p.mark_succeeded!(psp_id: "X", at: Time.zone.now, notify: { "foo" => 1 })
    expect(p.reload.status).to eq("succeeded")
    expect(order.reload.status).to eq("paid")
    expect { p.mark_succeeded!(psp_id: "X", at: Time.zone.now, notify: { "foo" => 1 }) }.not_to raise_error
  end

  it "applies the order's record changes once, when this payment settles it" do
    p = create_payment(out_trade_no: "t-writeback")
    expect(Payments::PaidWriteback).to receive(:call).with(payment: p).once

    2.times { p.mark_succeeded!(psp_id: "X", at: Time.zone.now, notify: {}) }
  end

  it "does not apply the record changes again for a second payment of a paid order" do
    create_payment(out_trade_no: "t-first").mark_succeeded!(psp_id: "X", at: Time.zone.now, notify: {})
    second = create_payment(out_trade_no: "t-second")
    expect(Payments::PaidWriteback).not_to receive(:call)

    second.mark_succeeded!(psp_id: "Y", at: Time.zone.now, notify: {})
  end

  describe "concurrency locking" do
    let(:payment) { create_payment(out_trade_no: "lock1") }

    it "acquires with_lock on self and payment_order in mark_succeeded!" do
      expect(payment).to receive(:with_lock).and_call_original
      expect_any_instance_of(Payments::Order).to receive(:with_lock).and_call_original
      payment.mark_succeeded!(psp_id: "X", at: Time.zone.now, notify: { "foo" => 1 })
      expect(payment.reload.status).to eq("succeeded")
      expect(order.reload.status).to eq("paid")
    end

    it "acquires with_lock on self and payment_order in mark_failed!" do
      expect(payment).to receive(:with_lock).and_call_original
      expect_any_instance_of(Payments::Order).to receive(:with_lock).and_call_original
      payment.mark_failed!(reason: "timeout", notify: { "err" => 1 })
      expect(payment.reload.status).to eq("failed")
      expect(order.reload.status).to eq("failed")
    end
  end

  describe "idempotent status transitions" do
    it "mark_pending! skips update when already pending" do
      p = create_payment(out_trade_no: "idem1", status: "pending")
      expect { p.mark_pending!("payload") }.not_to raise_error
      expect(p.reload.status).to eq("pending")
    end

    it "mark_pending! transitions from created to pending" do
      p = create_payment(out_trade_no: "idem2")
      p.mark_pending!("payload_data")
      expect(p.reload.status).to eq("pending")
      expect(p.reload.prepay_payload).to eq("payload_data")
    end

    it "mark_failed! is idempotent when already failed" do
      p = create_payment(out_trade_no: "idem3")
      p.mark_failed!(reason: "first failure", notify: {})
      expect { p.mark_failed!(reason: "second attempt", notify: {}) }.not_to raise_error
      expect(p.reload.status).to eq("failed")
    end

    it "mark_closed! transitions from created to closed" do
      p = create_payment(out_trade_no: "idem4")
      p.mark_closed!
      expect(p.reload.status).to eq("closed")
    end

    it "mark_closed! is idempotent when already closed" do
      p = create_payment(out_trade_no: "idem5", status: "closed")
      expect { p.mark_closed! }.not_to raise_error
      expect(p.reload.status).to eq("closed")
    end
  end

  describe "terminal-state guards (M1)" do
    it "does not regress a concurrent capture when mark_pending! runs on a stale instance" do
      stale = create_payment(out_trade_no: "stale-pending")
      captured = described_class.find(stale.id)
      captured.mark_succeeded!(psp_id: "captured", at: Time.current, notify: { "captured" => true })

      stale.mark_pending!("client_secret" => "late")

      expect(stale.reload.status).to eq("succeeded")
      expect(stale.raw_notify).to eq("captured" => true)
      expect(order.reload.status).to eq("paid")
    end

    it "retains the committed merchant identity when the prepay result is written" do
      payment = create_payment(out_trade_no: "bound-pending",
        prepay_payload: { "_attempt" => { "merchant_account_id" => 123, "mode" => "sandbox" } })

      payment.mark_pending!("client_secret" => "secret")

      expect(payment.reload.merchant_account_id).to eq(123)
      expect(payment.prepay_payload["client_secret"]).to eq("secret")
    end

    it "mark_failed! leaves a succeeded payment untouched" do
      p = create_payment(out_trade_no: "term1", status: "succeeded")
      p.mark_failed!(reason: "x")
      expect(p.reload.status).to eq("succeeded")
    end

    it "mark_closed! leaves a succeeded payment untouched" do
      p = create_payment(out_trade_no: "term2", status: "succeeded")
      p.mark_closed!
      expect(p.reload.status).to eq("succeeded")
    end

    it "mark_pending! leaves a succeeded payment untouched (late/replayed 'user paying' notification)" do
      p = create_payment(out_trade_no: "term3", status: "succeeded")
      p.mark_pending!("late_replay_payload")
      expect(p.reload.status).to eq("succeeded")
    end

    it "mark_pending! leaves a failed payment untouched" do
      p = create_payment(out_trade_no: "term4", status: "failed")
      p.mark_pending!("payload")
      expect(p.reload.status).to eq("failed")
    end

    it "mark_pending! leaves a closed payment untouched" do
      p = create_payment(out_trade_no: "term5", status: "closed")
      p.mark_pending!("payload")
      expect(p.reload.status).to eq("closed")
    end
  end
end
