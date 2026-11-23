# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payments ambiguous-write retry age" do
  let(:customer) { create(:customer) }
  let(:account) { create(:payment_merchant_account, :stripe, customer: customer, credentials: { secret_key: "sk_test_original" }) }
  let(:order) { create(:payment_order, customer: customer, amount: 1.00, currency: "USD") }
  let(:request) { instance_double(ActionDispatch::Request, user_agent: "Mozilla/5.0", remote_ip: "127.0.0.1") }

  before do
    Current.customer = customer
    account
  end

  after { Current.reset }

  def checkout
    Payments::Activities::Charge.call(customer: customer, order: order, provider: "stripe", request: request)
  end

  def lose_checkout_response
    allow(Payments::Gateway).to receive(:charge).and_raise(Payments::Errors::TransportError, "lost response")
    expect { checkout }.to raise_error(Payments::Errors::TransportError)
    order.payments.sole
  end

  def stripe_search(data: [], status: 200)
    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/payment_intents/search\?})
      .with(headers: { "Authorization" => "Bearer sk_test_original" })
      .to_return(status: status, body: { object: "search_result", data: data, has_more: false }.to_json)
  end

  it "blocks an expired key after an empty historical search without creating a new payment or calling charge" do
    original = lose_checkout_response
    search = stripe_search
    account.update!(status: "disabled")
    allow(Payments::CredentialResolver).to receive(:default_mode).and_return("production")

    travel_to(original.created_at + 25.hours) do
      2.times { expect { checkout }.to raise_error(Payments::Errors::OrderInFlight) }
    end

    expect(order.payments.sole.out_trade_no).to eq(original.out_trade_no)
    expect(original.reload.status).to eq("created")
    expect(original.attempt_context["review_reason"]).to eq("idempotency_window_expired")
    expect(Payments::Gateway).to have_received(:charge).once
    expect(search).to have_been_requested.twice
  end

  it "recovers the exact capture through the existing Stripe metadata-search API instead of replaying an expired write" do
    original = lose_checkout_response
    settled_at = original.created_at + 1.minute
    remote = { "id" => "pi_recovered", "status" => "succeeded", "currency" => "usd", "amount_received" => 100,
               "metadata" => { "out_trade_no" => original.out_trade_no }, "latest_charge" => { "created" => settled_at.to_i } }
    search = stripe_search(data: [remote])
    retrieve = stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_recovered")
      .with(headers: { "Authorization" => "Bearer sk_test_original" }).to_return(status: 200, body: remote.to_json)

    travel_to(original.created_at + 25.hours) do
      expect(checkout[:payment].status).to eq("succeeded")
    end

    expect(order.payments.sole.id).to eq(original.id)
    expect(original.reload.psp_transaction_id).to eq("pi_recovered")
    expect(original.paid_at.to_i).to eq(settled_at.to_i)
    expect(Payments::Gateway).to have_received(:charge).once
    expect(search).to have_been_requested.once
    expect(retrieve).to have_been_requested.once
  end

  it "does not turn an expired reconciliation API error into a failed payment and fresh operation" do
    original = lose_checkout_response
    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/payment_intents/search\?})
      .to_return(status: 400, body: { error: { code: "temporary_query_failure" } }.to_json)

    travel_to(original.created_at + 25.hours) do
      expect { checkout }.to raise_error(Payments::Errors::OrderInFlight)
    end

    expect(original.reload.status).to eq("created")
    expect(order.payments.count).to eq(1)
    expect(Payments::Gateway).to have_received(:charge).once
  end

  it "uses the same token-charge operation inside the safe window and blocks it outside the window" do
    method = create(:payment_method, customer: customer)
    charge = -> { Payments::Activities::ChargeToken.call(customer: customer, order: order, payment_method: method) }
    allow(Payments::Gateway).to receive(:charge_token).and_raise(Payments::Errors::TransportError, "lost response")
    expect { charge.call }.to raise_error(Payments::Errors::TransportError)
    original = order.payments.sole

    travel_to(original.created_at + 22.hours) do
      expect { charge.call }.to raise_error(Payments::Errors::TransportError)
    end
    stripe_search
    travel_to(original.created_at + 25.hours) do
      expect { charge.call }.to raise_error(Payments::Errors::OrderInFlight)
    end

    expect(order.payments.sole.id).to eq(original.id)
    expect(original.reload.status).to eq("created")
    expect(Payments::Gateway).to have_received(:charge_token).twice
  end

  it "keeps an expired uncertain refund reserved and refuses an automatic refund replay" do
    payment = create(:payment, customer: customer, payment_order: order, provider: "stripe", amount: 1.00, status: "succeeded")
    allow(Payments::Gateway).to receive(:refund).and_raise(Payments::Errors::TransportError, "lost response")
    refund_call = ->(amount) { Payments::Activities::Refund.call(customer: customer, payment: payment, amount: amount) }
    expect { refund_call.call(1.00) }.to raise_error(Payments::Errors::TransportError)
    original = payment.payment_refunds.sole

    travel_to(original.created_at + 25.hours) do
      expect { refund_call.call(1.00) }.to raise_error(Payments::Errors::OrderInFlight)
      expect { refund_call.call(0.50) }.to raise_error(Payments::Errors::RefundNotAllowed)
    end

    expect(payment.payment_refunds.sole.out_refund_no).to eq(original.out_refund_no)
    expect(original.reload.status).to eq("requested")
    expect(Payments::Gateway).to have_received(:refund).once
  end
end
