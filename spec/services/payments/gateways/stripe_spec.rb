# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Gateways::Stripe do
  subject(:gw) { described_class.new(account: account) }

  let(:account) do
    instance_double(Payments::MerchantAccount, mode: "sandbox", merchant_id: "acct_1",
      credential: nil).tap do |a|
      allow(a).to receive(:credential).with(:secret_key).and_return("sk_test_x")
      allow(a).to receive(:credential).with(:publishable_key).and_return("pk_test_x")
      allow(a).to receive(:credential).with(:webhook_signing_secret).and_return("whsec_x")
    end
  end

  def pin_payment_to_account(payment, merchant)
    payment.update!(prepay_payload: {
      Payments::Payment::ATTEMPT_CONTEXT_KEY => {
        "provider" => payment.provider, "merchant_account_id" => merchant.id,
        "merchant_id" => merchant.merchant_id, "mode" => merchant.mode
      }
    })
  end

  it_behaves_like "a registered payment gateway", key: "stripe"

  describe "class declarations" do
    it "declares card-only supported flows" do
      expect(described_class.supported_flows).to eq(%i[card])
    end

    it "declares card capabilities" do
      expect(described_class.capabilities).to include(:tokenized_cards, :recurring, :one_time)
    end

    it "declares a broad set of supported currencies including usd" do
      expect(described_class.supported_currencies).to include("usd", "eur", "gbp", "jpy", "cny")
    end

    it "declares the three credential fields" do
      names = described_class.credential_fields.map { |f| f[:name] }
      expect(names).to contain_exactly(:secret_key, :publishable_key, :webhook_signing_secret)
    end

    it "marks secret_key and webhook_signing_secret as encrypted" do
      fields_by_name = described_class.credential_fields.index_by { |f| f[:name] }
      expect(fields_by_name[:secret_key][:encrypted]).to be(true)
      expect(fields_by_name[:webhook_signing_secret][:encrypted]).to be(true)
      expect(fields_by_name[:publishable_key][:encrypted]).to be(false)
    end
  end

  describe ".checkout_widget" do
    it "returns the Stripe Payment Element widget descriptor" do
      widget = described_class.checkout_widget
      expect(widget[:controller]).to eq("payments--stripe-card")
      expect(widget[:value_keys]).to eq(%i[publishable_key client_secret])
      expect(widget[:renders_pay_button]).to be(true)
      expect(widget[:supports_save_card]).to be(true)
      expect(widget[:secured_by]).to eq("Stripe")
    end
  end

  describe ".extract_merchant_id" do
    it "reads from data.object.metadata.merchant_id" do
      body = { "data" => { "object" => { "metadata" => { "merchant_id" => "acct_99" } } } }.to_json
      expect(described_class.extract_merchant_id({}, body)).to eq("acct_99")
    end

    it "falls back to account field for Connect events" do
      body = { "account" => "acct_connect", "data" => { "object" => {} } }.to_json
      expect(described_class.extract_merchant_id({}, body)).to eq("acct_connect")
    end

    it "falls back to merchant_account_id metadata" do
      body = { "data" => { "object" => { "metadata" => { "merchant_account_id" => "acct_meta" } } } }.to_json
      expect(described_class.extract_merchant_id({}, body)).to eq("acct_meta")
    end

    it "returns nil when neither field is present" do
      expect(described_class.extract_merchant_id({}, "{}")).to be_nil
    end

    it "rejects malformed JSON with a controlled notification error" do
      expect { described_class.extract_merchant_id({}, "not-json") }.to raise_error(Payments::Errors::SignatureInvalid)
    end

    ["null", "[]", '{"data":[]}', '{"data":{"object":[]}}', '{"data":{"object":{"metadata":[]}}}'].each do |body|
      it "rejects malformed routing containers: #{body}" do
        expect { described_class.extract_merchant_id({}, body) }.to raise_error(Payments::Errors::SignatureInvalid)
      end
    end

    # Real direct (non-Connect) Stripe webhooks for charge.dispute.* and
    # refund.updated carry NO top-level `account` field and the Dispute/Refund
    # object's own `metadata` is always empty (we only ever stamp metadata on
    # PaymentIntent/SetupIntent/Customer). Without a fallback these events
    # resolve merchant_id => nil and 404 at the dispatcher (H2 bug).
    it "resolves the tenant from the disputed PaymentIntent id when metadata and account are absent" do
      customer = create(:customer)
      Current.customer = customer
      order = create(:payment_order, external_ref: "st-dispute-route", amount: 5.00, subject: "s")
      payment = create(:payment, payment_order: order, provider: "stripe", flow: "card",
             out_trade_no: "st-dispute-route-ot", amount: 5.00,
             status: "succeeded", psp_transaction_id: "pi_route_1")
      acc = create(:payment_merchant_account, :stripe, customer: customer,
                    mode: "sandbox", merchant_id: "acct_route_1", status: "active")
      pin_payment_to_account(payment, acc)

      body = {
        "type" => "charge.dispute.created",
        "data" => { "object" => { "id" => "dp_1", "payment_intent" => "pi_route_1", "metadata" => {} } }
      }.to_json

      expect(described_class.extract_merchant_id({}, body)).to eq(acc.merchant_id)
    end

    it "resolves the tenant from the refunded PaymentIntent id when metadata and account are absent" do
      customer = create(:customer)
      Current.customer = customer
      order = create(:payment_order, external_ref: "st-refund-route", amount: 5.00, subject: "s")
      payment = create(:payment, payment_order: order, provider: "stripe", flow: "card",
             out_trade_no: "st-refund-route-ot", amount: 5.00,
             status: "succeeded", psp_transaction_id: "pi_route_2")
      acc = create(:payment_merchant_account, :stripe, customer: customer,
                    mode: "sandbox", merchant_id: "acct_route_2", status: "active")
      pin_payment_to_account(payment, acc)

      body = {
        "type" => "refund.updated",
        "data" => { "object" => { "id" => "re_1", "payment_intent" => "pi_route_2", "metadata" => {} } }
      }.to_json

      expect(described_class.extract_merchant_id({}, body)).to eq(acc.merchant_id)
    end

    it "returns nil when the referenced payment_intent has no matching local payment" do
      body = {
        "type" => "charge.dispute.created",
        "data" => { "object" => { "id" => "dp_ghost", "payment_intent" => "pi_ghost", "metadata" => {} } }
      }.to_json

      expect(described_class.extract_merchant_id({}, body)).to be_nil
    end

    it "routes to the saved historical account even if environment mode has changed" do
      customer = create(:customer)
      Current.customer = customer
      order = create(:payment_order, external_ref: "st-mode-route", amount: 5.00, subject: "s")
      payment = create(:payment, payment_order: order, provider: "stripe", flow: "card",
             out_trade_no: "st-mode-route-ot", amount: 5.00,
             status: "succeeded", psp_transaction_id: "pi_mode_route")

      create(:payment_merchant_account, :stripe, :production, customer: customer,
             merchant_id: "acct_prod_mode", status: "active")
      sandbox_acc = create(:payment_merchant_account, :stripe, customer: customer,
                            mode: "sandbox", merchant_id: "acct_sandbox_mode", status: "active")
      pin_payment_to_account(payment, sandbox_acc)
      sandbox_acc.update!(status: "disabled")
      allow(Rails.env).to receive(:production?).and_return(true)

      body = {
        "type" => "charge.dispute.created",
        "data" => { "object" => { "id" => "dp_mode", "payment_intent" => "pi_mode_route", "metadata" => {} } }
      }.to_json

      expect(described_class.extract_merchant_id({}, body)).to eq(sandbox_acc.merchant_id)
    end

    it "rejects an unbound old operation for offline repair rather than guessing today's account" do
      customer = create(:customer)
      create(:payment_merchant_account, :stripe, customer: customer)
      create(:payment, customer: customer, provider: "stripe", psp_transaction_id: "pi_unpinned")
      body = { type: "refund.updated", data: { object: { payment_intent: "pi_unpinned" } } }.to_json
      expect { described_class.extract_merchant_id({}, body) }.to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "does not pick an arbitrary payment when the PSP operation correlation is ambiguous" do
      customer = create(:customer)
      merchant = create(:payment_merchant_account, :stripe, customer: customer)
      2.times do
        payment = create(:payment, customer: customer, provider: "stripe", psp_transaction_id: "pi_ambiguous")
        pin_payment_to_account(payment, merchant)
      end
      body = { type: "charge.dispute.created", data: { object: { payment_intent: "pi_ambiguous" } } }.to_json
      expect { described_class.extract_merchant_id({}, body) }.to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "authenticates an uncorrelated signed event using the official verifier rather than trusting its ID" do
      merchant = create(:payment_merchant_account, :stripe, customer: create(:customer), credentials: { webhook_signing_secret: "whsec_uncorrelated" })
      body = { id: "evt_unseen", type: "charge.dispute.created", data: { object: { id: "dp_unseen", payment_intent: "pi_unseen" } } }.to_json
      timestamp = Time.current.to_i
      signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec_uncorrelated", "#{timestamp}.#{body}")
      headers = { "Stripe-Signature" => "t=#{timestamp},v1=#{signature}" }

      expect(described_class.extract_merchant_id(headers, body)).to eq(merchant.merchant_id)
      expect { described_class.extract_merchant_id(headers.merge("Stripe-Signature" => "t=#{timestamp},v1=bad"), body) }
        .to raise_error(Payments::Errors::SignatureInvalid)
    end

    it "rejects ambiguity when two accounts share a signing secret" do
      2.times { create(:payment_merchant_account, :stripe, customer: create(:customer), credentials: { webhook_signing_secret: "whsec_shared" }) }
      body = { id: "evt_ambiguous", type: "charge.dispute.created", data: { object: { payment_intent: "pi_unseen" } } }.to_json
      timestamp = Time.current.to_i
      signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec_shared", "#{timestamp}.#{body}")
      expect { described_class.extract_merchant_id({ "Stripe-Signature" => "t=#{timestamp},v1=#{signature}" }, body) }
        .to raise_error(Payments::Errors::SignatureInvalid)
    end
  end

  describe "#charge" do
    let(:order)   { instance_double(Payments::Order, amount: 5.00, currency: "usd", external_ref: "r1", subject: "Test") }
    let(:payment) { instance_double(Payments::Payment, out_trade_no: "ch-1", psp_transaction_id: nil, prepay_payload: {}) }

    it "returns client_secret and publishable_key in prepay_payload" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .to_return(
          status: 200,
          body: { id: "pi_1", client_secret: "pi_1_secret", status: "requires_payment_method" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      res = gw.charge(order: order, payment: payment, flow: :card)
      expect(res[:prepay_payload]).to include(
        client_secret: "pi_1_secret",
        publishable_key: "pk_test_x"
      )
      expect(res[:psp_transaction_id]).to eq("pi_1")
    end

    it "sends form-encoded body with Bearer auth" do
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_1", client_secret: "secret", status: "requires_payment_method" }.to_json)

      gw.charge(order: order, payment: payment, flow: :card)
      expect(captured.headers["Authorization"]).to eq("Bearer sk_test_x")
      expect(captured.headers["Content-Type"]).to include("application/x-www-form-urlencoded")
      # Idempotency-Key keyed on our out_trade_no prevents a retry double-charge.
      expect(captured.headers["Idempotency-Key"]).to eq("ch-1")
      expect(captured.body).to include("amount=500")
      expect(captured.body).to include("currency=usd")
    end

    it "stamps merchant_id in metadata" do
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_1", client_secret: "secret", status: "requires_payment_method" }.to_json)

      gw.charge(order: order, payment: payment, flow: :card)
      # The stripe gem form-encodes nested params with literal brackets
      # (metadata[merchant_id]=...), unlike URI.encode_www_form's %5B/%5D.
      expect(captured.body).to include("metadata[merchant_id]=acct_1")
    end

    it "does not divide amount for zero-decimal currencies (jpy)" do
      jpy_order = instance_double(Payments::Order, amount: 5.00, currency: "jpy",
                                  external_ref: "r1", subject: "Test JPY")
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_1", client_secret: "secret", status: "requires_payment_method" }.to_json)

      gw.charge(order: jpy_order, payment: payment, flow: :card)
      # For zero-decimal jpy: 500 cents / 100 = 5 (smallest unit is 1 yen)
      expect(captured.body).to include("amount=5")
    end

    it "sets setup_future_usage=off_session when save_card is true" do
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_1", client_secret: "secret", status: "requires_payment_method" }.to_json)

      gw.charge(order: order, payment: payment, flow: :card, save_card: true)
      expect(captured.body).to include("setup_future_usage=off_session")
    end

    it "creates a Stripe Customer and attaches it to the PaymentIntent when save_card has a user" do
      user = instance_double("User", id: 9, email: "vault@example.com")
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/customers")
        .to_return(status: 200, body: { id: "cus_save" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_save", client_secret: "secret", status: "requires_payment_method" }.to_json)

      res = gw.charge(order: order, payment: payment, flow: :card, save_card: true, user: user)
      expect(res[:psp_customer_id]).to eq("cus_save")
      expect(captured.body).to include("customer=cus_save")
      expect(captured.body).to include("setup_future_usage=off_session")
    end

    it "omits setup_future_usage when save_card is false" do
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_1", client_secret: "secret", status: "requires_payment_method" }.to_json)

      gw.charge(order: order, payment: payment, flow: :card)
      expect(captured.body).not_to include("setup_future_usage")
    end

    it "replays identical save-card Customer/intent parameters even after the member edits their email" do
      user = double(id: 9, email: "before@example.com")
      customers = []
      intents = []
      stub_request(:post, "https://api.stripe.com/v1/customers")
        .with(headers: { "Idempotency-Key" => "ch-1-customer" })
        .with { |request| customers << request.body; true }
        .to_return(status: 200, body: { id: "cus_stable" }.to_json)
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with(headers: { "Idempotency-Key" => "ch-1" })
        .with { |request| intents << request.body; true }
        .to_return(status: 200, body: { id: "pi_stable", client_secret: "secret", customer: "cus_stable" }.to_json)

      first = gw.charge(order: order, payment: payment, flow: :card, save_card: true, user: user)
      allow(user).to receive(:email).and_return("after@example.com")
      second = described_class.new(account: account).charge(order: order, payment: payment, flow: :card, save_card: true, user: user)

      expect(customers.size).to eq(2)
      expect(customers.uniq.size).to eq(1)
      expect(intents.size).to eq(2)
      expect(intents.uniq.size).to eq(1)
      expect(intents.first).to include("customer=cus_stable")
      expect(first[:prepay_payload]).to include(psp_customer_id: "cus_stable", save_card: true)
      expect(second[:psp_customer_id]).to eq(first[:psp_customer_id])
    end

    it "retrieves the existing intent without recreating or changing its save-card request" do
      allow(payment).to receive(:psp_transaction_id).and_return("pi_existing")
      allow(payment).to receive(:prepay_payload).and_return("psp_customer_id" => "cus_existing", "save_card" => true)
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_existing").to_return(status: 200, body: {
        id: "pi_existing", client_secret: "existing_secret", customer: "cus_existing", setup_future_usage: "off_session"
      }.to_json)

      result = gw.charge(order: order, payment: payment, flow: :card, save_card: false)

      expect(result[:prepay_payload]).to include(client_secret: "existing_secret", psp_customer_id: "cus_existing", save_card: true)
      expect(a_request(:post, "https://api.stripe.com/v1/customers")).not_to have_been_made
      expect(a_request(:post, "https://api.stripe.com/v1/payment_intents")).not_to have_been_made
    end

    it "reuses the persisted Customer context after an ambiguous intent creation" do
      allow(payment).to receive(:prepay_payload).and_return("psp_customer_id" => "cus_persisted", "save_card" => true)
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |request| request.body.include?("customer=cus_persisted") && request.body.include?("setup_future_usage=off_session") }
        .to_return(status: 200, body: { id: "pi_retry", client_secret: "secret" }.to_json)

      gw.charge(order: order, payment: payment, flow: :card, save_card: false)

      expect(a_request(:post, "https://api.stripe.com/v1/customers")).not_to have_been_made
    end
  end

  describe "#charge_token" do
    let(:order)   { instance_double(Payments::Order, amount: 5.00, currency: "usd", external_ref: "r2", subject: "Sub") }
    let(:payment) { instance_double(Payments::Payment, out_trade_no: "ch-2") }
    let(:pm)      { instance_double(Payments::PaymentMethod, psp_customer_id: "cus_1", psp_payment_method_id: "pm_1") }

    it "creates an off-session confirmed PaymentIntent and returns succeeded" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .to_return(status: 200, body: { id: "pi_2", status: "succeeded" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.charge_token(order: order, payment: payment, payment_method: pm)
      expect(res).to include(status: :succeeded, psp_transaction_id: "pi_2")
    end

    it "sends off_session=true and confirm=true" do
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_2", status: "succeeded" }.to_json)

      gw.charge_token(order: order, payment: payment, payment_method: pm)
      expect(captured.body).to include("off_session=true")
      expect(captured.body).to include("confirm=true")
      expect(captured.body).to include("customer=cus_1")
      expect(captured.body).to include("payment_method=pm_1")
    end

    it "returns :requires_action with a client_secret on a 200 requires_action response" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .to_return(status: 200,
                   body: { id: "pi_ra", status: "requires_action", client_secret: "pi_ra_secret" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.charge_token(order: order, payment: payment, payment_method: pm)
      expect(res).to include(status: :requires_action, psp_transaction_id: "pi_ra",
                             client_secret: "pi_ra_secret")
    end

    it "surfaces an off-session authentication_required (402) as recoverable :requires_action" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .to_return(status: 402, body: {
          error: { code: "authentication_required",
                   payment_intent: { id: "pi_402", client_secret: "pi_402_secret" } }
        }.to_json, headers: { "Content-Type" => "application/json" })

      res = gw.charge_token(order: order, payment: payment, payment_method: pm)
      expect(res).to include(status: :requires_action, psp_transaction_id: "pi_402",
                             client_secret: "pi_402_secret")
    end

    it "re-raises a non-authentication ApiError (real decline)" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .to_return(status: 402, body: { error: { type: "card_error", code: "card_declined", message: "Your card was declined." } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect {
        gw.charge_token(order: order, payment: payment, payment_method: pm)
      }.to raise_error(Payments::Errors::ApiError) { |error| expect(error).to be_definitive }
    end

    it "does not retire the original operation after an idempotency parameter conflict" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents").to_return(status: 400, body: {
        error: { type: "idempotency_error", message: "Parameters differ from the original operation" }
      }.to_json)
      expect { gw.charge_token(order: order, payment: payment, payment_method: pm) }
        .to raise_error(Payments::Errors::ApiError) { |error| expect(error).to be_uncertain }
    end

    [409, 429, 500, 503].each do |status|
      it "keeps a financial write uncertain after HTTP #{status}" do
        stub_request(:post, "https://api.stripe.com/v1/payment_intents")
          .with(headers: { "Idempotency-Key" => "ch-2" })
          .to_return(status: status, body: { error: { type: "api_error", message: "Try again" } }.to_json,
                     headers: { "Stripe-Should-Retry" => "false" })

        expect { gw.charge_token(order: order, payment: payment, payment_method: pm) }
          .to raise_error(Payments::Errors::TransportError)
      end
    end

    it "reads a mixed-case retry directive through StripeResponseHeaders' supported lookup API" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents").to_return(status: 400,
        body: { error: { type: "invalid_request_error", message: "Retry the same request", param: "amount" } }.to_json,
        headers: { "StRiPe-ShOuLd-ReTrY" => "true" })
      expect { gw.charge_token(order: order, payment: payment, payment_method: pm) }
        .to raise_error(Payments::Errors::TransportError)
    end
  end

  describe "#vault_card" do
    let(:user) { instance_double("User", id: 7, email: "a@b.com") }

    it "creates a Customer and SetupIntent, returns client_secret + psp_customer_id" do
      stub_request(:post, "https://api.stripe.com/v1/customers")
        .to_return(status: 200, body: { id: "cus_1" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:post, "https://api.stripe.com/v1/setup_intents")
        .to_return(status: 200, body: { id: "seti_1", client_secret: "seti_1_secret" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.vault_card(user: user, return_url: "https://x/return")
      expect(res).to include(client_secret: "seti_1_secret", psp_customer_id: "cus_1",
                             setup_intent_id: "seti_1")
    end

    it "stamps merchant_id metadata on the SetupIntent" do
      captured_setup = nil
      stub_request(:post, "https://api.stripe.com/v1/customers")
        .to_return(status: 200, body: { id: "cus_1" }.to_json)
      stub_request(:post, "https://api.stripe.com/v1/setup_intents")
        .with { |req| captured_setup = req; true }
        .to_return(status: 200, body: { id: "seti_1", client_secret: "seti_secret" }.to_json)

      gw.vault_card(user: user, return_url: "https://x/return")
      expect(captured_setup.body).to include("metadata[merchant_id]=acct_1")
      expect(captured_setup.body).to include("usage=off_session")
    end
  end

  describe "#detach_token" do
    let(:pm) { instance_double(Payments::PaymentMethod, psp_payment_method_id: "pm_x") }

    it "calls detach endpoint and returns :removed" do
      stub_request(:post, "https://api.stripe.com/v1/payment_methods/pm_x/detach")
        .to_return(status: 200, body: { id: "pm_x" }.to_json)

      res = gw.detach_token(payment_method: pm)
      expect(res).to eq({ status: :removed })
    end
  end

  describe "#query" do
    let(:payment) { instance_double(Payments::Payment, psp_transaction_id: "pi_q1", out_trade_no: "ch-q1") }

    it "maps succeeded status" do
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_q1")
        .to_return(status: 200, body: { id: "pi_q1", status: "succeeded" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:succeeded)
      expect(res[:psp_transaction_id]).to eq("pi_q1")
    end

    it "maps processing status to :pending" do
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_q1")
        .to_return(status: 200, body: { id: "pi_q1", status: "processing" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:pending)
    end

    it "maps canceled to :closed" do
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_q1")
        .to_return(status: 200, body: { id: "pi_q1", status: "canceled" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:closed)
    end

    it "maps any other/unknown status to :failed" do
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_q1")
        .to_return(status: 200, body: { id: "pi_q1", status: "some_terminal_failure" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.query(payment: payment)
      expect(res[:status]).to eq(:failed)
    end

    it "falls back to out_trade_no when psp_transaction_id is absent" do
      pmt = instance_double(Payments::Payment, psp_transaction_id: nil, out_trade_no: "ch-fallback", prepay_payload: {})
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/ch-fallback")
        .to_return(status: 200, body: { id: "pi_fb", status: "succeeded" }.to_json)

      res = gw.query(payment: pmt)
      expect(res[:psp_transaction_id]).to eq("pi_fb")
    end

    it "returns the asserted JPY amount and the actual expanded Charge time, never intent creation time" do
      settled = Time.utc(2026, 10, 10, 15, 30)
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_q1").to_return(status: 200, body: {
        id: "pi_q1", status: "succeeded", currency: "jpy", amount_received: 1000,
        created: 1.week.ago.to_i, latest_charge: { id: "ch_captured", created: settled.to_i }
      }.to_json)

      expect(gw.query(payment: payment)).to include(currency: "JPY", amount: BigDecimal("1000"), settled_at: settled)
    end

    it "retrieves the unexpanded Charge to resolve the PSP capture timestamp" do
      settled = Time.utc(2026, 10, 10, 15, 30)
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_q1").to_return(status: 200, body: {
        id: "pi_q1", status: "succeeded", currency: "usd", amount_received: 500, latest_charge: "ch_capture"
      }.to_json)
      stub_request(:get, "https://api.stripe.com/v1/charges/ch_capture")
        .to_return(status: 200, body: { id: "ch_capture", created: settled.to_i }.to_json)

      expect(gw.query(payment: payment)).to include(currency: "USD", amount: BigDecimal("5.00"), settled_at: settled)
    end

    it "does not invent a timestamp when only intent creation time is known" do
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_q1").to_return(status: 200, body: {
        id: "pi_q1", status: "succeeded", created: 1.week.ago.to_i
      }.to_json)
      expect(gw.query(payment: payment)[:settled_at]).to be_nil
    end

    it "can query an SCA recovery intent whose id is only in the persisted payload" do
      pmt = instance_double(Payments::Payment, psp_transaction_id: nil, out_trade_no: "ct-sca",
                            prepay_payload: { "psp_payment_intent_id" => "pi_recovery" })
      stub_request(:get, "https://api.stripe.com/v1/payment_intents/pi_recovery")
        .to_return(status: 200, body: { id: "pi_recovery", status: "requires_action" }.to_json)
      expect(gw.query(payment: pmt)[:status]).to eq(:requires_action)
    end
  end

  describe "#refund" do
    let(:payment) do
      instance_double(Payments::Payment, psp_transaction_id: "pi_1",
                                         payment_order: instance_double(Payments::Order, currency: "usd"))
    end
    let(:refund_obj) { instance_double("Payments::Refund", amount: 2.00, out_refund_no: "rf-st-1") }

    it "creates a refund and returns psp_refund_id" do
      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .to_return(status: 200, body: { id: "re_1", status: "succeeded" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.refund(payment: payment, refund: refund_obj)
      expect(res[:psp_refund_id]).to eq("re_1")
      expect(res[:status]).to eq(:succeeded)
    end

    it "maps a non-succeeded refund status to :processing" do
      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .to_return(status: 200, body: { id: "re_2", status: "pending" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.refund(payment: payment, refund: refund_obj)
      expect(res[:status]).to eq(:processing)
    end

    it "keeps a 500 refund uncertain so the activity retains the original refund number" do
      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .with(headers: { "Idempotency-Key" => "rf-st-1" })
        .to_return(status: 500, body: { error: { type: "api_error", message: "Reconcile this request" } }.to_json,
                   headers: { "Stripe-Should-Retry" => "false" })
      expect { gw.refund(payment: payment, refund: refund_obj) }.to raise_error(Payments::Errors::TransportError)
    end

    it "rescales zero-decimal refund amounts to Stripe smallest units" do
      jpy_order = instance_double(Payments::Order, currency: "jpy")
      jpy_payment = instance_double(Payments::Payment, psp_transaction_id: "pi_jpy",
                                                        payment_order: jpy_order)
      jpy_refund = instance_double("Payments::Refund", amount: 1000.00,
                                                       out_refund_no: "rf-jpy")
      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/refunds")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "re_jpy", status: "succeeded" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      gw.refund(payment: jpy_payment, refund: jpy_refund)

      expect(captured.body).to include("amount=1000")
      expect(captured.body).not_to include("amount=100000")
      expect(captured.body).to include("metadata[out_refund_no]=rf-jpy")
    end
  end

  describe "#fetch_payment_method" do
    it "returns card brand/last4/exp from the PaymentMethod object" do
      stub_request(:get, "https://api.stripe.com/v1/payment_methods/pm_fetch")
        .to_return(status: 200, body: {
          id: "pm_fetch",
          card: { brand: "visa", last4: "4242", exp_month: 12, exp_year: 2030 }
        }.to_json, headers: { "Content-Type" => "application/json" })

      res = gw.fetch_payment_method("pm_fetch")
      expect(res).to eq(brand: "visa", last4: "4242", exp_month: 12, exp_year: 2030)
    end

    it "tolerates a PaymentMethod with no card object" do
      stub_request(:get, "https://api.stripe.com/v1/payment_methods/pm_nocard")
        .to_return(status: 200, body: { id: "pm_nocard" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.fetch_payment_method("pm_nocard")
      expect(res).to eq(brand: nil, last4: nil, exp_month: nil, exp_year: nil)
    end
  end

  describe "#ping" do
    it "returns ok: true when GET /v1/account succeeds" do
      stub_request(:get, "https://api.stripe.com/v1/account")
        .to_return(status: 200, body: { id: "acct_1" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      res = gw.ping
      expect(res[:ok]).to be(true)
      expect(res[:message]).to include("Connected to Stripe")
      expect(res[:verified_at]).to be_present
    end

    it "returns ok: false on an API error (bad secret key)" do
      stub_request(:get, "https://api.stripe.com/v1/account")
        .to_return(status: 401, body: { error: { message: "Invalid API Key" } }.to_json)

      res = gw.ping
      expect(res[:ok]).to be(false)
      expect(res[:message]).to include("Stripe API error")
    end

    it "returns ok: false on a network/transport error" do
      stub_request(:get, "https://api.stripe.com/v1/account").to_timeout

      res = gw.ping
      expect(res[:ok]).to be(false)
      expect(res[:message]).to include("Network error")
    end

    it "reports missing saved credentials as a controlled probe failure" do
      allow(account).to receive(:credential).with(:secret_key).and_return("")
      expect(gw.ping).to include(ok: false, message: I18n.t("comp_payments.test_connection.ping_api_error", label: "Stripe"))
      expect(a_request(:get, "https://api.stripe.com/v1/account")).not_to have_been_made
    end
  end

  describe "#close" do
    let(:payment) { instance_double(Payments::Payment, psp_transaction_id: "pi_1") }

    it "cancels the PaymentIntent and returns :closed" do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents/pi_1/cancel")
        .to_return(status: 200, body: { id: "pi_1", status: "canceled" }.to_json)

      res = gw.close(payment: payment)
      expect(res).to eq({ status: :closed })
    end
  end

  describe "#subscribe and #cancel_subscription" do
    it "subscribe returns :pending_sign (local state stub)" do
      sub = instance_double("Payments::Subscription")
      expect(gw.subscribe(subscription: sub)).to eq({ status: :pending_sign })
    end

    it "cancel_subscription returns :cancelled (local state stub)" do
      sub = instance_double("Payments::Subscription")
      expect(gw.cancel_subscription(subscription: sub)).to eq({ status: :cancelled })
    end
  end

  describe "#charge_subscription" do
    it "delegates to charge_token using subscription.payment_method and payment.amount" do
      pm  = instance_double(Payments::PaymentMethod, psp_customer_id: "cus_1", psp_payment_method_id: "pm_1")
      sub = instance_double(Payments::Subscription, amount: 9.99, currency: "usd",
                            external_ref: "sub-1", plan_name: "Monthly Plan", payment_method: pm)
      payment = instance_double(Payments::Payment, out_trade_no: "ch-sub-1",
                                amount: 5.00, payment_order: nil)

      captured = nil
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with { |req| captured = req; true }
        .to_return(status: 200, body: { id: "pi_sub", status: "succeeded" }.to_json)

      res = gw.charge_subscription(subscription: sub, payment: payment)
      expect(res).to include(psp_transaction_id: "pi_sub")
      expect(captured.body).to include("amount=500")
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
    let(:secret) { "whsec_x" }
    let(:body)   { '{"type":"payment_intent.succeeded","data":{"object":{}}}' }
    let(:ts)     { Time.zone.now.to_i.to_s }
    let(:signed_payload) { "#{ts}.#{body}" }
    let(:hmac)   { OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload) }
    let(:sig)    { "t=#{ts},v1=#{hmac}" }

    it "accepts a valid signature and returns parsed event" do
      event = gw.verify_notification(headers: { "Stripe-Signature" => sig }, body: body)
      expect(event["type"]).to eq("payment_intent.succeeded")
    end

    it "rejects a bad signature" do
      bad_sig = "t=#{ts},v1=badhexvalue000"
      expect {
        gw.verify_notification(headers: { "Stripe-Signature" => bad_sig }, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid, /bad signature/)
    end

    it "rejects a stale timestamp outside 300s replay window" do
      stale_ts = (Time.zone.now.to_i - 400).to_s
      stale_payload = "#{stale_ts}.#{body}"
      stale_hmac = OpenSSL::HMAC.hexdigest("SHA256", secret, stale_payload)
      stale_sig = "t=#{stale_ts},v1=#{stale_hmac}"

      expect {
        gw.verify_notification(headers: { "Stripe-Signature" => stale_sig }, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid, /stale/)
    end

    it "rejects a missing signature header" do
      expect {
        gw.verify_notification(headers: {}, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid)
    end

    ["null", "[]", '{"data":{"object":[]}}'].each do |payload|
      it "rejects a correctly signed but malformed event: #{payload}" do
        signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{ts}.#{payload}")
        expect { gw.verify_notification(headers: { "Stripe-Signature" => "t=#{ts},v1=#{signature}" }, body: payload) }
          .to raise_error(Payments::Errors::SignatureInvalid)
      end
    end

    it "rejects an unconfigured signing secret even if the caller signs with an empty key" do
      allow(account).to receive(:credential).with(:webhook_signing_secret).and_return("")
      signature = OpenSSL::HMAC.hexdigest("SHA256", "", "#{ts}.#{body}")
      expect { gw.verify_notification(headers: { "Stripe-Signature" => "t=#{ts},v1=#{signature}" }, body: body) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end
  end
end
