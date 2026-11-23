require "rails_helper"

RSpec.describe Payments::Activities::Charge do
  let_it_be(:customer) { create(:customer) }
  let(:order) { create(:payment_order, external_ref: "e1", amount: 1.00, subject: "s") }
  let(:request) { instance_double(ActionDispatch::Request, user_agent: "Mozilla/5.0 (Mac)", remote_ip: "127.0.0.1") }
  let(:user)     { create(:user, customer: customer) }

  before do
    Current.customer = customer
    %w[alipay wechat_pay stripe].each do |provider|
      create(:payment_merchant_account, customer: customer, provider: provider)
    end
    allow(Payments::Gateway).to receive(:charge)
      .and_return(prepay_payload: { code_url: "URL1" })
    allow(Payments::Gateway).to receive(:close).and_return(status: :closed)
    allow(Payments::Activities::Query).to receive(:call)
  end

  # Defaults to the alipay/order/desktop-request graph above; override per example.
  def charge(**overrides)
    described_class.call(customer: customer, order: order, provider: "alipay",
                         request: request, **overrides)
  end

  it "creates a pending Payment with the QR flow and gateway prepay payload" do
    result = charge
    expect(result[:payment]).to be_persisted
    expect(result[:payment].status).to eq("pending")
    expect(result[:flow]).to eq(:qr)
    expect(result[:prepay_payload]).to eq("code_url" => "URL1")
    expect(Payments::Gateway).to have_received(:charge).with(hash_including(request: request))
  end

  it "persists the gateway psp_transaction_id when charge returns one" do
    allow(Payments::Gateway).to receive(:charge)
      .and_return(prepay_payload: { client_secret: "sec" }, psp_transaction_id: "pi_stored")

    result = charge(provider: "stripe")
    expect(result[:payment].psp_transaction_id).to eq("pi_stored")
  end

  it "reuses an existing created/pending payment for the same order+provider" do
    first  = charge
    second = charge
    expect(second[:payment].id).to eq(first[:payment].id)
  end

  it "commits an uncertain attempt before HTTP and retries the same identity and original flow" do
    order # materialize before measuring the outer spec transaction
    baseline = ActiveRecord::Base.connection.open_transactions
    first_key = nil
    mobile_request = instance_double(ActionDispatch::Request, user_agent: "MicroMessenger", remote_ip: "127.0.0.1")
    allow(Payments::Gateway).to receive(:charge) do |**kwargs|
      expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline)
      first_key ||= kwargs[:payment].out_trade_no
      expect(kwargs[:payment].out_trade_no).to eq(first_key)
      expect(kwargs[:flow]).to eq(:qr)
      raise Payments::Errors::TransportError, "timeout"
    end

    expect { charge(provider: "wechat_pay") }.to raise_error(Payments::Errors::TransportError)
    attempt = order.payments.sole
    expect(attempt.status).to eq("created")
    expect(attempt.merchant_account_id).to be_present
    expect { charge(provider: "wechat_pay", request: mobile_request) }.to raise_error(Payments::Errors::TransportError)

    expect(order.payments.count).to eq(1)
    expect(attempt.reload.out_trade_no).to eq(first_key)
  end

  it "returns the original pending payload and flow without a second PSP write from a different browser" do
    original = charge(provider: "wechat_pay")
    mobile_request = instance_double(ActionDispatch::Request, user_agent: "MicroMessenger", remote_ip: "127.0.0.1")

    retry_result = charge(provider: "wechat_pay", request: mobile_request, openid: "different")

    expect(retry_result[:flow]).to eq(original[:flow])
    expect(retry_result[:prepay_payload]).to eq(original[:prepay_payload])
    expect(retry_result[:prepay_payload]).not_to have_key("_attempt")
    expect(Payments::Gateway).to have_received(:charge).once
  end

  it "preserves the original save-card choice and member across an uncertain retry" do
    allow(Payments::Gateway).to receive(:charge).and_raise(Payments::Errors::TransportError, "timeout")
    expect { charge(provider: "stripe", save_card: true, user: user) }.to raise_error(Payments::Errors::TransportError)

    allow(Payments::Gateway).to receive(:charge).and_return(prepay_payload: { client_secret: "same" })
    charge(provider: "stripe", save_card: false, user: nil)

    expect(Payments::Gateway).to have_received(:charge).with(hash_including(save_card: true, user: user)).twice
  end

  it "refuses changed order contents while the original operation remains uncertain" do
    allow(Payments::Gateway).to receive(:charge).and_raise(Payments::Errors::TransportError, "timeout")
    expect { charge }.to raise_error(Payments::Errors::TransportError)
    order.update!(amount: 2.00)

    expect { charge }.to raise_error(Payments::Errors::OrderInFlight)
    expect(Payments::Gateway).to have_received(:charge).once
    expect(order.payments.sole.amount).to eq(1.00)
  end

  it "retires a definitively rejected checkout attempt so a corrected submission can use a new identity" do
    error = Payments::Errors::ApiError.new("definitively rejected")
    error.define_singleton_method(:definitive?) { true }
    allow(Payments::Gateway).to receive(:charge).and_raise(error)
    expect { charge }.to raise_error(Payments::Errors::ApiError)
    original = order.payments.sole
    expect(original.status).to eq("failed")

    allow(Payments::Gateway).to receive(:charge).and_return(prepay_payload: { code_url: "corrected" })
    retried = charge[:payment]

    expect(retried.out_trade_no).not_to eq(original.out_trade_no)
    expect(retried.status).to eq("pending")
  end

  it "does not infer definitive rejection from the API-error class and preserves the original operation" do
    allow(Payments::Gateway).to receive(:charge).and_raise(Payments::Errors::ApiError.new("outcome not classified"))
    expect { charge }.to raise_error(Payments::Errors::ApiError)
    original = order.payments.sole
    expect(original.status).to eq("created")

    allow(Payments::Gateway).to receive(:charge).and_return(prepay_payload: { code_url: "same-operation" })
    expect(charge[:payment].out_trade_no).to eq(original.out_trade_no)
    expect(order.payments.count).to eq(1)
  end

  it "serializes lookup and insert on the order row" do
    expect(order).to receive(:with_lock).and_call_original
    charge
  end

  it "re-checks settlement under the order lock so a concurrent capture cannot start a second charge" do
    allow(order).to receive(:with_lock).and_wrap_original do |method, &block|
      order.update_columns(status: "paid", paid_at: Time.zone.now)
      method.call(&block)
    end

    expect { charge }.to raise_error(Payments::Errors::OrderSettled)
    expect(Payments::Gateway).not_to have_received(:charge)
    expect(Payments::Payment.where(payment_order_id: order.id)).to be_empty
  end

  it "stamps the handoff_token on a newly created payment" do
    result = charge(handoff_token: "tok-abc")
    expect(result[:payment].handoff_token).to eq("tok-abc")
  end

  it "keeps the original handoff_token when reusing a payment (later shopper cannot re-stamp it)" do
    first  = charge(handoff_token: "tok-first")
    second = charge(handoff_token: "tok-second")
    expect(second[:payment].id).to eq(first[:payment].id)
    expect(second[:payment].handoff_token).to eq("tok-first")
  end

  it "produces different payments for different providers on the same order" do
    alipay_payment = charge
    wechat_payment = charge(provider: "wechat_pay")
    expect(alipay_payment[:payment].id).not_to eq(wechat_payment[:payment].id)
    expect(alipay_payment[:payment].reload.status).to eq("closed")
    expect(Payments::Gateway).to have_received(:close).with(
      hash_including(payment: alipay_payment[:payment])
    )
  end

  it "refuses a second provider when Query shows the sibling already captured" do
    alipay_payment = charge[:payment]
    allow(Payments::Activities::Query).to receive(:call) do |customer:, payment:|
      payment.mark_succeeded!(psp_id: "paid-1", at: Time.zone.now, notify: {})
    end

    expect { charge(provider: "wechat_pay") }.to raise_error(Payments::Errors::OrderSettled)
    expect(Payments::Gateway).to have_received(:charge).once
    expect(alipay_payment.reload.status).to eq("succeeded")
  end

  it "does not mark a sibling closed or start a second capture when close fails" do
    alipay_payment = charge[:payment]
    allow(Payments::Gateway).to receive(:close)
      .and_raise(Payments::Errors::ApiError.new("close failed"))

    expect { charge(provider: "wechat_pay") }.to raise_error(Payments::Errors::OrderInFlight)
    expect(alipay_payment.reload.status).to eq("pending")
    expect(Payments::Gateway).to have_received(:charge).once
  end

  it "refuses a second provider when a sibling is still pending after the pre-lock close window" do
    charge
    allow(described_class).to receive(:close_other_provider_attempts!)

    expect { charge(provider: "wechat_pay") }.to raise_error(Payments::Errors::OrderInFlight)
    expect(Payments::Gateway).to have_received(:charge).once
  end

  it "stamps user_id on a newly created payment so the member ledger can find it" do
    result = charge(user: user)

    expect(result[:payment].user_id).to eq(user.id)
  end

  it "refuses to charge an expired order" do
    order.update!(expires_at: 1.minute.ago)

    expect { charge }.to raise_error(Payments::Errors::OrderExpired)
    expect(Payments::Payment.where(payment_order_id: order.id)).to be_empty
  end

  it "refuses to charge an order that is already settled" do
    order.update!(status: "paid", paid_at: Time.zone.now)

    expect { charge }.to raise_error(Payments::Errors::OrderSettled)
    expect(Payments::Payment.where(payment_order_id: order.id)).to be_empty
  end

  %w[partial_refund refunded].each do |settled|
    it "refuses to charge an order in #{settled} status" do
      order.update!(status: settled)

      expect { charge }.to raise_error(Payments::Errors::OrderSettled)
    end
  end

  it "picks flow via FlowSelector based on user agent" do
    wechat_req = instance_double(ActionDispatch::Request, user_agent: "MicroMessenger", remote_ip: "127.0.0.1")
    result = charge(provider: "wechat_pay", request: wechat_req)
    expect(result[:flow]).to eq(:jsapi)
  end

  describe "save_card opt-in" do
    let(:stripe_req) { instance_double(ActionDispatch::Request, user_agent: "Mozilla/5.0", remote_ip: "127.0.0.1") }

    def stripe_order(external_ref)
      create(:payment_order, external_ref: external_ref, amount: 5.00,
             subject: "plan", currency: "CNY")
    end

    it "forwards save_card: true to the gateway when provider supports tokenized_cards and user present" do
      charge(order: stripe_order("sc-1"), provider: "stripe",
             request: stripe_req, save_card: true, user: user)

      expect(Payments::Gateway).to have_received(:charge).with(
        hash_including(save_card: true)
      )
    end

    it "does NOT forward save_card when no user is present" do
      charge(order: stripe_order("sc-2"), provider: "stripe",
             request: stripe_req, save_card: true, user: nil)

      expect(Payments::Gateway).to have_received(:charge).with(
        hash_including(save_card: false)
      )
    end

    it "does NOT forward save_card for providers without :tokenized_cards capability" do
      charge(save_card: true, user: user)

      expect(Payments::Gateway).to have_received(:charge).with(
        hash_including(save_card: false)
      )
    end

    it "inserts a pending vault row keyed to the PaymentIntent when save_card succeeds" do
      allow(Payments::Gateway).to receive(:charge).and_return(
        prepay_payload: { client_secret: "sec" },
        psp_transaction_id: "pi_save_1",
        psp_customer_id: "cus_save_1"
      )

      expect {
        charge(order: stripe_order("sc-vault"), provider: "stripe",
               request: stripe_req, save_card: true, user: user)
      }.to change(Payments::PaymentMethod, :count).by(1)

      pm = Payments::PaymentMethod.find_by!(psp_payment_method_id: "pending:pi_save_1")
      expect(pm.user_id).to eq(user.id)
      expect(pm.psp_customer_id).to eq("cus_save_1")
      expect(pm.provider).to eq("stripe")
      expect(pm).not_to be_chargeable
    end

    it "does not insert a vault row when save_card is false" do
      allow(Payments::Gateway).to receive(:charge).and_return(
        prepay_payload: { client_secret: "sec" },
        psp_transaction_id: "pi_nosave",
        psp_customer_id: "cus_nosave"
      )

      expect {
        charge(order: stripe_order("sc-nosave"), provider: "stripe",
               request: stripe_req, save_card: false, user: user)
      }.not_to change(Payments::PaymentMethod, :count)
    end
  end
end
