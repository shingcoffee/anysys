# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payments historical merchant operations" do
  let(:customer) { create(:customer) }
  let(:historical) do
    create(:payment_merchant_account, :stripe, customer: customer, mode: "production", status: "disabled",
           credentials: { secret_key: "sk_live_historical" })
  end
  let(:order) { create(:payment_order, customer: customer, amount: 1.00, currency: "USD") }
  let(:payment) do
    create(:payment, customer: customer, payment_order: order, provider: "stripe", flow: "card",
           status: "pending", amount: 1.00, psp_transaction_id: "pi_historical",
            prepay_payload: { "_attempt" => { "provider" => "stripe", "merchant_account_id" => historical.id,
             "merchant_id" => historical.merchant_id, "mode" => historical.mode } })
  end

  before do
    Current.customer = customer
    create(:payment_merchant_account, :stripe, customer: customer,
           credentials: { secret_key: "sk_test_replacement" })
  end

  after { Current.reset }

  it "queries the recorded account rather than replacing a disabled production merchant with the active sandbox merchant" do
    lookup = stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_historical")
      .with(headers: { "Authorization" => "Bearer sk_live_historical" })
      .to_return(status: 200, body: { id: "pi_historical", status: "succeeded", currency: "usd", amount_received: 100,
        latest_charge: { created: Time.current.to_i } }.to_json)

    Payments::Activities::Query.call(customer: customer, payment: payment)

    expect(payment.reload.status).to eq("succeeded")
    expect(order.reload.status).to eq("paid")
    expect(lookup).to have_been_requested.once
  end

  it "refunds through the same historical account with the committed refund key" do
    payment.mark_succeeded!(psp_id: "pi_historical", at: Time.current, notify: {})
    request = stub_request(:post, "https://api.stripe.com/v1/refunds")
      .with(headers: { "Authorization" => "Bearer sk_live_historical" },
            body: hash_including("payment_intent" => "pi_historical", "amount" => "100"))
      .to_return(status: 200, body: { id: "re_historical", status: "succeeded" }.to_json)

    refund = Payments::Activities::Refund.call(customer: customer, payment: payment, amount: 1.00)

    expect(refund.status).to eq("succeeded")
    expect(order.reload.status).to eq("refunded")
    expect(request).to have_been_requested.once
    expect(a_request(:post, "https://api.stripe.com/v1/refunds")
      .with(headers: { "Idempotency-Key" => refund.out_refund_no })).to have_been_made.once
  end

  it "closes the existing remote object using pinned disabled credentials" do
    request = stub_request(:post, "https://api.stripe.com/v1/payment_intents/pi_historical/cancel")
      .with(headers: { "Authorization" => "Bearer sk_live_historical" })
      .to_return(status: 200, body: { id: "pi_historical", status: "canceled" }.to_json)

    expect(Payments::Gateway.close(customer: customer, payment: payment)).to eq(status: :closed)
    expect(request).to have_been_requested.once
  end

  it "pins a historical bill to the payment's account without selecting today's environment account" do
    account = create(:payment_merchant_account, :alipay, customer: customer, mode: "production", status: "disabled")
    ali_order = create(:payment_order, customer: customer, amount: 1.00, currency: "CNY")
    ali_payment = create(:payment, customer: customer, payment_order: ali_order, provider: "alipay", amount: 1.00,
                         status: "succeeded", paid_at: Time.current,
                          prepay_payload: { "_attempt" => { "provider" => "alipay", "merchant_account_id" => account.id,
                           "merchant_id" => account.merchant_id, "mode" => account.mode } })
    create(:payment_merchant_account, :alipay, customer: customer)
    gateway = instance_double(Payments::Gateways::Alipay,
      download_bill: { csv: "out_trade_no,amount,currency\n#{ali_payment.out_trade_no},1.00,CNY\n", raw_summary: {} })
    allow(Payments::Gateways::Alipay).to receive(:new).with(account: account).and_return(gateway)

    bill = Payments::Activities::Reconcile.call(customer: customer, provider: "alipay",
                                               bill_date: Date.current, payment: ali_payment)

    expect(bill.status).to eq("reconciled")
    expect(bill.discrepancy_count).to eq(0)
    expect(bill.raw_summary["merchant_account_id"]).to eq(account.id)
    expect(bill.raw_summary["mode"]).to eq("production")
    expect(gateway).to have_received(:download_bill).with(bill_date: Date.current, bill_type: "all")
  end

  it "rejects a captured-record fast path requested under another tenant" do
    payment.mark_succeeded!(psp_id: "pi_historical", at: Time.current, notify: {})

    expect { Payments::Activities::Query.call(customer: create(:customer), payment: payment) }
      .to raise_error(Payments::Errors::TenantMismatch)
  end
end
