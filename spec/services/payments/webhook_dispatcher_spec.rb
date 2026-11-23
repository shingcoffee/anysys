require "rails_helper"

RSpec.describe Payments::WebhookDispatcher do
  let_it_be(:customer) { create(:customer) }
  let(:priv) { File.read("spec/fixtures/payments/keys/test_rsa_private.pem") }
  let(:pub)  { File.read("spec/fixtures/payments/keys/test_rsa_public.pem") }

  before { Current.customer = customer }


  context "alipay" do
    let!(:account) do
      create(:payment_merchant_account, provider: "alipay", mode: "sandbox",
             merchant_id: "2088", status: "active",
             credentials: { private_key_pem: priv, platform_public_key_pem: pub })
    end

    let(:order) { create(:payment_order, external_ref: "e1", amount: 1.00, subject: "s") }
    let!(:payment) do
      create(:payment, payment_order: order, provider: "alipay", flow: "qr",
             out_trade_no: "ot-1", amount: 1.00, status: "pending")
    end

    def signed_alipay_body(params)
      key = OpenSSL::PKey::RSA.new(priv)
      to_sign = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
      sig = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, to_sign))
      URI.encode_www_form(params.merge("sign" => sig, "sign_type" => "RSA2"))
    end

    it "verifies signature, enqueues ProcessWebhookEventJob, and acks :accepted" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999", "notify_id" => "NID-ACCEPT")

      expect {
        expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:accepted)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob)

      # Not yet processed inline — verification/recording is synchronous, but
      # business processing is queued.
      expect(payment.reload.status).to eq("pending")

      perform_enqueued_jobs

      expect(payment.reload.status).to eq("succeeded")
      event = Payments::WebhookEvent.find_by(provider: "alipay", event_type: "TRADE_SUCCESS")
      expect(event.signing_account_id).to eq(account.id)
      expect(event.status).to eq("processed")
      expect(event.customer_id).to eq(customer.id)
    end

    it "drops a duplicate delivery via the event ledger (notify_id) and enqueues nothing" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999",
        "total_amount" => "1.00", "notify_id" => "NID-1")

      expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:accepted)
      perform_enqueued_jobs

      expect {
        expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:duplicate)
      }.not_to have_enqueued_job(Payments::ProcessWebhookEventJob)
      expect(Payments::WebhookEvent.where(provider: "alipay", psp_event_id: "NID-1").count).to eq(1)
    end

    it "drops a redelivery of a still-in-flight (received, not yet processed) event as :duplicate" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999", "notify_id" => "NID-INFLIGHT")

      # First delivery: verified + recorded + enqueued, but the job has NOT run
      # yet — the event is still "received".
      expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:accepted)
      event = Payments::WebhookEvent.find_by(provider: "alipay", psp_event_id: "NID-INFLIGHT")
      expect(event.status).to eq("received")

      # PSP redelivers before the job drains (common under load) — must be
      # dropped as a duplicate, not re-enqueued a second time.
      expect {
        expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:duplicate)
      }.not_to have_enqueued_job(Payments::ProcessWebhookEventJob)

      expect(event.reload.status).to eq("received")
      expect(Payments::WebhookEvent.where(provider: "alipay", psp_event_id: "NID-INFLIGHT").count).to eq(1)
    end

    it "re-drives a redelivery of a failed event: resets to received, enqueues, returns the event" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999", "notify_id" => "NID-REDRIVE")

      described_class.call(provider: "alipay", headers: {}, body: body)
      event = Payments::WebhookEvent.find_by(provider: "alipay", psp_event_id: "NID-REDRIVE")
      event.update!(status: "failed")

      expect {
        described_class.call(provider: "alipay", headers: {}, body: body)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob)

      expect(event.reload.status).to eq("received")
    end

    it "re-drives a redelivery of a stale 'received' event stuck beyond the job's retry window" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999", "notify_id" => "NID-STALE-RECEIVED")

      described_class.call(provider: "alipay", headers: {}, body: body)
      event = Payments::WebhookEvent.find_by(provider: "alipay", psp_event_id: "NID-STALE-RECEIVED")
      expect(event.status).to eq("received")
      # Simulate the job never having drained (crashed worker, queue outage) —
      # well beyond ProcessWebhookEventJob's own ~6-minute retry window.
      event.update_columns(updated_at: 20.minutes.ago)

      expect {
        expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:accepted)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob)

      expect(event.reload.status).to eq("received")
    end

    it "does NOT re-drive a 'received' event still within the job's retry window (avoids racing the in-flight job)" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999", "notify_id" => "NID-FRESH-RECEIVED")

      described_class.call(provider: "alipay", headers: {}, body: body)

      expect {
        expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:duplicate)
      }.not_to have_enqueued_job(Payments::ProcessWebhookEventJob)
    end

    it "rolls back the recorded event when enqueuing the job fails (atomic insert + enqueue)" do
      allow(Payments::ProcessWebhookEventJob).to receive(:perform_later).and_raise(StandardError, "queue down")
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999", "notify_id" => "NID-ATOMIC")

      expect {
        described_class.call(provider: "alipay", headers: {}, body: body)
      }.to raise_error(StandardError, "queue down")

      expect(Payments::WebhookEvent.where(provider: "alipay", psp_event_id: "NID-ATOMIC")).not_to exist
    end

    it "refuses to mark paid when the notified amount does not match the payment (H3)" do
      # payment.amount is 100; total_amount 99.99 yuan = 9999 fen.
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "trade_no" => "T999", "total_amount" => "99.99",
        "notify_id" => "NID-MISMATCH")

      expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:accepted)
      perform_enqueued_jobs

      expect(payment.reload.status).to eq("pending")
      expect(order.reload.status).to eq("pending")
    end

    it "raises TenantNotFound for unknown app_id" do
      body = URI.encode_www_form(app_id: "unknown", sign: "x", sign_type: "RSA2")
      expect {
        described_class.call(provider: "alipay", headers: {}, body: body)
      }.to raise_error(Payments::Errors::TenantNotFound)
    end

    it "raises SignatureInvalid on bad signature" do
      body = URI.encode_www_form(app_id: "2088", out_trade_no: "ot-1",
                                 sign: Base64.strict_encode64("bad"), sign_type: "RSA2")
      expect {
        described_class.call(provider: "alipay", headers: {}, body: body)
      }.to raise_error(Payments::Errors::SignatureInvalid)
    end

    it "records and settles using the disabled historical account that verified the notification" do
      account.update!(status: "disabled")
      payment.update!(prepay_payload: { Payments::Payment::ATTEMPT_CONTEXT_KEY => {
        merchant_account_id: account.id, merchant_id: account.merchant_id, mode: account.mode
      } })
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "total_amount" => "1.00", "notify_id" => "NID-DISABLED")

      expect {
        described_class.call(provider: "alipay", headers: {}, body: body)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob).with(
        kind_of(Integer), account.merchant_id, account.id
      )
      perform_enqueued_jobs

      expect(payment.reload.status).to eq("succeeded")
      expect(Payments::WebhookEvent.find_by!(psp_event_id: "NID-DISABLED").signing_account_id).to eq(account.id)
    end

    it "runs an event without a stable ID outside the dispatcher transaction, with exact signer identity" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1", "trade_status" => "TRADE_SUCCESS")
      transaction_depth = ActiveRecord::Base.connection.open_transactions
      expect(Payments::Activities::HandleWebhook).to receive(:call).with(
        hash_including(signing_account_id: account.id, signing_merchant_id: account.merchant_id)
      ) do
        expect(ActiveRecord::Base.connection.open_transactions).to eq(transaction_depth)
      end

      expect(described_class.call(provider: "alipay", headers: {}, body: body)).to eq(:ok)
    end

    it "refuses another verified account's reuse of a failed event ID" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "notify_id" => "NID-COLLISION")
      described_class.call(provider: "alipay", headers: {}, body: body)
      event = Payments::WebhookEvent.find_by!(psp_event_id: "NID-COLLISION")
      event.update!(status: "failed")
      original_payload = event.payload
      create(:payment_merchant_account, customer: create(:customer), provider: "alipay", merchant_id: "attacker",
             credentials: { private_key_pem: priv, platform_public_key_pem: pub })
      attacker_body = signed_alipay_body("app_id" => "attacker", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "notify_id" => "NID-COLLISION")

      expect {
        described_class.call(provider: "alipay", headers: {}, body: attacker_body)
      }.to raise_error(Payments::Errors::SignatureInvalid)
      expect(event.reload.payload).to eq(original_payload)
      expect(event.status).to eq("failed")
    end

    it "preserves the original verified body and identity through PSP redrive" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "notify_id" => "NID-PINNED")
      described_class.call(provider: "alipay", headers: {}, body: body)
      event = Payments::WebhookEvent.find_by!(psp_event_id: "NID-PINNED")
      event.update!(status: "failed")
      redelivery = signed_alipay_body("app_id" => "2088", "out_trade_no" => "different-trade",
        "trade_status" => "TRADE_SUCCESS", "notify_id" => "NID-PINNED")

      expect {
        described_class.call(provider: "alipay", headers: {}, body: redelivery)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob).with(event.id, account.merchant_id, account.id)
      expect(event.reload.verified_payload["out_trade_no"]).to eq("ot-1")
    end

    it "redrives the original verified event for the same account after a merchant-label edit" do
      body = signed_alipay_body("app_id" => "2088", "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "notify_id" => "NID-RENAMED")
      described_class.call(provider: "alipay", headers: {}, body: body)
      event = Payments::WebhookEvent.find_by!(psp_event_id: "NID-RENAMED")
      event.update!(status: "failed")
      account.update!(merchant_id: "2088-renamed")
      redelivery = signed_alipay_body("app_id" => account.merchant_id, "out_trade_no" => "ot-1",
        "trade_status" => "TRADE_SUCCESS", "notify_id" => "NID-RENAMED")

      expect {
        described_class.call(provider: "alipay", headers: {}, body: redelivery)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob).with(event.id, "2088", account.id)
      expect(event.reload.signing_merchant_id).to eq("2088")
      expect(event.verified_payload["app_id"]).to eq("2088")
    end
  end

  context "wechat_pay merchant_id extraction" do
    it "extracts mchid from resource payload via the gateway class" do
      body = { resource: { mchid: "wx_m1" } }.to_json
      expect(Payments::Gateways::WechatPay.extract_merchant_id({}, body)).to eq("wx_m1")
    end
  end

  describe ".normalize_headers" do
    it "converts Rack env-style keys into canonical Hyphen-Case keys" do
      env = {
        "HTTP_WECHATPAY_SIGNATURE" => "sig",
        "HTTP_WECHATPAY_TIMESTAMP" => "1234",
        "HTTP_WECHATPAY_NONCE"     => "nonce",
        "Content-Type"             => "application/json"
      }
      out = described_class.normalize_headers(env)
      expect(out["Wechatpay-Signature"]).to eq("sig")
      expect(out["Wechatpay-Timestamp"]).to eq("1234")
      expect(out["Wechatpay-Nonce"]).to eq("nonce")
      expect(out["Content-Type"]).to eq("application/json")
    end

    it "accepts already-normalized Hyphen-Case keys unchanged" do
      out = described_class.normalize_headers("Wechatpay-Signature" => "s")
      expect(out["Wechatpay-Signature"]).to eq("s")
    end
  end
end
