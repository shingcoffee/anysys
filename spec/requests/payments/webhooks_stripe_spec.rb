# frozen_string_literal: true

require "rails_helper"

# Stripe webhook end-to-end request tests.
#
# Coverage rationale:
# - spec/requests/payments/webhooks_spec.rb covers Alipay only; this file adds
#   Stripe-specific scenarios through the HTTP layer (WebhooksController →
#   WebhookDispatcher → HandleWebhook).
# - spec/services/payments/activities/handle_webhook_spec.rb covers the
#   activity logic in isolation; this file exercises the full HTTP path.
# - spec/services/payments/gateways/stripe_spec.rb covers verify_notification
#   in isolation; this file exercises the controller + dispatcher integration.
#
# The route constraint was previously hard-coded to /(wechat_pay|alipay)/,
# which silently dropped all Stripe webhooks (404). It is now a request-time
# lambda over Payments::Gateways.keys so every registered gateway is covered
# automatically. Section 1 below confirms the HTTP route now reaches the
# controller for Stripe.
RSpec.describe "Payments::Webhooks — Stripe", type: :request do
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  def stripe_signature(body:, secret:, timestamp: Time.zone.now.to_i)
    signed_payload = "#{timestamp}.#{body}"
    hmac           = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    "t=#{timestamp},v1=#{hmac}"
  end

  def prepare_recorded_attempt!(payment, account)
    Payments::Activities::PrepareAttempt.call(customer: account.customer, order: payment.payment_order,
                                             payment: payment, operation: "charge")
    expect(payment.merchant_account_id).to eq(account.id)
  end

  # Runs the full controller → dispatcher → activity path for a Stripe event.
  def dispatch_stripe(sig:, body:)
    Payments::WebhookDispatcher.call(
      provider: "stripe",
      headers:  { "Stripe-Signature" => sig },
      body:     body
    )
  end

  let_it_be(:customer) { create(:customer) }
  let(:whsec)    { "whsec_test_stripe_secret" }

  let!(:stripe_account) do
    create(:payment_merchant_account, customer: customer, merchant_id: "acct_test_tenant",
           credentials: {
             secret_key:             "sk_test_x",
             publishable_key:        "pk_test_x",
             webhook_signing_secret: whsec
           })
  end

  before do
    Current.customer = customer
  end

  # ===========================================================================
  # 1. Routing guard — confirm /payments/webhooks/stripe is now routable
  # ===========================================================================
  describe "Stripe webhook route is reachable via HTTP" do
    it "POST /payments/webhooks/stripe reaches the controller and returns :ok" do
      # The constraint is now a request-time lambda over Payments::Gateways.keys,
      # so "stripe" is accepted as a valid provider segment.
      #
      # We stub the dispatcher so the controller returns :ok regardless of payload,
      # giving us a clean signal that the route was matched and the controller action
      # ran — distinct from any routing 404 (which would never reach the controller).
      allow(Payments::WebhookDispatcher).to receive(:call).and_return(:ok)

      post "/payments/webhooks/stripe", params: "{}", headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
    end
  end

  # ===========================================================================
  # 2. Controller + dispatcher: payment_intent.succeeded
  # ===========================================================================
  describe "payment_intent.succeeded dispatched to WebhooksController" do
    let(:out_trade_no) { "STRIPE-WT-#{SecureRandom.hex(4)}" }

    let(:order) do
      Current.customer = customer
      create(:payment_order, external_ref: "so-1", amount: 15.00, subject: "Widget")
    end

    let!(:payment) do
      Current.customer = customer
      create(:payment,
        payment_order: order,
        provider:      "stripe",
        flow:          "card",
        out_trade_no:  out_trade_no,
        amount: 15.00,
        status:        "pending"
      )
    end

    let(:pi_object) do
      {
        "id"       => "pi_test_123",
        "status"   => "succeeded",
        "metadata" => { "merchant_id" => "acct_test_tenant", "out_trade_no" => out_trade_no }
      }
    end

    # Real Stripe events always carry a top-level id (evt_…) — this is what
    # WebhookDispatcher hangs the async ProcessWebhookEventJob on.
    let(:event_body) do
      {
        "id"      => "evt_test_123",
        "type"    => "payment_intent.succeeded",
        "account" => "acct_test_tenant",
        "data"    => { "object" => pi_object }
      }.to_json
    end

    it "verifies signature + enqueues async processing, then marks the payment succeeded" do
      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: event_body, secret: whsec, timestamp: ts)

      # Verify the dispatcher runs the correct path using the real dispatcher:
      # signature verification + event recording are synchronous (ack now),
      # business processing (HandleWebhook) is queued.
      expect {
        expect(dispatch_stripe(sig: sig, body: event_body)).to eq(:accepted)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob)
      expect(payment.reload.status).to eq("pending")

      perform_enqueued_jobs

      expect(payment.reload.status).to eq("succeeded")
      expect(payment.psp_transaction_id).to eq("pi_test_123")
    end

    it "raises SignatureInvalid for a forged signature" do
      forged_sig = "t=#{Time.zone.now.to_i},v1=deadbeef000000000000000000000000"

      expect {
        dispatch_stripe(sig: forged_sig, body: event_body)
      }.to raise_error(Payments::Errors::SignatureInvalid)

      expect(payment.reload.status).to eq("pending")
    end

    it "raises SignatureInvalid for a stale timestamp (> 300s replay window)" do
      stale_ts      = (Time.zone.now.to_i - 400)
      stale_payload = "#{stale_ts}.#{event_body}"
      stale_hmac    = OpenSSL::HMAC.hexdigest("SHA256", whsec, stale_payload)
      stale_sig     = "t=#{stale_ts},v1=#{stale_hmac}"

      expect {
        dispatch_stripe(sig: stale_sig, body: event_body)
      }.to raise_error(Payments::Errors::SignatureInvalid)

      expect(payment.reload.status).to eq("pending")
    end

    it "is a no-op (does not flip payment) when signing merchant belongs to a different tenant" do
      attacker      = create(:customer)
      attacker_acct = create(:payment_merchant_account, customer: attacker, merchant_id: "acct_attacker_000",
                              credentials: {
                                secret_key:             "sk_test_y",
                                publishable_key:        "pk_test_y",
                                webhook_signing_secret: "whsec_attacker"
                              })

      # Event references tenant A's out_trade_no but is signed by attacker's secret.
      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: event_body, secret: "whsec_attacker", timestamp: ts)

      # WebhookDispatcher resolves tenant via extract_merchant_id → "acct_test_tenant"
      # then verifies against THAT account's whsec (whsec_test_stripe_secret), so
      # the attacker's hmac is invalid for the correct tenant's signing secret.
      expect {
        dispatch_stripe(sig: sig, body: event_body)
      }.to raise_error(Payments::Errors::SignatureInvalid)

      expect(payment.reload.status).to eq("pending")
    end
  end

  # ===========================================================================
  # 3. setup_intent.succeeded — backfill guard across tenants
  # ===========================================================================
  describe "setup_intent.succeeded cross-tenant guard" do
    let(:victim_customer) { create(:customer) }
    let(:victim_user)     { create(:user, :member, customer: victim_customer) }

    let!(:victim_acct) do
      create(:payment_merchant_account, customer: victim_customer, merchant_id: "acct_victim_vvv",
             credentials: { webhook_signing_secret: "whsec_victim" })
    end

    let!(:victim_pm) do
      create(:payment_method,
        customer:              victim_customer,
        user:                  victim_user,
        provider:              "stripe",
        psp_customer_id:       "cus_victim_www",
        psp_payment_method_id: "pending:victim_pending",
        status:                "active",
        brand:                 nil,
        last4:                 nil,
        exp_month:             nil,
        exp_year:              nil
      )
    end

    let(:attacker_customer) { create(:customer) }
    let!(:attacker_acct) do
      create(:payment_merchant_account, customer: attacker_customer, merchant_id: "acct_attacker_aaa",
             credentials: { webhook_signing_secret: "whsec_attacker" })
    end

    it "does NOT backfill a victim's pending PaymentMethod when signed by attacker merchant" do
      event_body = {
        "id"      => "evt_attacker_setup",
        "type"    => "setup_intent.succeeded",
        "account" => "acct_attacker_aaa",
        "data"    => {
          "object" => {
            "customer"       => "cus_victim_www",
            "payment_method" => "pm_stolen_token",
            "status"         => "succeeded"
          }
        }
      }.to_json

      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: event_body, secret: "whsec_attacker", timestamp: ts)

      # Dispatcher resolves merchant from "account" → "acct_attacker_aaa",
      # verifies against attacker's whsec (succeeds) and enqueues async
      # processing; HandleWebhook applies the cross-tenant guard there:
      # attacker's customer_id ≠ victim_pm.customer_id → no-op.
      expect {
        dispatch_stripe(sig: sig, body: event_body)
      }.not_to raise_error
      perform_enqueued_jobs

      victim_pm.reload
      expect(victim_pm.psp_payment_method_id).to eq("pending:victim_pending")
      expect(victim_pm.brand).to be_nil
    end
  end

  # ===========================================================================
  # 4. WebhooksController HTTP responses for Stripe events via dispatcher
  # ===========================================================================
  describe "WebhooksController response codes for Stripe via dispatcher" do
    it "accepts a valid Stripe payment_intent.succeeded and processes it async" do
      out_trade_no = "CTRL-STRIPE-#{SecureRandom.hex(4)}"
      order   = create(:payment_order, external_ref: out_trade_no, amount: 5.00, subject: "s")
      payment = create(:payment, payment_order: order, provider: "stripe", flow: "card",
                       out_trade_no: out_trade_no, amount: 5.00, status: "pending")

      body = {
        "id"      => "evt_ctrl_1",
        "type"    => "payment_intent.succeeded",
        "account" => "acct_test_tenant",
        "data"    => { "object" => {
          "id" => "pi_ctrl_1", "status" => "succeeded",
          "metadata" => { "merchant_id" => "acct_test_tenant", "out_trade_no" => out_trade_no }
        } }
      }.to_json

      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: body, secret: whsec, timestamp: ts)

      result = dispatch_stripe(sig: sig, body: body)
      expect(result).to eq(:accepted)

      perform_enqueued_jobs

      expect(payment.reload.status).to eq("succeeded")
    end

    it "raises TenantNotFound when no MerchantAccount matches the event account field" do
      body = {
        "type"    => "payment_intent.succeeded",
        "account" => "acct_completely_unknown",
        "data"    => { "object" => { "id" => "pi_ghost", "metadata" => {} } }
      }.to_json

      ts  = Time.zone.now.to_i
      # Sign with the known account's secret to pass the gateway lookup step;
      # the dispatcher will fail at gateway_for_merchant (unknown merchant_id).
      sig = stripe_signature(body: body, secret: whsec, timestamp: ts)

      expect {
        dispatch_stripe(sig: sig, body: body)
      }.to raise_error(Payments::Errors::TenantNotFound)
    end
  end

  # ===========================================================================
  # 5. Zero-decimal (JPY) amount rescaling through the full async path (C1)
  # ===========================================================================
  describe "JPY payment_intent.succeeded through the dispatcher async pipeline" do
    let(:jpy_out_trade_no) { "JPY-STRIPE-#{SecureRandom.hex(4)}" }
    let(:jpy_order) do
      Current.customer = customer
      create(:payment_order, external_ref: "jpy-async-o1", amount: 1000.00,
             subject: "Yen Widget", currency: "JPY")
    end
    let!(:jpy_payment) do
      Current.customer = customer
      create(:payment, payment_order: jpy_order, provider: "stripe", flow: "card",
             out_trade_no: jpy_out_trade_no, amount: 1000.00, status: "pending")
    end

    it "rescales Stripe's whole-yen amount_received and marks the payment succeeded end-to-end" do
      body = {
        "id"      => "evt_jpy_async_1",
        "type"    => "payment_intent.succeeded",
        "account" => "acct_test_tenant",
        "data"    => { "object" => {
          "id" => "pi_jpy_async", "status" => "succeeded", "amount_received" => 1000,
          "metadata" => { "merchant_id" => "acct_test_tenant", "out_trade_no" => jpy_out_trade_no }
        } }
      }.to_json

      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: body, secret: whsec, timestamp: ts)

      expect {
        expect(dispatch_stripe(sig: sig, body: body)).to eq(:accepted)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob)
      expect(jpy_payment.reload.status).to eq("pending")

      perform_enqueued_jobs

      expect(jpy_payment.reload.status).to eq("succeeded")
      expect(jpy_payment.psp_transaction_id).to eq("pi_jpy_async")
    end
  end

  # ===========================================================================
  # 6. Dispute / refund handlers still enforce signing_matches_payment? after
  #    the async move (H2) — verified through the full dispatcher -> job ->
  #    HandleWebhook pipeline, not just the activity in isolation.
  #
  #    NOTE: real direct (non-Connect) Stripe webhooks for charge.dispute.* and
  #    refund.updated carry NO top-level `account` field — Stripe only sends
  #    that on Connect events. These bodies previously injected a fake `account`
  #    field to make routing work in the test; that masked the fact that
  #    extract_merchant_id had no fallback for real dispute/refund payloads
  #    (H2 routing bug — see section 7). The bodies below now omit `account`,
  #    matching what Stripe actually sends, and routing instead falls back to
  #    the payment_intent id stored on our own payment record. Because that
  #    fallback resolves the TRUE owning tenant (not whatever the request body
  #    claims), an attacker's forged event is now rejected at signature
  #    verification — one step earlier than the old defense-in-depth guard in
  #    HandleWebhook, but with the same end result: the victim's data is
  #    untouched.
  # ===========================================================================
  describe "cross-tenant guard survives the async move for dispute and refund handlers" do
    let(:victim_customer) { create(:customer) }
    let!(:victim_account) do
      create(:payment_merchant_account, customer: victim_customer, merchant_id: "acct_victim_async",
             credentials: { webhook_signing_secret: "whsec_victim_async" })
    end

    let(:attacker_customer) { create(:customer) }
    let!(:attacker_account) do
      create(:payment_merchant_account, customer: attacker_customer, merchant_id: "acct_attacker_async",
             credentials: { webhook_signing_secret: "whsec_attacker_async" })
    end

    it "rejects a dispute event referencing a victim's payment_intent but signed by an unrelated merchant" do
      Current.customer = victim_customer
      victim_order = create(:payment_order, customer: victim_customer, external_ref: "victim-disp-o1", amount: 5.00, subject: "s")
      victim_payment = create(:payment, customer: victim_customer, payment_order: victim_order, provider: "stripe", flow: "card",
        out_trade_no: "VICTIM-DISP-OT-1", amount: 5.00, status: "succeeded",
         psp_transaction_id: "pi_victim_disputed_async")
      prepare_recorded_attempt!(victim_payment, victim_account)

      # Attacker crafts a body naming the victim's payment_intent as the
      # disputed charge, signed with the attacker's OWN webhook secret (the
      # only secret they actually possess). No top-level `account` field —
      # real direct webhooks don't carry one.
      body = {
        "id"   => "evt_attacker_dispute",
        "type" => "charge.dispute.created",
        "data" => { "object" => {
          "id" => "dp_attacker_1", "payment_intent" => "pi_victim_disputed_async",
          "reason" => "fraudulent", "status" => "needs_response", "amount" => 500, "metadata" => {}
        } }
      }.to_json

      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: body, secret: "whsec_attacker_async", timestamp: ts)

      # Routing resolves the TRUE owner (victim) via the stored payment_intent
      # reference, so verification runs against the victim's whsec — which the
      # attacker's signature does not satisfy.
      expect {
        dispatch_stripe(sig: sig, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid)

      expect(Payments::Dispute.unscoped_by_tenant.where(psp_dispute_id: "dp_attacker_1")).to be_empty
      expect(victim_payment.reload.status).to eq("succeeded")
    end

    it "rejects a refund event referencing a victim's payment_intent but signed by an unrelated merchant" do
      Current.customer = victim_customer
      victim_order = create(:payment_order, customer: victim_customer, external_ref: "victim-refund-o1", amount: 5.00, subject: "s")
      victim_payment = create(:payment, customer: victim_customer, payment_order: victim_order, provider: "stripe", flow: "card",
        out_trade_no: "VICTIM-REFUND-OT-1", amount: 5.00, status: "succeeded",
         psp_transaction_id: "pi_victim_refunded_async")
      prepare_recorded_attempt!(victim_payment, victim_account)
      victim_refund = create(:payment_refund, customer: victim_customer, payment: victim_payment, out_refund_no: "rf-victim-async-1",
        amount: 5.00, status: "processing", psp_refund_id: "re_victim_async_1")

      body = {
        "id"   => "evt_attacker_refund",
        "type" => "refund.updated",
        "data" => { "object" => {
          "id" => "re_victim_async_1", "status" => "succeeded",
          "payment_intent" => "pi_victim_refunded_async", "metadata" => {}
        } }
      }.to_json

      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: body, secret: "whsec_attacker_async", timestamp: ts)

      expect {
        dispatch_stripe(sig: sig, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid)

      expect(victim_refund.reload.status).to eq("processing")
    end
  end

  # ===========================================================================
  # 7. H2 fix: charge.dispute.* and refund.updated route correctly through the
  #    full HTTP path with a REALISTIC direct-webhook body — no metadata on
  #    the Dispute/Refund object (never stamped by us) and no top-level
  #    `account` field (Connect-only). Before the fix, extract_merchant_id
  #    returned nil for these bodies, gateway_for_merchant raised
  #    Payments::Errors::TenantNotFound, and the event never reached
  #    verification (in production: an endless 4xx/5xx retry loop until Stripe
  #    disables the endpoint).
  # ===========================================================================
  describe "dispute and refund webhooks route via the payment's stored payment_intent id (H2)" do
    let(:tenant_customer) { create(:customer) }
    let(:whsec_tenant)    { "whsec_tenant_route" }
    let!(:tenant_account) do
      create(:payment_merchant_account, customer: tenant_customer, merchant_id: "acct_tenant_route",
             credentials: { webhook_signing_secret: whsec_tenant })
    end

    it "records a dispute for the correct tenant with no metadata and no Connect account field" do
      Current.customer = tenant_customer
      order   = create(:payment_order, customer: tenant_customer, external_ref: "tenant-disp-o1", amount: 7.00, subject: "s")
      payment = create(:payment, customer: tenant_customer, payment_order: order, provider: "stripe", flow: "card",
        out_trade_no: "TENANT-DISP-OT-1", amount: 7.00, status: "succeeded",
         psp_transaction_id: "pi_tenant_disputed")
      prepare_recorded_attempt!(payment, tenant_account)

      body = {
        "id"   => "evt_tenant_dispute",
        "type" => "charge.dispute.created",
        "data" => { "object" => {
          "id" => "dp_tenant_1", "payment_intent" => "pi_tenant_disputed",
          "reason" => "fraudulent", "status" => "needs_response", "amount" => 700, "metadata" => {}
        } }
      }.to_json

      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: body, secret: whsec_tenant, timestamp: ts)

      expect {
        expect(dispatch_stripe(sig: sig, body: body)).to eq(:accepted)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob)

      perform_enqueued_jobs

      dispute = Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_tenant_1")
      expect(dispute).to be_present
      expect(dispute.payment_id).to eq(payment.id)
      expect(dispute.status).to eq("open")
    end

    it "settles an async refund for the correct tenant with no metadata and no Connect account field" do
      Current.customer = tenant_customer
      order   = create(:payment_order, customer: tenant_customer, external_ref: "tenant-refund-o1", amount: 7.00, subject: "s")
      payment = create(:payment, customer: tenant_customer, payment_order: order, provider: "stripe", flow: "card",
        out_trade_no: "TENANT-REFUND-OT-1", amount: 7.00, status: "succeeded",
         psp_transaction_id: "pi_tenant_refunded")
      prepare_recorded_attempt!(payment, tenant_account)
      refund = create(:payment_refund, customer: tenant_customer, payment: payment, out_refund_no: "rf-tenant-1",
        amount: 7.00, status: "processing", psp_refund_id: "re_tenant_1")

      body = {
        "id"   => "evt_tenant_refund",
        "type" => "refund.updated",
        "data" => { "object" => {
          "id" => "re_tenant_1", "status" => "succeeded",
          "payment_intent" => "pi_tenant_refunded", "metadata" => {}
        } }
      }.to_json

      ts  = Time.zone.now.to_i
      sig = stripe_signature(body: body, secret: whsec_tenant, timestamp: ts)

      expect {
        expect(dispatch_stripe(sig: sig, body: body)).to eq(:accepted)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob)

      perform_enqueued_jobs

      expect(refund.reload.status).to eq("succeeded")
    end
  end
end
