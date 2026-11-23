# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sms::Webhooks", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:twilio_credential) do
    create(:sms_credential, provider: "twilio", mode: "sandbox", status: "active",
           access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN",
           config: { "messaging_service_sid" => "MG1" })
  end

  def sign(url, params)
    data = url.to_s + params.sort_by(&:first).map { |k, v| "#{k}#{v}" }.join
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", "AUTH_TOKEN", data))
  end

  def post_webhook(kind, params, signature:)
    url = "http://www.example.com/sms/webhooks/twilio/#{kind}"
    post "/sms/webhooks/twilio/#{kind}", params: params,
         headers: { "X-Twilio-Signature" => signature }
    url
  end

  def create_bound_message(credential: twilio_credential, **attrs)
    create(:sms_message, **attrs, metadata: { "credential_id" => credential.id, "credential_mode" => credential.mode })
  end

  describe "signature verification" do
    it "rejects a forged/wrong signature with 403" do
      params = { "MessageSid" => "SM1", "MessageStatus" => "delivered" }
      post_webhook("delivery", params, signature: "forged-signature")
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a missing signature with 403" do
      params = { "MessageSid" => "SM1", "MessageStatus" => "delivered" }
      post "/sms/webhooks/twilio/delivery", params: params
      expect(response).to have_http_status(:forbidden)
    end

    it "authenticates every original parameter before invoking an event parser" do
      params = { "From" => "+14155552671", "Body" => "STOP", "ExtraVendorField" => "signed-value" }
      url = "http://www.example.com/sms/webhooks/twilio/inbound"
      signature = Twilio::Security::RequestValidator.new("AUTH_TOKEN").build_signature_for(url, params)
      expect_any_instance_of(Sms::Adapters::Twilio).not_to receive(:parse_inbound)

      expect { post_webhook("inbound", params.merge("ExtraVendorField" => "tampered"), signature: signature) }
        .not_to change(Sms::BackendReceipt, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "does not redact signed From/Body parameters before verification" do
      params = { "From" => "+14155552671", "Body" => "hello", "ExtraVendorField" => "signed-value" }
      url = "http://www.example.com/sms/webhooks/twilio/inbound"
      signature = Twilio::Security::RequestValidator.new("AUTH_TOKEN").build_signature_for(url, params)

      post_webhook("inbound", params, signature: signature)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
      expect(response.body).to eq("<Response/>")
    end
  end

  describe "known-length envelope limit" do
    it "rejects envelopes over 64 KiB before resolving or parsing a vendor" do
      expect(Sms::Adapters).not_to receive(:for)
      expect(Sms::ReceiptInbox).not_to receive(:record!)
      post "/sms/webhooks/twilio/inbound", params: "Body=#{'a' * (64 * 1024)}",
           headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

      expect(response).to have_http_status(:content_too_large)
    end

    it "accepts a signed envelope at the 64 KiB limit" do
      body = "Extra=#{'a' * (64 * 1024 - 'Extra='.bytesize)}"
      url = "http://www.example.com/sms/webhooks/twilio/inbound"
      signature = Twilio::Security::RequestValidator.new("AUTH_TOKEN")
                   .build_signature_for(url, { "Extra" => body.delete_prefix("Extra=") })
      post "/sms/webhooks/twilio/inbound", params: body,
           headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded", "X-Twilio-Signature" => signature }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
      expect(response.body).to eq("<Response/>")
    end
  end

  describe "delivery receipts (kind=delivery)" do
    it "flips a matching message to delivered on a valid, correctly-signed DLR" do
      msg = create_bound_message(customer: customer, provider: "twilio", status: "sent",
                   vendor_message_id: "SM123", sent_at: Time.zone.now)

      url    = "http://www.example.com/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM123", "MessageStatus" => "delivered" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/delivery", params: params, headers: { "X-Twilio-Signature" => sig }

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
      expect(msg.reload.status).to eq("delivered")
    end

    it "flips a matching message to failed on a failed DLR" do
      msg = create_bound_message(customer: customer, provider: "twilio", status: "sent",
                   vendor_message_id: "SM124", sent_at: Time.zone.now)

      url    = "http://www.example.com/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM124", "MessageStatus" => "failed" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/delivery", params: params, headers: { "X-Twilio-Signature" => sig }

      expect(response).to have_http_status(:ok)
      expect(msg.reload.status).to eq("failed")
      expect(msg.failure_message).to eq(Sms::Message::FAILURE_DELIVERY)
    end

    it "is a no-op (still 200) when no message matches the vendor_message_id" do
      url    = "http://www.example.com/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "UNKNOWN-SID", "MessageStatus" => "delivered" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/delivery", params: params, headers: { "X-Twilio-Signature" => sig }
      expect(response).to have_http_status(:ok)
    end

    it "respects the terminal guard — a late failed DLR does not un-deliver an already-delivered message" do
      msg = create_bound_message(customer: customer, provider: "twilio", status: "delivered",
                   vendor_message_id: "SM125", delivered_at: Time.zone.now)

      url    = "http://www.example.com/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM125", "MessageStatus" => "failed" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/delivery", params: params, headers: { "X-Twilio-Signature" => sig }
      expect(msg.reload.status).to eq("delivered")
    end

    it "records an interim receipt as unknown without marking delivery or failure" do
      msg = create_bound_message(customer: customer, provider: "twilio", status: "sent",
                   vendor_message_id: "SM126", sent_at: Time.zone.now)

      url    = "http://www.example.com/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM126", "MessageStatus" => "queued" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/delivery", params: params, headers: { "X-Twilio-Signature" => sig }
      expect(response).to have_http_status(:ok)
      expect(msg.reload.status).to eq("unknown")
      expect(msg.delivered_at).to be_nil
      expect(msg.failure_code).to be_nil
    end

    it "uses the normalized recipient when the event also has legacy raw fields" do
      message = create_bound_message(customer: customer, provider: "twilio", to: "+14155552671",
                                     status: "sent", vendor_message_id: "SM-NORMALIZED", sent_at: Time.current)
      params = { "MessageSid" => "SM-NORMALIZED", "MessageStatus" => "delivered", "To" => "+14155552672" }
      allow_any_instance_of(Sms::Adapters::Twilio).to receive(:parse_delivery_receipt).and_return([
        { vendor_message_id: "SM-NORMALIZED", status: :delivered, phone: message.to, raw: params }
      ])

      post_webhook("delivery", params, signature: sign("http://www.example.com/sms/webhooks/twilio/delivery", params))

      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
    end

    it "carries a legacy raw recipient into projection without mutating a mismatched message" do
      message = create_bound_message(customer: customer, provider: "twilio", to: "+14155552671",
                                     status: "sent", vendor_message_id: "SM-LEGACY", sent_at: Time.current)
      params = { "MessageSid" => "SM-LEGACY", "MessageStatus" => "delivered", "To" => "+14155552672" }
      allow_any_instance_of(Sms::Adapters::Twilio).to receive(:parse_delivery_receipt).and_return([
        { vendor_message_id: "SM-LEGACY", status: :delivered, raw: params }
      ])
      original = message.attributes

      post_webhook("delivery", params, signature: sign("http://www.example.com/sms/webhooks/twilio/delivery", params))

      expect(response).to have_http_status(:ok)
      expect(message.reload.attributes).to eq(original)
      expect(Sms::BackendReceipt.last).to have_attributes(processed_at: nil)
      expect(Sms::BackendReceipt.last.payload["phone"]).to eq(params["To"])
    end
  end

  describe "invalid supplied recipients" do
    %w[delivery inbound].each do |kind|
      it "rejects an authenticated #{kind} event with an invalid recipient before persistence" do
        message = create_bound_message(customer: customer, provider: "twilio", to: "+14155552671",
                                       status: "sent", vendor_message_id: "SM-INVALID", sent_at: Time.current)
        params = { "MessageSid" => "SM-INVALID", "MessageStatus" => "delivered", "Body" => "STOP", "AccountSid" => "AC_TEST" }
        params[kind == "inbound" ? "From" : "To"] = "not-a-phone"
        params["To"] = message.to if kind == "inbound"
        url = "http://www.example.com/sms/webhooks/twilio/#{kind}"
        signature = Twilio::Security::RequestValidator.new("AUTH_TOKEN").build_signature_for(url, params)
        original = message.attributes
        expect(Sms::ReceiptInbox).not_to receive(:record!)

        expect { post_webhook(kind, params, signature: signature) }
          .not_to change { [Sms::BackendReceipt.count, Sms::OptOut.count] }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to eq("error" => "invalid_request",
                                          "message" => I18n.t("sms_integration.errors.webhook_recipient_invalid"))
        expect(message.reload.attributes).to eq(original)
      end
    end

    it "does not treat a dropped invalid normalized delivery phone as an omitted recipient" do
      params = { "MessageSid" => "SM-INVALID-NIL", "MessageStatus" => "delivered", "To" => "not-a-phone" }
      allow_any_instance_of(Sms::Adapters::Twilio).to receive(:parse_delivery_receipt).and_return([
        { vendor_message_id: "SM-INVALID-NIL", status: :delivered, phone: nil, raw: params }
      ])
      expect(Sms::ReceiptInbox).not_to receive(:record!)

      post_webhook("delivery", params, signature: sign("http://www.example.com/sms/webhooks/twilio/delivery", params))

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "defensive guard — adapter resolution failure after routing" do
    it "returns 404 when the adapter can't be resolved (rescue ArgumentError)" do
      allow(Sms::CredentialResolver).to receive(:call).and_return(twilio_credential)
      allow(Sms::Adapters).to receive(:for).and_call_original
      allow(Sms::Adapters).to receive(:for).with("twilio").and_raise(ArgumentError, "boom")

      post "/sms/webhooks/twilio/delivery", params: { "MessageSid" => "SM1" },
           headers: { "X-Twilio-Signature" => "whatever" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "inbound STOP (kind=inbound)" do
    let!(:sms_module) { enable_module!("sms", customer, name: "SMS") }
    let!(:template) do
      create(:sms_template, key: "verify_code", variables: %w[code],
             provider_template_codes: { "twilio" => "HX1" })
    end

    it "records a GLOBAL opt-out row on a valid STOP, and suppresses a subsequent Send to that number" do
      url    = "http://www.example.com/sms/webhooks/twilio/inbound"
      params = { "From" => "+14155552671", "Body" => "STOP" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/inbound", params: params, headers: { "X-Twilio-Signature" => sig }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
      expect(response.body).to eq("<Response/>")

      opt_out = Sms::OptOut.find_by(phone_e164: "+14155552671")
      expect(opt_out).to be_present
      expect(opt_out.customer_id).to be_nil
      expect(opt_out.provider).to eq("twilio")
      expect(opt_out.reason).to eq("inbound:STOP")

      Current.customer = customer
      msg = Sms::Activities::Send.call(customer: customer, to: "+14155552671",
                                       template_key: "verify_code", vars: { "code" => "1" })
      expect(msg.status).to eq("suppressed")
      Current.customer = nil
    end

    it "is a no-op (still 200, no opt-out row) when STOP has a blank From" do
      url    = "http://www.example.com/sms/webhooks/twilio/inbound"
      params = { "From" => "", "Body" => "STOP" }
      sig    = sign(url, params)

      expect {
        post "/sms/webhooks/twilio/inbound", params: params, headers: { "X-Twilio-Signature" => sig }
      }.not_to change(Sms::OptOut, :count)
      expect(response).to have_http_status(:ok)
      expect(Sms::OptOut.find_by(phone_e164: "+")).to be_nil
    end

    it "is a no-op (still 200, no opt-out row) for a non-STOP inbound message" do
      url    = "http://www.example.com/sms/webhooks/twilio/inbound"
      params = { "From" => "+14155552671", "Body" => "hello" }
      sig    = sign(url, params)

      expect {
        post "/sms/webhooks/twilio/inbound", params: params, headers: { "X-Twilio-Signature" => sig }
      }.not_to change(Sms::OptOut, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "unknown kind" do
    it "returns 404 for a signature-valid request with an unrecognized kind" do
      url    = "http://www.example.com/sms/webhooks/twilio/bogus"
      params = { "MessageSid" => "SM1" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/bogus", params: params, headers: { "X-Twilio-Signature" => sig }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "no retained credential for the provider" do
    it "returns 503 when there is no retained twilio credential" do
      twilio_credential.destroy!

      url    = "http://www.example.com/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM1", "MessageStatus" => "delivered" }
      sig    = sign(url, params)

      post "/sms/webhooks/twilio/delivery", params: params, headers: { "X-Twilio-Signature" => sig }
      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe "poll-only provider has no webhook (S-BUG-2)" do
    it "returns 404 for a POST to a poll-only adapter's webhook (Aliyun), not a 500" do
      # Aliyun is :poll and does not implement verify_webhook!; the endpoint must
      # reject cleanly rather than raising an unauthenticated NotImplementedError.
      post "/sms/webhooks/aliyun/delivery", params: { "anything" => "x" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "multi-mode credential verification (S-BUG-3)" do
    let!(:twilio_production) do
      create(:sms_credential, provider: "twilio", mode: "production", status: "active",
             access_key_id: "AC_PROD", access_key_secret: "PROD_TOKEN",
             config: { "messaging_service_sid" => "MG2" })
    end

    def sign_with(token, url, params)
      data = url.to_s + params.sort_by(&:first).map { |k, v| "#{k}#{v}" }.join
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", token, data))
    end

    it "accepts a DLR signed by a NON-default-mode credential's token" do
      msg = create_bound_message(credential: twilio_production, customer: customer, provider: "twilio", status: "sent",
                   vendor_message_id: "SM-PROD", sent_at: Time.zone.now)

      url    = "http://www.example.com/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM-PROD", "MessageStatus" => "delivered" }
      sig    = sign_with("PROD_TOKEN", url, params)

      post "/sms/webhooks/twilio/delivery", params: params, headers: { "X-Twilio-Signature" => sig }

      expect(response).to have_http_status(:ok)
      expect(msg.reload.status).to eq("delivered")
    end
  end

  describe "verified receipt ownership and retention" do
    let(:delivery_url) { "http://www.example.com/sms/webhooks/twilio/delivery" }

    context "when retained modes share a signing token" do
      let!(:shared_credential) do
        create(:sms_credential, provider: "twilio", mode: "production", status: "disabled",
               access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN")
      end

      it "binds a delivery receipt to the recorded second credential" do
        message = create_bound_message(credential: shared_credential, customer: customer, provider: "twilio",
                                       status: "sent", vendor_message_id: "SM-SHARED", sent_at: Time.current)
        params = { "MessageSid" => "SM-SHARED", "MessageStatus" => "delivered", "AccountSid" => "AC_TEST" }

        post_webhook("delivery", params, signature: sign(delivery_url, params))

        expect(response).to have_http_status(:ok)
        expect(message.reload.status).to eq("delivered")
        expect(Sms::BackendReceipt.last.credential_id).to eq(shared_credential.id)
      end

      it "returns a controlled conflict for an ambiguous early receipt without assigning a mode" do
        params = { "MessageSid" => "SM-AMBIGUOUS", "MessageStatus" => "delivered", "mode" => "production" }

        expect { post_webhook("delivery", params, signature: sign(delivery_url, params)) }
          .not_to change(Sms::BackendReceipt, :count)
        expect(response).to have_http_status(:conflict)
      end

      it "uses the authenticated AccountSid to persist an unmatched event for a unique account" do
        shared_credential.update!(access_key_id: "AC_SECOND")
        params = { "MessageSid" => "SM-UNMATCHED", "MessageStatus" => "delivered", "AccountSid" => "AC_SECOND" }

        post_webhook("delivery", params, signature: sign(delivery_url, params))

        expect(response).to have_http_status(:ok)
        expect(Sms::BackendReceipt.last).to have_attributes(credential_id: shared_credential.id, processed_at: nil)
      end

      it "rejects an authenticated sender AccountSid belonging to neither retained row" do
        params = { "MessageSid" => "SM-FOREIGN", "MessageStatus" => "delivered", "AccountSid" => "AC_FOREIGN" }

        expect { post_webhook("delivery", params, signature: sign(delivery_url, params)) }
          .not_to change(Sms::BackendReceipt, :count)
        expect(response).to have_http_status(:forbidden)
      end

      it "resolves an inbound opt-out using unique actual-contact credential metadata" do
        message = create_bound_message(credential: shared_credential, customer: customer, provider: "twilio",
                                       to: "+14155552671", status: "sent", vendor_message_id: "SM-CONTACT", sent_at: Time.current)
        url = "http://www.example.com/sms/webhooks/twilio/inbound"
        params = { "From" => message.to, "Body" => "STOP", "AccountSid" => "AC_TEST" }

        post_webhook("inbound", params, signature: sign(url, params))

        expect(response).to have_http_status(:ok)
        expect(Sms::BackendReceipt.last.credential_id).to eq(shared_credential.id)
        expect(Sms::OptOut.find_by(phone_e164: message.to)).to be_present
      end

      (Sms::Adapters::Twilio::STOP_WORDS.map { |keyword| { "Body" => " #{keyword.downcase} " } } +
        [{ "Body" => "请停止发送短信", "OptOutType" => "STOP" }]).each do |classification|
        it "binds #{classification.inspect} to the From contact, not inbound To, for the same AccountSid" do
          sender_number = "+14155552672"
          sandbox_message = create_bound_message(customer: customer, provider: "twilio", to: sender_number,
                                                 status: "sent", vendor_message_id: "SM-SANDBOX-SENDER", sent_at: Time.current)
          contact_message = create_bound_message(credential: shared_credential, customer: customer, provider: "twilio",
                                                 to: "+14155552671", status: "sent", vendor_message_id: "SM-PROD-CONTACT", sent_at: Time.current)
          params = classification.merge("From" => "+1 (415) 555-2671", "To" => sender_number,
                                        "AccountSid" => "AC_TEST", "MessageSid" => "SM-INBOUND-REPLY")
          url = "http://www.example.com/sms/webhooks/twilio/inbound"
          signature = Twilio::Security::RequestValidator.new("AUTH_TOKEN").build_signature_for(url, params)
          originals = [sandbox_message.attributes, contact_message.attributes]

          expect { post_webhook("inbound", params, signature: signature) }.to change(Sms::OptOut, :count).by(1)

          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq("application/xml")
          expect(response.body).to eq("<Response/>")
          expect(Sms::BackendReceipt.last).to have_attributes(credential_id: shared_credential.id)
          expect(Sms::BackendReceipt.last.payload).to include("phone" => contact_message.to, "raw" => params)
          expect(Sms::OptOut.find_by(phone_e164: contact_message.to)).to be_present
          expect(Sms::OptOut.find_by(phone_e164: sender_number)).to be_nil
          expect([sandbox_message.reload.attributes, contact_message.reload.attributes]).to eq(originals)
        end
      end

      it "retains ambiguity 409 when both modes actually contacted the same From number" do
        [twilio_credential, shared_credential].each do |credential|
          create_bound_message(credential: credential, customer: customer, provider: "twilio", to: "+14155552671",
                               status: "sent", vendor_message_id: "SM-CONTACT-#{credential.mode}", sent_at: Time.current)
        end
        params = { "From" => "+14155552671", "To" => "+14155552672", "Body" => "退订",
                   "OptOutType" => "STOP", "AccountSid" => "AC_TEST" }
        url = "http://www.example.com/sms/webhooks/twilio/inbound"
        signature = Twilio::Security::RequestValidator.new("AUTH_TOKEN").build_signature_for(url, params)

        expect { post_webhook("inbound", params, signature: signature) }
          .not_to change { [Sms::BackendReceipt.count, Sms::OptOut.count] }
        expect(response).to have_http_status(:conflict)
      end

      it "does not bind a valid delivery receipt to a different recipient in the same account" do
        message = create_bound_message(credential: shared_credential, customer: customer, provider: "twilio",
                                       to: "+14155552671", status: "sent", vendor_message_id: "SM-MISMATCH", sent_at: Time.current)
        params = { "MessageSid" => "SM-MISMATCH", "MessageStatus" => "delivered", "To" => "+14155552672", "AccountSid" => "AC_TEST" }
        original = message.attributes

        expect { post_webhook("delivery", params, signature: sign(delivery_url, params)) }
          .not_to change(Sms::BackendReceipt, :count)
        expect(response).to have_http_status(:conflict)
        expect(message.reload.attributes).to eq(original)
      end
    end

    it "retains the disabled original credential's delivery receipt and deduplicates redelivery" do
      message = create_bound_message(customer: customer, provider: "twilio", status: "sent",
                                     vendor_message_id: "SM-DISABLED", sent_at: Time.current)
      twilio_credential.update!(status: "disabled")
      params = { "MessageSid" => "SM-DISABLED", "MessageStatus" => "delivered" }
      signature = sign(delivery_url, params)

      expect { post_webhook("delivery", params, signature: signature) }.to change(Sms::BackendReceipt, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
      expect(Sms::BackendReceipt.last.credential_id).to eq(twilio_credential.id)
      expect { post_webhook("delivery", params, signature: signature) }.not_to change(Sms::BackendReceipt, :count)
    end

    it "does not apply a valid receipt to a message owned by a different credential" do
      other = create(:sms_credential, provider: "twilio", mode: "production", status: "disabled",
                     access_key_id: "AC_OLD", access_key_secret: "OLD_TOKEN")
      message = create_bound_message(credential: other, customer: customer, provider: "twilio",
                                     status: "sent", vendor_message_id: "SM-OWNED", sent_at: Time.current)
      params = { "MessageSid" => "SM-OWNED", "MessageStatus" => "delivered" }
      post_webhook("delivery", params, signature: sign(delivery_url, params))

      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("sent")
      expect(Sms::BackendReceipt.last).to have_attributes(credential_id: twilio_credential.id, processed_at: nil)
    end

    it "persists an early receipt for later vendor-ID correlation" do
      params = { "MessageSid" => "SM-EARLY", "MessageStatus" => "delivered" }
      post_webhook("delivery", params, signature: sign(delivery_url, params))
      receipt = Sms::BackendReceipt.last
      expect(receipt.processed_at).to be_nil
      message = create_bound_message(customer: customer, provider: "twilio", status: "pending")
      message.mark_sent!(vendor_message_id: "SM-EARLY", raw: {})

      Sms::ReceiptInbox.reconcile(provider: "twilio", vendor_message_id: "SM-EARLY")

      expect(message.reload.status).to eq("delivered")
      expect(receipt.reload.processed_at).to be_present
    end

    it "does not match a receipt with no vendor ID to an unrelated NULL-ID message" do
      message = create_bound_message(customer: customer, provider: "twilio", status: "pending")
      params = { "MessageStatus" => "delivered" }
      post_webhook("delivery", params, signature: sign(delivery_url, params))

      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("pending")
    end

    it "does not persist a forged receipt" do
      expect {
        post_webhook("delivery", { "MessageSid" => "forged" }, signature: "forged")
      }.not_to change(Sms::BackendReceipt, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "records inbound opt-outs with the verified retained credential ID" do
      twilio_credential.update!(status: "disabled")
      url = "http://www.example.com/sms/webhooks/twilio/inbound"
      params = { "From" => "+14155552671", "Body" => "STOP" }
      post_webhook("inbound", params, signature: sign(url, params))

      expect(response).to have_http_status(:ok)
      expect(Sms::BackendReceipt.last).to have_attributes(credential_id: twilio_credential.id)
      expect(Sms::OptOut.find_by(phone_e164: "+14155552671")).to be_present
    end
  end
end
