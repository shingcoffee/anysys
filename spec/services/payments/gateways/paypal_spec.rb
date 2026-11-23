# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Gateways::Paypal do
  subject(:gw) { described_class.new(account: account) }

  let(:account) do
    instance_double(Payments::MerchantAccount, mode: "sandbox", merchant_id: "PAYPAL_MERCHANT_ID").tap do |a|
      allow(a).to receive(:credential).with(:client_id).and_return("test_client_id")
      allow(a).to receive(:credential).with(:client_secret).and_return("test_client_secret")
      allow(a).to receive(:credential).with(:webhook_id).and_return("WH-TEST-123")
    end
  end
  let(:sandbox_base) { "https://api-m.sandbox.paypal.com" }

  def pin_payment_to_account(payment, merchant)
    payment.update!(prepay_payload: {
      Payments::Payment::ATTEMPT_CONTEXT_KEY => {
        "provider" => payment.provider, "merchant_account_id" => merchant.id,
        "merchant_id" => merchant.merchant_id, "mode" => merchant.mode
      }
    })
  end


  # Stub OAuth token for all tests that make API calls.
  before do
    stub_request(:post, "#{sandbox_base}/v1/oauth2/token")
      .to_return(
        status: 200,
        body: { access_token: "test_bearer_token", expires_in: 32400 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it_behaves_like "a registered payment gateway", key: "paypal"

  it "is also accessible as Payments::Gateways::PayPal" do
    expect(Payments::Gateways::PayPal).to eq(described_class)
  end

  describe "class declarations" do
    it "declares card-only supported flows" do
      expect(described_class.supported_flows).to eq(%i[card])
    end

    it "declares one_time, refunds, webhooks capabilities (no tokenized_cards)" do
      expect(described_class.capabilities).to contain_exactly(:one_time, :refunds, :webhooks)
      expect(described_class.capabilities).not_to include(:tokenized_cards)
    end

    it "declares a set of western supported currencies including usd" do
      expect(described_class.supported_currencies).to include("usd", "eur", "gbp", "jpy", "cad")
    end

    it "declares three credential fields" do
      names = described_class.credential_fields.map { |f| f[:name] }
      expect(names).to contain_exactly(:client_id, :client_secret, :webhook_id)
    end

    it "marks client_secret as encrypted, client_id and webhook_id as plain" do
      fields_by_name = described_class.credential_fields.index_by { |f| f[:name] }
      expect(fields_by_name[:client_secret][:encrypted]).to be(true)
      expect(fields_by_name[:client_id][:encrypted]).to be(false)
      expect(fields_by_name[:webhook_id][:encrypted]).to be(false)
    end

    it "returns the checkout_widget descriptor" do
      widget = described_class.checkout_widget
      expect(widget[:controller]).to eq("payments--paypal-buttons")
      expect(widget[:value_keys]).to eq(%i[client_id paypal_order_id currency])
      expect(widget[:renders_pay_button]).to be(false)
      expect(widget[:supports_save_card]).to be(false)
      expect(widget[:secured_by]).to eq("PayPal")
    end
  end

  describe ".extract_merchant_id" do
    it "reads from resource.custom_id (direct capture)" do
      body = { "resource" => { "custom_id" => "MERCH_99" } }.to_json
      expect(described_class.extract_merchant_id({}, body)).to eq("MERCH_99")
    end

    it "falls back to purchase_units[0].custom_id" do
      body = { "resource" => { "purchase_units" => [{ "custom_id" => "MERCH_88" }] } }.to_json
      expect(described_class.extract_merchant_id({}, body)).to eq("MERCH_88")
    end

    it "rejects malformed JSON with a controlled notification error" do
      expect { described_class.extract_merchant_id({}, "not-json") }.to raise_error(Payments::Errors::SignatureInvalid)
    end

    ["null", "[]", '{"resource":[]}', '{"resource":{"purchase_units":{}}}', '{"resource":{"links":[[]]}}'].each do |body|
      it "rejects malformed routing containers: #{body}" do
        expect { described_class.extract_merchant_id({}, body) }.to raise_error(Payments::Errors::SignatureInvalid)
      end
    end

    it "returns nil when neither field is present" do
      expect(described_class.extract_merchant_id({}, "{}")).to be_nil
    end

    it "resolves the tenant via the disputed capture id when custom_id is absent" do
      customer = create(:customer)
      Current.customer = customer
      order = create(:payment_order, external_ref: "pp-route", amount: 5.00, subject: "s")
      payment = create(:payment, payment_order: order, provider: "paypal", flow: "card",
             out_trade_no: "pp-route-ot", amount: 5.00,
             status: "succeeded", psp_transaction_id: "CAP-ROUTE")
      acc = create(:payment_merchant_account, :paypal, mode: "sandbox",
                    merchant_id: "PP-MID-1", status: "active")
      pin_payment_to_account(payment, acc)

      body = { "event_type" => "CUSTOMER.DISPUTE.CREATED",
               "resource" => { "dispute_id" => "D1",
                               "disputed_transactions" => [{ "seller_transaction_id" => "CAP-ROUTE" }] } }.to_json

      expect(described_class.extract_merchant_id({}, body)).to eq(acc.merchant_id)
    end

    it "uses the committed historical account rather than today's environment mode" do
      customer = create(:customer)
      Current.customer = customer
      order = create(:payment_order, external_ref: "pp-mode-route", amount: 5.00, subject: "s")
      payment = create(:payment, payment_order: order, provider: "paypal", flow: "card",
             out_trade_no: "pp-mode-route-ot", amount: 5.00,
             status: "succeeded", psp_transaction_id: "CAP-MODE-ROUTE")

      create(:payment_merchant_account, :paypal, :production, customer: customer,
             merchant_id: "PP-PROD-MID", status: "active")
      sandbox_acc = create(:payment_merchant_account, :paypal, customer: customer,
                            mode: "sandbox", merchant_id: "PP-SANDBOX-MID", status: "active")
      pin_payment_to_account(payment, sandbox_acc)
      sandbox_acc.update!(status: "disabled")
      allow(Rails.env).to receive(:production?).and_return(true)

      body = { "event_type" => "CUSTOMER.DISPUTE.CREATED",
               "resource" => { "dispute_id" => "D2",
                               "disputed_transactions" => [{ "seller_transaction_id" => "CAP-MODE-ROUTE" }] } }.to_json

      expect(described_class.extract_merchant_id({}, body)).to eq(sandbox_acc.merchant_id)
    end

    context "native refund notifications without custom_id" do
      let(:customer) { create(:customer) }
      let!(:merchant) { create(:payment_merchant_account, :paypal, customer: customer, merchant_id: "PP-REFUND-MID") }
      let!(:payment) do
        create(:payment, customer: customer, provider: "paypal", psp_transaction_id: "CAP-REFUND",
               payment_order: create(:payment_order, customer: customer, currency: "USD"))
          .tap { |record| pin_payment_to_account(record, merchant) }
      end
      let!(:refund) do
        create(:payment_refund, customer: customer, payment: payment, out_refund_no: "rf-paypal-route", psp_refund_id: "REFUND-LOCAL")
      end

      def refund_body(resource)
        { id: "WH-REFUND", event_type: "PAYMENT.CAPTURE.REFUNDED", resource: resource }.to_json
      end

      it "routes an early refund by its invoice_id before its PSP id is stored" do
        refund.update!(psp_refund_id: nil)
        body = refund_body(id: "REFUND-EARLY", invoice_id: refund.out_refund_no,
                           amount: { currency_code: "USD", value: "1.00" }, status: "COMPLETED")
        expect(described_class.extract_merchant_id({}, body)).to eq(merchant.merchant_id)
      end

      it "routes a refund by its previously stored PSP refund id" do
        expect(described_class.extract_merchant_id({}, refund_body(id: refund.psp_refund_id))).to eq(merchant.merchant_id)
      end

      it "routes by the Refund representation's up link without fetching an unverified URL" do
        body = refund_body(id: "REFUND-UNRECORDED", links: [
          { rel: "self", href: "https://api.paypal.com/v2/payments/refunds/REFUND-UNRECORDED" },
          { rel: "up", href: "https://api.paypal.com/v2/payments/captures/CAP-REFUND" }
        ])
        expect(described_class.extract_merchant_id({}, body)).to eq(merchant.merchant_id)
        expect(a_request(:any, /paypal/)).not_to have_been_made
      end

      it "routes the supplementary capture linkage" do
        body = refund_body(id: "REFUND-UNRECORDED", supplementary_data: { related_ids: { capture_id: "CAP-REFUND" } })
        expect(described_class.extract_merchant_id({}, body)).to eq(merchant.merchant_id)
      end

      it "does not route a PayPal notification through a different provider's refund" do
        payment.update!(provider: "stripe")
        expect(described_class.extract_merchant_id({}, refund_body(id: refund.psp_refund_id, invoice_id: refund.out_refund_no))).to be_nil
      end

      it "retains historical refund routing when the merchant disables new charges" do
        merchant.update!(status: "disabled")
        create(:payment_merchant_account, :paypal, :production, customer: customer, merchant_id: "PP-CURRENT-PRODUCTION")
        allow(Rails.env).to receive(:production?).and_return(true)
        expect(described_class.extract_merchant_id({}, refund_body(id: refund.psp_refund_id))).to eq(merchant.merchant_id)
      end
    end
  end

  describe "#charge" do
    let(:order)   { instance_double(Payments::Order, amount: 20.00, currency: "usd", subject: "Order #1") }
    let(:payment) { instance_double(Payments::Payment, out_trade_no: "PP-OT-1") }

    it "creates a CAPTURE-intent Order and returns paypal_order_id in prepay_payload" do
      stub_request(:post, "#{sandbox_base}/v2/checkout/orders")
        .to_return(
          status: 201,
          body: { id: "ORDER-123", status: "CREATED" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      res = gw.charge(order: order, payment: payment, flow: :card)
      expect(res[:prepay_payload]).to include(
        paypal_order_id: "ORDER-123",
        client_id:       "test_client_id",
        currency:        "USD",
        intent:          "capture"
      )
    end

    it "stamps invoice_id and custom_id in the request body" do
      captured = nil
      stub_request(:post, "#{sandbox_base}/v2/checkout/orders")
        .with { |req| captured = req; true }
        .to_return(status: 201, body: { id: "ORDER-456", status: "CREATED" }.to_json)

      gw.charge(order: order, payment: payment, flow: :card)
      body = JSON.parse(captured.body)
      unit = body["purchase_units"].first
      expect(unit["invoice_id"]).to eq("PP-OT-1")
      expect(unit["custom_id"]).to eq("PAYPAL_MERCHANT_ID")
      # PayPal-Request-Id keyed on our out_trade_no makes create-order idempotent.
      expect(captured.headers["Paypal-Request-Id"]).to eq("PP-OT-1")
    end

    it "sends Bearer Authorization header" do
      captured = nil
      stub_request(:post, "#{sandbox_base}/v2/checkout/orders")
        .with { |req| captured = req; true }
        .to_return(status: 201, body: { id: "ORDER-789", status: "CREATED" }.to_json)

      gw.charge(order: order, payment: payment, flow: :card)
      expect(captured.headers["Authorization"]).to eq("Bearer test_bearer_token")
    end

    it "formats zero-decimal JPY amounts without decimal point" do
      jpy_order = instance_double(Payments::Order, amount: 5.00, currency: "jpy", subject: "JPY Order")
      captured = nil
      stub_request(:post, "#{sandbox_base}/v2/checkout/orders")
        .with { |req| captured = req; true }
        .to_return(status: 201, body: { id: "ORDER-JPY", status: "CREATED" }.to_json)

      gw.charge(order: jpy_order, payment: payment, flow: :card)
      # zero-decimal: 500 cents / 100 = 5 yen (no fractional)
      body = JSON.parse(captured.body)
      expect(body["purchase_units"].first["amount"]["value"]).to eq("5")
      expect(body["purchase_units"].first["amount"]["currency_code"]).to eq("JPY")
    end

    it "accepts and ignores save_card: true (no vaulting)" do
      stub_request(:post, "#{sandbox_base}/v2/checkout/orders")
        .to_return(status: 201, body: { id: "ORDER-SC", status: "CREATED" }.to_json)

      expect {
        gw.charge(order: order, payment: payment, flow: :card, save_card: true)
      }.not_to raise_error
    end
  end

  describe "#query" do
    let(:payment) { instance_double(Payments::Payment, psp_transaction_id: nil,
                                    prepay_payload: { "paypal_order_id" => "ORDER-Q1" },
                                    out_trade_no: "PP-OT-Q1") }

    it "returns :succeeded for COMPLETED order" do
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1")
        .to_return(status: 200, body: {
          status: "COMPLETED",
          purchase_units: [{ payments: { captures: [{ id: "CAPTURE-1" }] } }]
        }.to_json)

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:succeeded)
      expect(res[:psp_transaction_id]).to eq("CAPTURE-1")
    end

    it "captures an APPROVED order server-side and returns :succeeded on COMPLETED capture" do
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1")
        .to_return(status: 200, body: { status: "APPROVED" }.to_json)

      stub_request(:post, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1/capture")
        .to_return(status: 201, body: {
          status: "COMPLETED",
          purchase_units: [{ payments: { captures: [{ id: "CAPTURE-APPROVED" }] } }]
        }.to_json)

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:succeeded)
      expect(res[:psp_transaction_id]).to eq("CAPTURE-APPROVED")
    end

    it "sends a PayPal-Request-Id keyed on the payment's out_trade_no for the server-side capture (M5)" do
      capture_payment = instance_double(Payments::Payment, psp_transaction_id: nil,
                                        prepay_payload: { "paypal_order_id" => "ORDER-Q1" },
                                        out_trade_no: "PP-OT-CAPTURE-1")
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1")
        .to_return(status: 200, body: { status: "APPROVED" }.to_json)

      captured = nil
      stub_request(:post, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1/capture")
        .with { |req| captured = req; true }
        .to_return(status: 201, body: {
          status: "COMPLETED",
          purchase_units: [{ payments: { captures: [{ id: "CAPTURE-APPROVED" }] } }]
        }.to_json)

      gw.query(payment: capture_payment)

      expect(captured.headers["Paypal-Request-Id"]).to eq("PP-OT-CAPTURE-1-capture")
    end

    it "returns :pending when APPROVED capture result is not COMPLETED" do
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1")
        .to_return(status: 200, body: { status: "APPROVED" }.to_json)

      stub_request(:post, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1/capture")
        .to_return(status: 200, body: { status: "PENDING" }.to_json)

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:pending)
    end

    it "returns :closed for VOIDED order" do
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1")
        .to_return(status: 200, body: { status: "VOIDED" }.to_json)

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:closed)
    end

    it "returns :pending for CREATED order (not yet approved)" do
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1")
        .to_return(status: 200, body: { status: "CREATED" }.to_json)

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:pending)
    end

    it "prefers prepay_payload order id over psp_transaction_id (capture id must not become order id)" do
      # After capture, psp_transaction_id holds the CAPTURE id. A later reconcile query
      # must still use the ORDER id — GET /v2/checkout/orders/<capture_id> would 404.
      paid_payment = instance_double(Payments::Payment, psp_transaction_id: "CAP-ALREADY-STORED",
                                     prepay_payload: { "paypal_order_id" => "ORDER-CORRECT" })
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-CORRECT")
        .to_return(status: 200, body: { status: "COMPLETED",
                                        purchase_units: [{ payments: { captures: [{ id: "CAP-ALREADY-STORED" }] } }] }.to_json)

      res = gw.query(payment: paid_payment)
      expect(res[:status]).to eq(:succeeded)
      # The ORDER id endpoint was hit (not the capture id).
      expect(a_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-CORRECT")).to have_been_made
      expect(a_request(:get, "#{sandbox_base}/v2/checkout/orders/CAP-ALREADY-STORED")).not_to have_been_made
    end

    it "falls back to psp_transaction_id when prepay_payload carries no order id" do
      # Defensive fallback in case prepay_payload is absent or old.
      fallback_payment = instance_double(Payments::Payment, psp_transaction_id: "ORDER-FALLBACK",
                                          prepay_payload: {})
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-FALLBACK")
        .to_return(status: 200, body: { status: "CREATED" }.to_json)

      res = gw.query(payment: fallback_payment)
      expect(res[:status]).to eq(:pending)
      expect(a_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-FALLBACK")).to have_been_made
    end

    it "returns capture amount/currency/time rather than purchase-unit totals" do
      stub_request(:get, "#{sandbox_base}/v2/checkout/orders/ORDER-Q1").to_return(status: 200, body: {
        status: "COMPLETED", purchase_units: [{
          amount: { value: "99.00", currency_code: "USD" },
          payments: { captures: [{ id: "CAP-NATIVE", amount: { value: "1000", currency_code: "JPY" },
                                  create_time: "2026-10-10T15:30:00Z" }] }
        }]
      }.to_json)

      expect(gw.query(payment: payment)).to include(currency: "JPY", amount: BigDecimal("1000"), settled_at: Time.utc(2026, 10, 10, 15, 30))
    end
  end

  describe "#refund" do
    let(:order)   { instance_double(Payments::Order, currency: "usd") }
    let(:payment) do
      instance_double(Payments::Payment, psp_transaction_id: "CAPTURE-R1", payment_order: order)
    end
    let(:refund_obj) { instance_double("Payments::Refund", amount: 5.00, out_refund_no: "rf-pp-1") }

    it "posts to the captures refund endpoint and returns psp_refund_id" do
      stub_request(:post, "#{sandbox_base}/v2/payments/captures/CAPTURE-R1/refund")
        .to_return(status: 201, body: { id: "REFUND-1", status: "COMPLETED" }.to_json)

      res = gw.refund(payment: payment, refund: refund_obj)
      expect(res[:psp_refund_id]).to eq("REFUND-1")
      expect(res[:status]).to eq(:succeeded)
    end

    it "returns :processing when refund status is not COMPLETED" do
      stub_request(:post, "#{sandbox_base}/v2/payments/captures/CAPTURE-R1/refund")
        .to_return(status: 201, body: { id: "REFUND-2", status: "PENDING" }.to_json)

      res = gw.refund(payment: payment, refund: refund_obj)
      expect(res[:status]).to eq(:processing)
    end

    it "formats the amount as a decimal string" do
      captured = nil
      stub_request(:post, "#{sandbox_base}/v2/payments/captures/CAPTURE-R1/refund")
        .with { |req| captured = req; true }
        .to_return(status: 201, body: { id: "REFUND-3", status: "COMPLETED" }.to_json)

      gw.refund(payment: payment, refund: refund_obj)
      body = JSON.parse(captured.body)
      expect(body["amount"]["value"]).to eq("5.00")
      expect(body["amount"]["currency_code"]).to eq("USD")
      expect(body["invoice_id"]).to eq("rf-pp-1")
      expect(body["custom_id"]).to eq("PAYPAL_MERCHANT_ID")
    end

    it "classifies an explicit invalid-parameter rejection as non-execution" do
      stub_request(:post, "#{sandbox_base}/v2/payments/captures/CAPTURE-R1/refund").to_return(status: 422, body: {
        name: "UNPROCESSABLE_ENTITY", details: [{ issue: "INVALID_PARAMETER_VALUE", field: "/amount/value" }]
      }.to_json)
      expect { gw.refund(payment: payment, refund: refund_obj) }
        .to raise_error(Payments::Errors::ApiError) { |error| expect(error).to be_definitive }
    end

    it "does not assume non-execution from a duplicate-identity rejection" do
      stub_request(:post, "#{sandbox_base}/v2/payments/captures/CAPTURE-R1/refund").to_return(status: 422, body: {
        name: "UNPROCESSABLE_ENTITY", details: [{ issue: "DUPLICATE_INVOICE_ID" }]
      }.to_json)
      expect { gw.refund(payment: payment, refund: refund_obj) }
        .to raise_error(Payments::Errors::ApiError) { |error| expect(error).to be_uncertain }
    end
  end

  describe "#close" do
    let(:payment) { instance_double(Payments::Payment, psp_transaction_id: "CAPTURE-C1") }

    it "raises rather than pretending the PayPal order is voided" do
      expect {
        gw.close(payment: payment)
      }.to raise_error(Payments::Errors::ApiError, /cannot be voided/)
      expect(a_request(:any, /paypal/)).not_to have_been_made
    end
  end

  describe "#download_bill" do
    it "raises ApiError with unsupported message" do
      expect {
        gw.download_bill(bill_date: Date.today, bill_type: "trade")
      }.to raise_error(Payments::Errors::ApiError, /unsupported/)
    end
  end

  describe "#verify_notification" do
    let(:headers) do
      {
        "Paypal-Transmission-Id"   => "trans-id-123",
        "Paypal-Transmission-Time" => "2026-06-22T12:00:00Z",
        "Paypal-Cert-Url"          => "https://api.paypal.com/cert",
        "Paypal-Auth-Algo"         => "SHA256withRSA",
        "Paypal-Transmission-Sig"  => "sig123abc"
      }
    end
    let(:body) { { "event_type" => "PAYMENT.CAPTURE.COMPLETED", "resource" => { "id" => "CAP-VN-1" } }.to_json }

    it "returns parsed payload when PayPal reports SUCCESS" do
      stub_request(:post, "#{sandbox_base}/v1/notifications/verify-webhook-signature")
        .to_return(status: 200, body: { verification_status: "SUCCESS" }.to_json)

      result = gw.verify_notification(headers: headers, body: body)
      expect(result["event_type"]).to eq("PAYMENT.CAPTURE.COMPLETED")
    end

    it "raises SignatureInvalid when verification_status is not SUCCESS" do
      stub_request(:post, "#{sandbox_base}/v1/notifications/verify-webhook-signature")
        .to_return(status: 200, body: { verification_status: "FAILURE" }.to_json)

      expect {
        gw.verify_notification(headers: headers, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid, /bad signature/)
    end

    it "sends the webhook_id from credentials" do
      captured = nil
      stub_request(:post, "#{sandbox_base}/v1/notifications/verify-webhook-signature")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { verification_status: "SUCCESS" }.to_json)

      gw.verify_notification(headers: headers, body: body)
      body_json = JSON.parse(captured.body)
      expect(body_json["webhook_id"]).to eq("WH-TEST-123")
      expect(body_json["transmission_id"]).to eq("trans-id-123")
    end

    it "rejects a cert URL that does not end with .paypal.com" do
      bad_headers = headers.merge("Paypal-Cert-Url" => "https://evil.example.com/cert")
      expect {
        gw.verify_notification(headers: bad_headers, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid, /bad cert url/)
    end

    it "rejects a cert URL with .paypal.com.evil.com as host (suffix attack)" do
      bad_headers = headers.merge("Paypal-Cert-Url" => "https://paypal.com.evil.com/cert")
      expect {
        gw.verify_notification(headers: bad_headers, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid, /bad cert url/)
    end

    it "rejects an unparseable cert URL" do
      bad_headers = headers.merge("Paypal-Cert-Url" => "not a url ://")
      expect {
        gw.verify_notification(headers: bad_headers, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid, /bad cert url/)
    end

    it "accepts a valid .paypal.com cert URL without reaching the verify API" do
      # Only the valid-origin check should pass through to the API stub.
      stub_request(:post, "#{sandbox_base}/v1/notifications/verify-webhook-signature")
        .to_return(status: 200, body: { verification_status: "SUCCESS" }.to_json)

      expect {
        gw.verify_notification(headers: headers, body: body)
      }.not_to raise_error
    end

    ["null", "[]", '{"resource":[]}'].each do |payload|
      it "rejects an invalid event shape before the signature postback: #{payload}" do
        expect { gw.verify_notification(headers: headers, body: payload) }.to raise_error(Payments::Errors::SignatureInvalid)
        expect(a_request(:post, "#{sandbox_base}/v1/notifications/verify-webhook-signature")).not_to have_been_made
      end
    end
  end

  describe "#ping" do
    it "returns ok: true when OAuth token succeeds" do
      res = gw.ping
      expect(res[:ok]).to be(true)
      expect(res[:message]).to include("Connected to PayPal")
    end

    it "returns ok: false on ApiError (bad credentials)" do
      stub_request(:post, "#{sandbox_base}/v1/oauth2/token")
        .to_return(status: 401, body: { error: "invalid_client" }.to_json)

      res = gw.ping
      expect(res[:ok]).to be(false)
      expect(res[:message]).to include("PayPal API error")
    end

    it "returns ok: false on network error" do
      stub_request(:post, "#{sandbox_base}/v1/oauth2/token")
        .to_raise(Errno::ECONNREFUSED)

      res = gw.ping
      expect(res[:ok]).to be(false)
      expect(res[:message]).to include("Network error")
    end
  end

  describe "tokenization API — not implemented" do
    it "raises NotImplementedError for subscribe" do
      sub = instance_double("Payments::Subscription")
      expect { gw.subscribe(subscription: sub) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for vault_card" do
      user = instance_double("User")
      expect { gw.vault_card(user: user, return_url: "/") }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for charge_token" do
      order = instance_double(Payments::Order)
      payment = instance_double(Payments::Payment)
      pm = instance_double(Payments::PaymentMethod)
      expect { gw.charge_token(order: order, payment: payment, payment_method: pm) }
        .to raise_error(NotImplementedError)
    end
  end

  describe "base checkout_widget default" do
    it "returns nil for redirect/QR gateways (base default)" do
      expect(Payments::Gateways::Alipay.checkout_widget).to be_nil
    end
  end

  describe "production base URL" do
    it "uses production endpoint when account.mode is 'production'" do
      prod_account = instance_double(Payments::MerchantAccount, mode: "production",
                                     merchant_id: "PROD_MERCH").tap do |a|
        allow(a).to receive(:credential).with(:client_id).and_return("prod_client_id")
        allow(a).to receive(:credential).with(:client_secret).and_return("prod_secret")
        allow(a).to receive(:credential).with(:webhook_id).and_return("WH-PROD-1")
      end
      prod_gw = described_class.new(account: prod_account)

      stub_request(:post, "https://api-m.paypal.com/v1/oauth2/token")
        .to_return(status: 200, body: { access_token: "prod_token" }.to_json)

      res = prod_gw.ping
      expect(res[:ok]).to be(true)
      expect(a_request(:post, "https://api-m.paypal.com/v1/oauth2/token")).to have_been_made
    end
  end
end
