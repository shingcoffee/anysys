# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Gateways::Base do
  subject(:gateway) { concrete_class.new(account: account) }

  let(:account) { double("account") }

  let(:concrete_class) do
    Class.new(described_class) do
      def self.key           = "test_gateway"
      def self.display_name  = "Test Gateway"

      def self.extract_merchant_id(_h, _b) = "merchant_123"

      # Expose protected HTTP helpers for testing
      def test_safe_json(str)             = safe_json(str)
      def test_http_post(url, body:, headers: {}) = http_post(url, body: body, headers: headers)
      def test_http_get(url, headers: {}) = http_get(url, headers: headers)
      def test_post_json(url, body:, headers: {}) = post_json(url, body: body, headers: headers)
      def test_get_json(url, headers: {}) = get_json(url, headers: headers)
      def test_ping_via(label, &blk)      = ping_via(label, &blk)
    end
  end


  describe "class-level interface" do
    it "raises NotImplementedError for .key on base class" do
      expect { described_class.key }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for .display_name on base class" do
      expect { described_class.display_name }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for .extract_merchant_id on base class" do
      expect { described_class.extract_merchant_id({}, "") }.to raise_error(NotImplementedError)
    end

    it ".credential_fields returns [] by default" do
      expect(described_class.credential_fields).to eq([])
    end

    it ".supported_flows returns [:qr, :h5, :jsapi] by default" do
      expect(described_class.supported_flows).to eq(%i[qr h5 jsapi])
    end

    it "defaults capabilities to one-time + refunds + webhooks" do
      expect(concrete_class.capabilities).to match_array(%i[one_time refunds webhooks])
    end

    it "defaults supported_currencies to CNY" do
      expect(concrete_class.supported_currencies).to eq(%w[cny])
    end

    it "knows zero-decimal currencies" do
      expect(concrete_class.zero_decimal_currency?("jpy")).to be(true)
      expect(concrete_class.zero_decimal_currency?("usd")).to be(false)
    end
  end

  describe "instance abstract methods" do
    let(:base)         { described_class.new(account: account) }
    let(:payment)      { double("payment") }
    let(:order)        { double("order") }
    let(:refund_obj)   { double("refund") }
    let(:subscription) { double("subscription") }

    it "raises NotImplementedError for #charge" do
      expect { base.charge(order: order, payment: payment, flow: :qr) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #query" do
      expect { base.query(payment: payment) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #refund" do
      expect { base.refund(payment: payment, refund: refund_obj) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #close" do
      expect { base.close(payment: payment) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #subscribe" do
      expect { base.subscribe(subscription: subscription) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #cancel_subscription" do
      expect { base.cancel_subscription(subscription: subscription) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #charge_subscription" do
      expect { base.charge_subscription(subscription: subscription, payment: payment) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #download_bill" do
      expect { base.download_bill(bill_date: "2024-01-01", bill_type: "trade") }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #verify_notification" do
      expect { base.verify_notification(headers: {}, body: "") }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for tokenization methods by default" do
      expect { base.vault_card(user: nil, return_url: "x") }.to raise_error(NotImplementedError)
      expect { base.charge_token(order: nil, payment: nil, payment_method: nil) }.to raise_error(NotImplementedError)
      expect { base.detach_token(payment_method: nil) }.to raise_error(NotImplementedError)
    end
  end

  describe "#safe_json" do
    it "parses valid JSON" do
      expect(gateway.test_safe_json('{"code":"0"}')).to eq({ "code" => "0" })
    end

    it "returns { 'raw' => str } on invalid JSON" do
      expect(gateway.test_safe_json("garbage")).to eq({ "raw" => "garbage" })
    end

    it "handles nil" do
      expect(gateway.test_safe_json(nil)).to eq({ "raw" => "" })
    end
  end

  describe "#post_json / #get_json" do
    it "parses a JSON POST response body" do
      stub_request(:post, "https://pay.example.com/charge")
        .to_return(status: 200, body: '{"ok":true,"id":"x1"}')
      expect(gateway.test_post_json("https://pay.example.com/charge", body: "{}"))
        .to eq({ "ok" => true, "id" => "x1" })
    end

    it "parses a JSON GET response body" do
      stub_request(:get, "https://pay.example.com/q")
        .to_return(status: 200, body: '{"status":"ok"}')
      expect(gateway.test_get_json("https://pay.example.com/q")).to eq({ "status" => "ok" })
    end

    ["null", "[]", "invalid-json"].each do |body|
      it "keeps an unusable write response uncertain: #{body}" do
        stub_request(:post, "https://pay.example.com/charge").to_return(status: 200, body: body)
        expect { gateway.test_post_json("https://pay.example.com/charge", body: "{}") }
          .to raise_error(Payments::Errors::TransportError)
      end
    end
  end

  describe "#ping_via" do
    it "returns ok when the probe succeeds" do
      res = gateway.test_ping_via("TestPSP") { true }
      expect(res[:ok]).to be(true)
      expect(res[:message]).to eq("Connected to TestPSP successfully.")
    end

    it "maps ApiError to a not-ok result" do
      res = gateway.test_ping_via("TestPSP") { raise Payments::Errors::ApiError.new("boom") }
      expect(res[:ok]).to be(false)
      expect(res[:message]).to eq("TestPSP API error.")
    end

    it "maps TransportError to a network-error result" do
      res = gateway.test_ping_via("TestPSP") { raise Payments::Errors::TransportError.new("down") }
      expect(res[:ok]).to be(false)
      expect(res[:message]).to eq("Network error.")
    end
  end

  describe "#http_post body encoding" do
    it "sends a String body as-is" do
      stub_request(:post, "https://pay.example.com/charge")
        .with(body: '{"amount":100}')
        .to_return(status: 200, body: '{"ok":true}')

      expect {
        gateway.test_http_post("https://pay.example.com/charge", body: '{"amount":100}')
      }.not_to raise_error
    end

    it "JSON-encodes a Hash body" do
      stub_request(:post, "https://pay.example.com/charge")
        .with(body: '{"amount":100}')
        .to_return(status: 200, body: '{"ok":true}')

      expect {
        gateway.test_http_post("https://pay.example.com/charge", body: { amount: 100 })
      }.not_to raise_error
    end
  end

  describe "#http_post — error responses" do
    it "raises ApiError on a 4xx response" do
      stub_request(:post, "https://pay.example.com/charge")
        .to_return(status: 400, body: '{"error":"bad request"}')

      expect {
        gateway.test_http_post("https://pay.example.com/charge", body: "{}")
      }.to raise_error(Payments::Errors::ApiError)
    end

    it "raises TransportError on connection timeout" do
      stub_request(:post, "https://pay.example.com/charge").to_timeout

      expect {
        gateway.test_http_post("https://pay.example.com/charge", body: "{}")
      }.to raise_error(Payments::Errors::TransportError)
    end

    [409, 429, 500, 503].each do |status|
      it "does not release financial idempotency after HTTP #{status}" do
        stub_request(:post, "https://pay.example.com/charge").to_return(status: status, body: '{"error":"retry"}')
        expect { gateway.test_http_post("https://pay.example.com/charge", body: "{}") }
          .to raise_error(Payments::Errors::TransportError)
      end
    end

    it "maps malformed gateway URL configuration without leaking raw transport exceptions" do
      expect { gateway.test_http_get("https://bad host/path") }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end
  end

  describe "#http_get — error responses" do
    it "raises ApiError on a 5xx response" do
      stub_request(:get, "https://pay.example.com/query")
        .to_return(status: 500, body: '{"error":"server error"}')

      expect {
        gateway.test_http_get("https://pay.example.com/query")
      }.to raise_error(Payments::Errors::ApiError)
    end
  end

  describe "#notify_url (shared webhook URL helper)" do
    let(:concrete_with_notify) do
      Class.new(described_class) do
        def self.key = "alipay" # any registered key so the route param is valid
        def expose_notify_url = notify_url
        def expose_result_url(payment) = result_url(payment)
      end
    end

    it "returns the per-account override when present" do
      account = double("account", notify_url_override: "https://tenant.example.com/hook")
      gw = concrete_with_notify.new(account: account)
      expect(gw.expose_notify_url).to eq("https://tenant.example.com/hook")
    end

    it "builds the canonical webhook route from the gateway key when override is blank" do
      account = double("account", notify_url_override: nil)
      gw = concrete_with_notify.new(account: account)
      expect(gw.expose_notify_url).to include("/payments/webhooks/alipay")
    end

    it "uses the application's parsed secure canonical origin for callback and shopper return URLs" do
      allow(Rails.application).to receive(:default_url_options).and_return(
        host: "payments.example.test", protocol: "https", port: 8443
      )
      account = double("account", notify_url_override: nil)
      gw = concrete_with_notify.new(account: account)
      payment = double(customer_id: 12_345_678, out_trade_no: "trade-1")

      expect(gw.expose_notify_url).to eq("https://payments.example.test:8443/payments/webhooks/alipay")
      expect(gw.expose_result_url(payment)).to eq("https://payments.example.test:8443/12345678/payments/result/trade-1")
    end

    it "fails closed on missing production origin instead of generating localhost links" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.application).to receive(:default_url_options).and_return(host: nil, protocol: "https")
      gw = concrete_with_notify.new(account: double(notify_url_override: nil))
      expect { gw.expose_notify_url }.to raise_error(Payments::Errors::CredentialsMissing)
    end
  end

  describe "#ping (default no-op)" do
    it "reports an assumed-OK connection for gateways without a ping endpoint" do
      base = described_class.new(account: account)
      res = base.ping
      expect(res[:ok]).to be(true)
      expect(res[:message]).to match(/no ping endpoint/i)
      expect(res[:verified_at]).to be_present
    end
  end

  describe "historical webhook credentials" do
    it "verifies a disabled account's webhook while refusing new charges with its credentials" do
      customer = create(:customer)
      account = create(:payment_merchant_account, :stripe, customer: customer,
                       merchant_id: "disabled-history", status: "disabled",
                       credentials: { webhook_signing_secret: "whsec_history" })
      body = { data: { object: { metadata: { merchant_id: account.merchant_id } } } }.to_json
      timestamp = Time.current.to_i
      signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec_history", "#{timestamp}.#{body}")

      gw = Payments::Gateway.gateway_for_merchant(provider: "stripe", merchant_id: account.merchant_id)
      expect(gw.verify_notification(headers: { "Stripe-Signature" => "t=#{timestamp},v1=#{signature}" }, body: body))
        .to eq(JSON.parse(body))
      expect { Payments::CredentialResolver.call(customer: customer, provider: "stripe") }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "pins settlement credentials to the committed merchant identity, including a disabled account" do
      customer = create(:customer)
      account = create(:payment_merchant_account, :stripe, customer: customer, status: "disabled")
      payment = create(:payment, customer: customer, provider: "stripe", prepay_payload: {
        Payments::Payment::ATTEMPT_CONTEXT_KEY => {
          "provider" => "stripe", "merchant_account_id" => account.id, "merchant_id" => account.merchant_id, "mode" => account.mode
        }
      })
      expect(Payments::CredentialResolver.for_payment(customer: customer, payment: payment)).to eq(account)

      account.update!(merchant_id: "replacement-merchant")
      expect(Payments::CredentialResolver.for_payment(customer: customer, payment: payment)).to eq(account)
      expect { Payments::CredentialResolver.for_payment(customer: customer, payment: payment, historical: false) }
        .to raise_error(Payments::Errors::CredentialsMissing)
      expect { Payments::CredentialResolver.for_payment(customer: create(:customer), payment: payment) }
        .to raise_error(Payments::Errors::TenantMismatch)
    end
  end
end
