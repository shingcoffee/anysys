require "rails_helper"

RSpec.describe Payments::Activities::Refund do
  let_it_be(:customer) { create(:customer) }
  let(:order) { create(:payment_order, external_ref: "or", amount: 5.00, subject: "s") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "otr-1", amount: 5.00, status: "succeeded")
  end

  before { Current.customer = customer }

  it "marks refund succeeded on synchronous success" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})

    refund = described_class.call(customer: customer, payment: payment,
                                  amount: 1.00, reason: "customer")
    expect(refund).to be_persisted
    expect(refund.status).to eq("succeeded")
    expect(refund.psp_refund_id).to eq("P1")
  end

  it "marks refund failed when the gateway returns :failed (no stranded processing)" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :failed, raw: { "error" => "refund_declined" })

    refund = described_class.call(customer: customer, payment: payment,
                                  amount: 1.00, reason: "bad")
    expect(refund.status).to eq("failed")
  end

  it "marks refund processing when gateway returns :processing" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :processing, psp_refund_id: "P-PENDING", raw: { "status" => "pending" })

    refund = described_class.call(customer: customer, payment: payment,
                                  amount: 2.00, reason: "partial")
    expect(refund.status).to eq("processing")
    expect(refund.psp_refund_id).to eq("P-PENDING")
    expect(refund.raw_notify).to eq("status" => "pending")
  end

  it "reuses an in-flight refund when called again with the same (amount, reason)" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :processing, raw: {})

    first = described_class.call(customer: customer, payment: payment,
                                 amount: 1.50, reason: "dup")
    second = described_class.call(customer: customer, payment: payment,
                                  amount: 1.50, reason: "dup")
    expect(second.id).to eq(first.id)
    expect(Payments::Refund.where(payment_id: payment.id).count).to eq(1)
  end

  it "reuses an in-flight refund for the same amount even when the reason differs" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :processing, raw: {})

    first = described_class.call(customer: customer, payment: payment,
                                 amount: 1.50, reason: "a")
    second = described_class.call(customer: customer, payment: payment,
                                  amount: 1.50, reason: "b")
    expect(second.id).to eq(first.id)
    expect(Payments::Refund.where(payment_id: payment.id).count).to eq(1)
  end

  it "serializes concurrent refund attempts via row lock on Payment" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :succeeded, psp_refund_id: "PX", raw: {})

    expect(payment).to receive(:with_lock).and_call_original

    described_class.call(customer: customer, payment: payment,
                         amount: 1.20, reason: "race")
  end

  it "refuses a billing collection without calling the gateway" do
    order.update!(external_ref: "billing-inv-9")
    expect(Payments::Gateway).not_to receive(:refund)

    expect {
      described_class.call(customer: customer, payment: payment, amount: 1.00, reason: "invoice")
    }.to raise_error(Payments::Errors::RefundNotAllowed) { |error| expect(error.code).to eq(:billing_collection) }
    expect(Payments::Refund.where(payment_id: payment.id)).to be_empty
  end

  describe "over-refund protection (C4)" do
    it "rejects a refund larger than the captured amount without calling the gateway" do
      expect(Payments::Gateway).not_to receive(:refund)

      expect {
        described_class.call(customer: customer, payment: payment, amount: 5.01)
      }.to raise_error(Payments::Errors::RefundNotAllowed)
      expect(Payments::Refund.where(payment_id: payment.id)).to be_empty
    end

    it "rejects a refund whose cumulative total would exceed the captured amount" do
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})
      described_class.call(customer: customer, payment: payment, amount: 3.00, reason: "a")

      expect {
        described_class.call(customer: customer, payment: payment, amount: 3.00, reason: "b")
      }.to raise_error(Payments::Errors::RefundNotAllowed)
      expect(Payments::Refund.where(payment_id: payment.id).sum(:amount)).to eq(3.00)
    end

    it "allows a partial refund up to the exact remaining balance" do
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})
      described_class.call(customer: customer, payment: payment, amount: 2.00, reason: "a")

      expect {
        described_class.call(customer: customer, payment: payment, amount: 3.00, reason: "b")
      }.not_to raise_error
    end

    it "normalizes the requested amount before checking the refundable balance" do
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})

      refund = described_class.call(
        customer: customer, payment: payment, amount: "5.004", reason: "rounded"
      )

      expect(refund.amount).to eq(5.00)
    end

    it "rejects a non-finite amount without calling the gateway" do
      expect(Payments::Gateway).not_to receive(:refund)

      expect {
        described_class.call(customer: customer, payment: payment, amount: "NaN")
      }.to raise_error(Payments::Errors::RefundNotAllowed) { |e| expect(e.code).to eq(:non_positive) }
      expect(Payments::Refund.where(payment_id: payment.id)).to be_empty
    end

    it "rejects an array amount without calling the gateway" do
      expect(Payments::Gateway).not_to receive(:refund)

      expect {
        described_class.call(customer: customer, payment: payment, amount: ["1.00"])
      }.to raise_error(Payments::Errors::RefundNotAllowed) { |e| expect(e.code).to eq(:non_positive) }
      expect(Payments::Refund.where(payment_id: payment.id)).to be_empty
    end

    it "refuses to refund a payment that is not captured" do
      pending_payment = create(:payment, payment_order: order, provider: "alipay",
        flow: "qr", out_trade_no: "otr-pending", amount: 5.00, status: "pending")
      expect(Payments::Gateway).not_to receive(:refund)

      expect {
        described_class.call(customer: customer, payment: pending_payment, amount: 1.00)
      }.to raise_error(Payments::Errors::RefundNotAllowed)
    end
  end

  describe "commit-before-PSP-call retry safety (H1)" do
    it "keeps an uncertain API-error reservation and original refund key across retries" do
      error = Payments::Errors::ApiError.new("provider outcome unknown")
      error.define_singleton_method(:uncertain?) { true }
      allow(Payments::Gateway).to receive(:refund).and_raise(error)

      expect { described_class.call(customer: customer, payment: payment, amount: 5.00) }
        .to raise_error(Payments::Errors::ApiError)
      original = payment.payment_refunds.sole
      expect(original.status).to eq("requested")

      expect { described_class.call(customer: customer, payment: payment, amount: 1.00) }
        .to raise_error(Payments::Errors::RefundNotAllowed)

      allow(Payments::Gateway).to receive(:refund).and_return(status: :succeeded, psp_refund_id: "same", raw: {})
      retried = described_class.call(customer: customer, payment: payment, amount: 5.00)

      expect(retried.out_refund_no).to eq(original.out_refund_no)
      expect(payment.payment_refunds.count).to eq(1)
      expect(retried.status).to eq("succeeded")
    end

    it "persists the refund row with status requested when the gateway raises TransportError, and a retry reuses the same row" do
      allow(Payments::Gateway).to receive(:refund).and_raise(Payments::Errors::TransportError, "timeout")

      expect {
        described_class.call(customer: customer, payment: payment, amount: 1.00, reason: "flaky")
      }.to raise_error(Payments::Errors::TransportError)

      refund = Payments::Refund.where(payment_id: payment.id).sole
      expect(refund.status).to eq("requested")
      first_out_refund_no = refund.out_refund_no

      # Retry: gateway now succeeds — the SAME row (same out_refund_no) is reused.
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P-RETRY", raw: {})

      retried = described_class.call(customer: customer, payment: payment, amount: 1.00, reason: "flaky")

      expect(Payments::Refund.where(payment_id: payment.id).count).to eq(1)
      expect(retried.id).to eq(refund.id)
      expect(retried.out_refund_no).to eq(first_out_refund_no)
      expect(retried.status).to eq("succeeded")
    end

    it "counts a stuck 'requested' row (from an unretried TransportError) against the over-refund ceiling" do
      # First partial refund times out ambiguously and is never retried — it
      # commits and stays "requested" (H1's whole point: the row is NOT rolled
      # back). This is intentional: the PSP may have actually processed it, so
      # the ceiling must treat it as reserved, not as if it never happened.
      allow(Payments::Gateway).to receive(:refund).and_raise(Payments::Errors::TransportError, "timeout")
      expect {
        described_class.call(customer: customer, payment: payment, amount: 3.00, reason: "stuck")
      }.to raise_error(Payments::Errors::TransportError)
      stuck = Payments::Refund.where(payment_id: payment.id).sole
      expect(stuck.status).to eq("requested")

      # A second refund of a *different* amount — 3.00 is already reserved by
      # the stuck row, so 3.00 + 2.01 would exceed the 5.00 capture. Same-amount
      # retries reuse the in-flight row (reason is not part of the key).
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P-BLOCKED", raw: {})

      expect {
        described_class.call(customer: customer, payment: payment, amount: 2.01, reason: "second")
      }.to raise_error(Payments::Errors::RefundNotAllowed)

      # The remaining 200 (500 - 300 reserved) is still refundable.
      expect {
        described_class.call(customer: customer, payment: payment, amount: 2.00, reason: "remainder")
      }.not_to raise_error
      expect(Payments::Refund.where(payment_id: payment.id).sum(:amount)).to eq(5.00)
    end

    it "reuses a stuck 'requested' row for a full refund without hitting the over-refund ceiling (H1 regression)" do
      # Full refund (500 of 500) times out ambiguously, leaving the row "requested".
      allow(Payments::Gateway).to receive(:refund).and_raise(Payments::Errors::TransportError, "timeout")
      expect {
        described_class.call(customer: customer, payment: payment, amount: 5.00, reason: "full")
      }.to raise_error(Payments::Errors::TransportError)
      stuck = Payments::Refund.where(payment_id: payment.id).sole
      expect(stuck.status).to eq("requested")

      # Retry with the SAME (amount, reason) must reuse the stuck row instead of
      # being rejected by the over-refund ceiling (which would otherwise count
      # the stuck row's own 500 as "already refunded" against itself, leaving a
      # refundable remainder of 0 and making the retry permanently unreachable).
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P-FULL", raw: {})

      retried = nil
      expect {
        retried = described_class.call(customer: customer, payment: payment, amount: 5.00, reason: "full")
      }.not_to raise_error

      expect(Payments::Refund.where(payment_id: payment.id).count).to eq(1)
      expect(retried.id).to eq(stuck.id)
      expect(retried.status).to eq("succeeded")
    end

    it "preserves the refund reservation when the API error has no definitive outcome classification" do
      allow(Payments::Gateway).to receive(:refund)
        .and_raise(Payments::Errors::ApiError.new("declined", code: "x", payload: {}))

      expect {
        described_class.call(customer: customer, payment: payment, amount: 1.00, reason: "bad-api")
      }.to raise_error(Payments::Errors::ApiError)

      refund = Payments::Refund.where(payment_id: payment.id).sole
      expect(refund.status).to eq("requested")
    end
  end
end
