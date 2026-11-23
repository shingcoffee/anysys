require "rails_helper"

RSpec.describe Payments::Gateway do
  let_it_be(:customer) { create(:customer) }
  let(:acc) do
    create(:payment_merchant_account, :alipay,
           mode: Rails.env.production? ? "production" : "sandbox",
           merchant_id: "2088", status: "active")
  end
  let(:order) { create(:payment_order, external_ref: "e", amount: 1.00, subject: "s") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "ot", amount: 1.00).tap { |record| pin_payment(record, acc) }
  end

  before do
    Current.customer = customer
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
  end

  def pin_payment(record, account, **attributes)
    context = { "provider" => record.provider, "merchant_account_id" => account.id,
                "merchant_id" => account.merchant_id, "mode" => account.mode }
    record.update!(prepay_payload: record.prepay_payload.merge(
      Payments::Payment::ATTEMPT_CONTEXT_KEY => context.merge(attributes.stringify_keys)
    ))
    record
  end


  it "delegates charge to the alipay gateway" do
    acc # materialize
    fake = instance_double(Payments::Gateways::Alipay, charge: { prepay_payload: { qr_code: "Q" } })
    allow(Payments::Gateways::Alipay).to receive(:new).with(account: acc).and_return(fake)
    result = described_class.charge(customer: customer, order: order, payment: payment, flow: :qr)
    expect(result[:prepay_payload][:qr_code]).to eq("Q")
  end

  it "raises CredentialsMissing when no active account" do
    unrelated_payment = Payments::Payment.new(customer_id: customer.id, payment_order: order, provider: "wechat_pay", flow: "qr",
                                              out_trade_no: "z", amount: 1.00)
    expect {
      described_class.charge(customer: customer, order: order, payment: unrelated_payment, flow: :qr)
    }.to raise_error(Payments::Errors::CredentialsMissing)
  end

  it "gateway_for_merchant resolves by payload merchant_id" do
    acc # materialize
    expect(described_class.gateway_for_merchant(provider: "alipay", merchant_id: "2088"))
      .to be_a(Payments::Gateways::Alipay)
  end

  it "gateway_for_merchant raises TenantNotFound for unknown merchant_id" do
    expect {
      described_class.gateway_for_merchant(provider: "alipay", merchant_id: "nope")
    }.to raise_error(Payments::Errors::TenantNotFound)
  end

  it "delegates query to the gateway" do
    acc
    fake = instance_double(Payments::Gateways::Alipay, query: { status: :succeeded })
    allow(Payments::Gateways::Alipay).to receive(:new).with(account: acc).and_return(fake)
    expect(described_class.query(customer: customer, payment: payment)).to eq(status: :succeeded)
  end

  describe "delegation to the resolved gateway" do
    before { acc } # materialize the active alipay account so CredentialResolver finds it

    # Stub Payments::Gateways::Alipay.new to return a verifying double with the
    # given methods, so we assert the facade forwards to the right gateway method.
    def stub_alipay(**methods)
      instance_double(Payments::Gateways::Alipay, **methods).tap do |fake|
        allow(Payments::Gateways::Alipay).to receive(:new).with(account: acc).and_return(fake)
      end
    end

    it "delegates refund" do
      stub_alipay(refund: { psp_refund_id: "r1" })
      expect(described_class.refund(customer: customer, payment: payment, refund: double)).to eq(psp_refund_id: "r1")
    end

    it "delegates close" do
      stub_alipay(close: { status: :closed })
      expect(described_class.close(customer: customer, payment: payment)).to eq(status: :closed)
    end

    it "delegates subscribe using subscription.provider" do
      stub_alipay(subscribe: { sign_url_or_params: "s" })
      sub = double("subscription", provider: "alipay", customer_id: customer.id, billing_owned?: false)
      expect(described_class.subscribe(customer: customer, subscription: sub)).to eq(sign_url_or_params: "s")
    end

    it "delegates cancel_subscription" do
      stub_alipay(cancel_subscription: { status: :cancelled })
      sub = double("subscription", provider: "alipay", customer_id: customer.id, billing_owned?: false)
      expect(described_class.cancel_subscription(customer: customer, subscription: sub)).to eq(status: :cancelled)
    end

    it "delegates charge_subscription" do
      stub_alipay(charge_subscription: { psp_transaction_id: "t1" })
      sub = double("subscription", provider: "alipay", customer_id: customer.id, billing_owned?: false)
      expect(described_class.charge_subscription(customer: customer, subscription: sub, payment: payment))
        .to eq(psp_transaction_id: "t1")
    end

    it "delegates download_bill using the explicit provider" do
      stub_alipay(download_bill: { csv: "a,b" })
      expect(described_class.download_bill(customer: customer, provider: "alipay",
                                           bill_date: Date.today, bill_type: "trade")).to eq(csv: "a,b")
    end

    it "delegates vault_card using the explicit provider" do
      stub_alipay(vault_card: { client_secret: "cs" })
      expect(described_class.vault_card(customer: customer, user: double, provider: "alipay",
                                        return_url: "/r")).to eq(client_secret: "cs")
    end

    it "delegates charge_token using payment_method.provider" do
      stub_alipay(charge_token: { psp_transaction_id: "ct" })
      pm = double("payment_method", provider: "alipay", customer_id: customer.id, billing_token?: false)
      expect(described_class.charge_token(customer: customer, order: order, payment: payment, payment_method: pm))
        .to eq(psp_transaction_id: "ct")
    end

    it "delegates detach_token using payment_method.provider" do
      stub_alipay(detach_token: { status: :removed })
      pm = double("payment_method", provider: "alipay", customer_id: customer.id, billing_token?: false)
      expect(described_class.detach_token(customer: customer, payment_method: pm)).to eq(status: :removed)
    end

    it "delegates fetch_payment_method using the explicit provider" do
      stub_alipay(fetch_payment_method: { brand: "visa" })
      expect(described_class.fetch_payment_method(customer: customer, provider: "alipay", psp_pm_id: "pm_1"))
        .to eq(brand: "visa")
    end
  end

  describe "#charge save_card forwarding (reflection branch)" do
    let(:stripe_acc) do
      create(:payment_merchant_account, provider: "stripe", mode: acc.mode,
             merchant_id: "acct_strp", status: "active",
             credentials: { secret_key: "sk_test", publishable_key: "pk_test",
                            webhook_signing_secret: "whsec" })
    end
    let(:stripe_payment) do
      create(:payment, payment_order: order, provider: "stripe", flow: "card",
              out_trade_no: "ot-strp", amount: 1.00).tap { |record| pin_payment(record, stripe_acc) }
    end

    before { Payments::PlatformGateway.for_provider("stripe").update!(available: true) }

    it "forwards save_card to gateways whose #charge accepts it (Stripe)" do
      stripe_acc
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi", client_secret: "cs" }.to_json)

      described_class.charge(customer: customer, order: order, payment: stripe_payment, flow: :card, save_card: true)
      expect(captured.body).to include("setup_future_usage=off_session")
    end

    it "does not forward user: to Alipay whose #charge does not declare it" do
      acc
      fake = instance_double(Payments::Gateways::Alipay)
      allow(fake).to receive(:charge).and_return(prepay_payload: { qr_code: "Q" })
      allow(Payments::Gateways::Alipay).to receive(:new).with(account: acc).and_return(fake)
      member = instance_double("User", id: 1, email: "m@example.com")

      described_class.charge(customer: customer, order: order, payment: payment,
                             flow: :qr, user: member)

      expect(fake).to have_received(:charge).with(
        order: order, payment: payment, flow: :qr, openid: nil
      )
    end
  end

  describe ".test_connection" do
    it "calls ping on the resolved account's gateway" do
      acc
      result = described_class.test_connection(customer: customer, provider: "alipay", mode: acc.mode)
      expect(result[:ok]).to be(true)
    end

    it "returns ok: false when no account row exists for (provider, mode)" do
      result = described_class.test_connection(customer: customer, provider: "alipay", mode: "production")
      expect(result[:ok]).to be(false)
      expect(result[:message]).to match(/No account row/)
    end

    it "returns ok: false when the provider is not a registered gateway" do
      acc
      allow(Payments::Gateways).to receive(:for).with("alipay").and_raise(ArgumentError.new("sk_live_secret_fragment"))
      result = described_class.test_connection(customer: customer, provider: "alipay", mode: acc.mode)
      expect(result[:ok]).to be(false)
      expect(result[:message]).to eq(I18n.t("comp_payments.test_connection.unknown_gateway"))
      expect(result[:message]).not_to include("sk_live_secret_fragment")
    end
  end

  describe "committed financial write identity" do
    it "never resolves a replacement active account after the activity's precheck" do
      payment
      acc.update!(status: "disabled")
      replacement = instance_double(Payments::MerchantAccount)
      allow(Payments::CredentialResolver).to receive(:call).and_return(replacement)
      expect(Payments::Gateways::Alipay).not_to receive(:new)

      expect { described_class.charge(customer: customer, order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::CredentialsMissing)
      expect { described_class.charge_token(customer: customer, order: order, payment: payment,
                                            payment_method: double(provider: "alipay")) }
        .to raise_error(Payments::Errors::CredentialsMissing)
      expect(Payments::CredentialResolver).not_to have_received(:call)
    end

    it "refuses a currently unavailable platform gateway before constructing the PSP client" do
      payment
      Payments::PlatformGateway.for_provider("alipay").update!(available: false)
      expect(Payments::Gateways::Alipay).not_to receive(:new)

      expect { described_class.charge(customer: customer, order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "does not replace an original merchant identity that changed on the same account row" do
      payment
      acc.update!(merchant_id: "changed-after-precheck")
      expect(Payments::Gateways::Alipay).not_to receive(:new)
      expect { described_class.charge(customer: customer, order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "rejects a saved mode mismatch instead of selecting today's other mode" do
      pin_payment(payment, acc, mode: "production")
      expect(Payments::Gateways::Alipay).not_to receive(:new)
      expect { described_class.charge(customer: customer, order: order, payment: payment, flow: :qr) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "rejects a token/provider mismatch before the PSP call" do
      expect(Payments::Gateways::Alipay).not_to receive(:new)
      expect { described_class.charge_token(customer: customer, order: order, payment: payment,
                                            payment_method: double(provider: "stripe")) }
        .to raise_error(Payments::Errors::TenantMismatch)
    end

    it "signs H5 using the original attempt IP even when the retry arrives from another network" do
      account = create(:payment_merchant_account, :wechat_pay, customer: customer, merchant_id: "wx-pinned-h5")
      Payments::PlatformGateway.for_provider("wechat_pay").update!(available: true)
      h5 = create(:payment, customer: customer, payment_order: order, provider: "wechat_pay", flow: "h5")
      pin_payment(h5, account, client_ip: "203.0.113.10")
      request = double("retry request")
      expect(request).not_to receive(:remote_ip)
      stub_request(:post, "https://api.mch.weixin.qq.com/v3/pay/transactions/h5")
        .with do |outbound|
          body = JSON.parse(outbound.body)
          body["mchid"] == account.merchant_id && body.dig("scene_info", "payer_client_ip") == "203.0.113.10"
        end
        .to_return(status: 200, body: { h5_url: "https://wx.tenpay.com/cashier" }.to_json)

      expect(described_class.charge(customer: customer, order: order, payment: h5, flow: :h5, request: request))
        .to include(prepay_payload: { h5_url: "https://wx.tenpay.com/cashier" })
    end

    it "retains pinned historical reads after account disablement and environment mode changes" do
      payment
      acc.update!(status: "disabled")
      allow(Payments::CredentialResolver).to receive(:default_mode).and_return("production")
      fake = instance_double(Payments::Gateways::Alipay, query: { status: :pending })
      allow(Payments::Gateways::Alipay).to receive(:new).with(account: acc).and_return(fake)

      expect(described_class.query(customer: customer, payment: payment)).to eq(status: :pending)
    end
  end
end
