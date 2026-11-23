# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Payments do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  def enable_payments!(cust)
    fm = enable_module!("payment", cust, name: "Payments")
    fm.update!(handoff_enabled: true)
    fm
  end

  describe ".request" do
    it "writes a normalized payment handoff and leaves order creation to checkout" do
      enable_payments!(customer)
      ctx = { customer_id: customer.id, errors: [], submission_outcome: { "preset" => "thank_you" } }

      expect(described_class.request(ctx, amount: 12.5, currency: "cny", subject: " Fee ")).to be(true)
      expect(ctx[:submission_outcome]).to eq(
        "preset" => "thank_you",
        "handoff" => {
          "module_key" => "payment",
          "input" => { "amount" => Payments::Money.normalize(12.5, "CNY"), "currency" => "CNY", "subject" => "Fee" }
        }
      )
      expect(Payments::Order.count).to eq(0)
    end

    it "stamps optional checkout fields onto the handoff input" do
      enable_payments!(customer)
      ctx = { customer_id: customer.id, errors: [] }

      freeze_time do
        described_class.request(
          ctx,
          amount: 1,
          currency: "CNY",
          subject: "Fee",
          description: " Note ",
          metadata: { sku: "abc" },
          expires_in_minutes: 5,
          exit_target: { kind: "route", name: "customer_home" }
        )
      end

      input = ctx[:submission_outcome].dig("handoff", "input")
      expect(input["body"]).to eq("Note")
      expect(input["metadata"]).to eq("sku" => "abc")
      expect(input["expires_at"]).to eq(5.minutes.from_now.utc.iso8601)
      expect(ctx[:submission_outcome].dig("handoff", "exit_target")).to eq(
        "kind" => "route", "name" => "customer_home"
      )
    end

    it "fails invalid_order for a non-positive amount or blank subject" do
      enable_payments!(customer)
      [{ amount: 0, subject: "Fee" }, { amount: 5, subject: " " }].each do |args|
        ctx = { customer_id: customer.id, errors: [] }
        expect(described_class.request(ctx, currency: "CNY", **args)).to be(false)
        expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.request_payment.invalid_order")])
        expect(ctx[:submission_outcome]).to be_nil
      end
    end

    it "fails with a translated code when the Payment module is disabled" do
      ctx = { customer_id: customer.id, errors: [] }

      expect(described_class.request(ctx, amount: 1, currency: "CNY", subject: "Fee")).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.request_payment.module_disabled")])
      expect(Payments::Order.for_customer(customer.id)).to be_empty
    end
  end

  describe ".refund" do
    let(:order) { create(:payment_order, customer: customer, amount: 5.00, subject: "s") }
    let(:payment) do
      create(:payment, customer: customer, payment_order: order, provider: "alipay",
             flow: "qr", amount: 5.00, status: "succeeded")
    end

    it "refunds a payment of the run customer" do
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})
      ctx = { customer_id: customer.id, errors: [] }
      Current.customer = customer

      refund = described_class.refund(ctx, payment: payment.id, amount: 1.00, reason: "dup")
      expect(refund).to be_a(Payments::Refund)
      expect(Payments::Refund.where(payment_id: payment.id)).to exist
    end

    it "refunds the captured amount when mode is full" do
      allow(Payments::Gateway).to receive(:refund)
        .and_return(status: :succeeded, psp_refund_id: "P1", raw: {})
      ctx = { customer_id: customer.id, errors: [] }
      Current.customer = customer

      refund = described_class.refund(ctx, payment: payment.id, mode: "full")
      expect(refund.amount).to eq(payment.amount)
    end

    it "rejects another tenant's payment without calling the gateway" do
      foreign = create(:payment, customer: other, status: "succeeded", amount: 5.00)
      expect(Payments::Gateway).not_to receive(:refund)
      ctx = { customer_id: customer.id, errors: [] }

      expect(described_class.refund(ctx, payment: foreign.id, amount: 1.00)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.refund_payment.not_found")])
      expect(Payments::Refund.where(payment_id: foreign.id)).to be_empty
    end
  end
end
