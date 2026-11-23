require "rails_helper"

RSpec.describe Payments::Activities::Query do
  let_it_be(:customer) { create(:customer) }
  let(:order) { create(:payment_order, external_ref: "oq", amount: 2.00, subject: "s") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "otq-1", amount: 2.00, status: "pending")
  end

  before { Current.customer = customer }

  it "marks payment succeeded when gateway returns :succeeded" do
    allow(Payments::Gateway).to receive(:query)
      .and_return(status: :succeeded, psp_transaction_id: "T1", raw: { "ok" => 1 })

    result = described_class.call(customer: customer, payment: payment)

    aggregate_failures do
      expect(payment.reload.status).to eq("succeeded")
      expect(payment.psp_transaction_id).to eq("T1")
      expect(order.reload.status).to eq("paid")
      expect(result[:status]).to eq(:succeeded)
    end
  end

  it "marks payment failed when gateway returns :failed" do
    allow(Payments::Gateway).to receive(:query)
      .and_return(status: :failed, raw: { "err" => "x" })

    described_class.call(customer: customer, payment: payment)

    expect(payment.reload.status).to eq("failed")
  end

  it "marks payment closed when gateway returns :closed" do
    allow(Payments::Gateway).to receive(:query)
      .and_return(status: :closed, raw: { "trade_status" => "TRADE_CLOSED" })

    described_class.call(customer: customer, payment: payment)

    expect(payment.reload.status).to eq("closed")
    expect(order.reload.status).to eq("pending")
  end

  it "is a no-op on local state when gateway returns :pending" do
    allow(Payments::Gateway).to receive(:query)
      .and_return(status: :pending, raw: {})

    described_class.call(customer: customer, payment: payment)

    expect(payment.reload.status).to eq("pending")
  end

  it "does not mark paid when the PSP success reports a smaller amount" do
    allow(Payments::Gateway).to receive(:query)
      .and_return(status: :succeeded, psp_transaction_id: "T-under",
                  raw: { "total_amount" => "0.01" })

    described_class.call(customer: customer, payment: payment)

    expect(payment.reload.status).to eq("pending")
    expect(order.reload.status).to eq("pending")
  end

  it "marks paid when the PSP success amount matches the recorded amount" do
    allow(Payments::Gateway).to receive(:query)
      .and_return(status: :succeeded, psp_transaction_id: "T-match",
                  raw: { "total_amount" => "2.00" })

    described_class.call(customer: customer, payment: payment)

    expect(payment.reload.status).to eq("succeeded")
    expect(order.reload.status).to eq("paid")
  end

  describe "Stripe currency and settlement evidence" do
    let(:stripe_order) { create(:payment_order, currency: "USD", amount: 2.00) }
    let(:stripe_payment) { create(:payment, payment_order: stripe_order, provider: "stripe", flow: "card", amount: 2.00, status: "pending", psp_transaction_id: "pi_query") }

    it "rejects a different reported currency when the smallest-unit amount is identical" do
      allow(Payments::Gateway).to receive(:query).and_return(
        status: :succeeded, psp_transaction_id: "pi_wrong", raw: { "amount_received" => 200, "currency" => "eur" }
      )

      described_class.call(customer: customer, payment: stripe_payment)

      expect(stripe_payment.reload.status).to eq("pending")
      expect(stripe_order.reload.status).to eq("pending")
    end

    it "uses an expanded capture timestamp rather than poll time or intent creation" do
      captured_at = Time.utc(2026, 7, 13, 23, 58, 0)
      allow(Payments::Gateway).to receive(:query).and_return(
        status: :succeeded, psp_transaction_id: "pi_timestamp", raw: {
          "amount_received" => 200, "currency" => "usd", "created" => 1.week.ago.to_i,
          "latest_charge" => { "created" => captured_at.to_i }
        }
      )

      described_class.call(customer: customer, payment: stripe_payment)

      expect(stripe_payment.reload.paid_at).to eq(captured_at)
      expect(stripe_order.reload.paid_at).to eq(captured_at)
    end

    it "consumes the gateway's authoritative normalized settlement evidence" do
      captured_at = Time.utc(2026, 7, 13, 23, 58, 0)
      allow(Payments::Gateway).to receive(:query).and_return(
        status: :succeeded, psp_transaction_id: "pi_normalized", amount: BigDecimal("2.00"),
        currency: "USD", settled_at: captured_at, raw: { "latest_charge" => "ch_unexpanded" }
      )

      described_class.call(customer: customer, payment: stripe_payment)

      expect(stripe_payment.reload.paid_at).to eq(captured_at)
    end
  end

  describe "PayPal Order JSON" do
    let(:paypal_order) { create(:payment_order, external_ref: "pq", amount: 10.00, subject: "s", currency: "USD") }
    let(:paypal_payment) do
      create(:payment, payment_order: paypal_order, provider: "paypal", flow: "card",
             out_trade_no: "ppq-1", amount: 10.00, status: "pending")
    end

    def paypal_order_raw(capture_value:, unit_value: "10.00")
      {
        "status" => "COMPLETED",
        "purchase_units" => [{
          "amount" => { "currency_code" => "USD", "value" => unit_value },
          "payments" => {
            "captures" => [{
              "id" => "CAP-Q",
              "amount" => { "currency_code" => "USD", "value" => capture_value }
            }]
          }
        }]
      }
    end

    it "does not mark paid when the nested capture amount is smaller than recorded" do
      allow(Payments::Gateway).to receive(:query)
        .and_return(status: :succeeded, psp_transaction_id: "CAP-under",
                    raw: paypal_order_raw(capture_value: "0.01"))

      described_class.call(customer: customer, payment: paypal_payment)

      expect(paypal_payment.reload.status).to eq("pending")
      expect(paypal_order.reload.status).to eq("pending")
    end

    it "marks paid when the nested capture amount matches the recorded amount" do
      allow(Payments::Gateway).to receive(:query)
        .and_return(status: :succeeded, psp_transaction_id: "CAP-match",
                    raw: paypal_order_raw(capture_value: "10.00"))

      described_class.call(customer: customer, payment: paypal_payment)

      expect(paypal_payment.reload.status).to eq("succeeded")
      expect(paypal_order.reload.status).to eq("paid")
    end

    it "does not mark paid when the nested capture currency differs from the order" do
      allow(Payments::Gateway).to receive(:query)
        .and_return(status: :succeeded, psp_transaction_id: "CAP-eur",
                    raw: {
                      "status" => "COMPLETED",
                      "purchase_units" => [{
                        "payments" => {
                          "captures" => [{
                            "id" => "CAP-eur",
                            "amount" => { "currency_code" => "EUR", "value" => "10.00" }
                          }]
                        }
                      }]
                    })

      described_class.call(customer: customer, payment: paypal_payment)

      expect(paypal_payment.reload.status).to eq("pending")
      expect(paypal_order.reload.status).to eq("pending")
    end

    it "does not mark paid when the Order JSON has no capture amount" do
      allow(Payments::Gateway).to receive(:query)
        .and_return(status: :succeeded, psp_transaction_id: "CAP-bare",
                    raw: {
                      "status" => "COMPLETED",
                      "purchase_units" => [{
                        "amount" => { "currency_code" => "USD", "value" => "10.00" },
                        "payments" => { "captures" => [{ "id" => "CAP-bare" }] }
                      }]
                    })

      described_class.call(customer: customer, payment: paypal_payment)

      expect(paypal_payment.reload.status).to eq("pending")
      expect(paypal_order.reload.status).to eq("pending")
    end
  end
end
