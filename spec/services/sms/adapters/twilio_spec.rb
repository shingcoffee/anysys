# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Adapters::Twilio do
  let(:credential) do
    build_stubbed(:sms_credential, provider: "twilio",
                  access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN",
                  config: { "messaging_service_sid" => "MG123" }, mode: "sandbox")
  end
  let(:template) do
    build_stubbed(:sms_template, provider_template_codes: { "twilio" => "HX123" })
  end
  let(:adapter)  { described_class.new(credential: credential) }
  let(:messages_url) { "https://api.twilio.com/2010-04-01/Accounts/AC_TEST/Messages.json" }

  describe "class interface" do
    it_behaves_like "an SMS adapter class interface",
                    key: "twilio", delivery_mechanism: :webhook,
                    config_fields: %i[messaging_service_sid from]

    describe ".configured?" do
      it "is true with key/secret + messaging_service_sid" do
        cred = build_stubbed(:sms_credential, provider: "twilio", access_key_id: "id",
                             access_key_secret: "secret", config: { "messaging_service_sid" => "MG1" })
        expect(described_class.configured?(cred)).to be(true)
      end

      it "is true with key/secret + from (no messaging_service_sid)" do
        cred = build_stubbed(:sms_credential, provider: "twilio", access_key_id: "id",
                             access_key_secret: "secret", config: { "from" => "+15551234567" })
        expect(described_class.configured?(cred)).to be(true)
      end

      it "is false without either messaging_service_sid or from" do
        cred = build_stubbed(:sms_credential, provider: "twilio", access_key_id: "id",
                             access_key_secret: "secret", config: {})
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false without access_key_secret" do
        cred = build_stubbed(:sms_credential, provider: "twilio", access_key_id: "id",
                             access_key_secret: nil, config: { "from" => "+15551234567" })
        expect(described_class.configured?(cred)).to be(false)
      end
    end
  end

  describe "#send_message" do
    it "POSTs Messages.json with basic auth and MessagingServiceSid when present" do
      stub_request(:post, messages_url).to_return(
        status: 201, body: { "sid" => "SM123" }.to_json
      )

      result = adapter.send_message(to: "+15559876543", template: template, template_params: { "1" => "1234" })

      expect(result[:vendor_message_id]).to eq("SM123")
      expect(WebMock).to have_requested(:post, messages_url).with(
        headers: { "Authorization" => "Basic #{Base64.strict_encode64('AC_TEST:AUTH_TOKEN')}" }
      ) { |req|
        body = URI.decode_www_form(req.body).to_h
        body["To"] == "+15559876543" &&
          body["ContentSid"] == "HX123" &&
          body["ContentVariables"] == '{"1":"1234"}' &&
          body["MessagingServiceSid"] == "MG123" &&
          body["StatusCallback"].to_s.include?("/sms/webhooks/twilio/delivery") &&
          !body.key?("From")
      }
    end

    it "falls back to From when messaging_service_sid is absent" do
      cred = build_stubbed(:sms_credential, provider: "twilio", access_key_id: "AC_TEST",
                           access_key_secret: "AUTH_TOKEN", config: { "from" => "+15550000000" })
      a = described_class.new(credential: cred)
      stub_request(:post, messages_url).to_return(status: 201, body: { "sid" => "SM124" }.to_json)

      a.send_message(to: "+15559876543", template: template, template_params: {})

      expect(WebMock).to have_requested(:post, messages_url).with { |req|
        body = URI.decode_www_form(req.body).to_h
        body["From"] == "+15550000000" && !body.key?("MessagingServiceSid")
      }
    end

    it "treats blank sid acceptance as ambiguous TransportError" do
      stub_request(:post, messages_url).to_return(status: 200, body: { "sid" => "" }.to_json)
      expect {
        adapter.send_message(to: "+15559876543", template: template, template_params: {})
      }.to raise_error(Sms::Errors::TransportError)
    end

    it "raises ApiError when error_code is present" do
      stub_request(:post, messages_url).to_return(
        status: 400, body: { "sid" => "SM1", "error_code" => 21211, "message" => "invalid To" }.to_json
      )
      expect {
        adapter.send_message(to: "bad", template: template, template_params: {})
      }.to raise_error(Sms::Errors::ApiError, /invalid To/)
    end

    it "does not accept a successful-looking 502 body that the SDK replaces with a server error" do
      stub_request(:post, messages_url).to_return(
        status: 502, body: { "sid" => "SM_LOOKS_OK", "auth_token" => "SECRET_ECHO" }.to_json
      )
      expect {
        adapter.send_message(to: "+15559876543", template: template, template_params: {})
      }.to raise_error(Sms::Errors::ApiError) { |error|
        # twilio-ruby replaces 5xx bodies before constructing RestError; there
        # is no usable SID at this boundary. The worker quarantines HTTP 5xx.
        expect(error.code).to eq(502)
        expect(error.payload).not_to have_key("sid")
        expect(error.payload).not_to have_key("auth_token")
      }
    end

    it "retains a known SID from an unclassified unsuccessful resource response" do
      stub_request(:post, messages_url).to_return(status: 400, body: {
        sid: "SM_LOOKS_OK", status: "queued", auth_token: "SECRET_ECHO"
      }.to_json)
      expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
        .to raise_error(Sms::Errors::TransportError) { |error|
          expect(error.vendor_message_id).to eq("SM_LOOKS_OK")
          expect(error.payload).to eq("sid" => "SM_LOOKS_OK", "status" => "queued")
        }
    end

    it "raises TransportError on network failure" do
      stub_request(:post, messages_url).to_raise(Errno::ECONNREFUSED.new("boom"))
      expect {
        adapter.send_message(to: "+15559876543", template: template, template_params: {})
      }.to raise_error(Sms::Errors::TransportError)
    end

    ["null", "[]", "not-json", { sid: [] }.to_json, { sid: " " }.to_json,
     { sid: "SM1", status: [] }.to_json, { sid: "SM1", error_code: [21610] }.to_json].each do |body|
      it "treats malformed HTTP success #{body.inspect} as ambiguous" do
        stub_request(:post, messages_url).to_return(status: 201, body: body)
        expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
          .to raise_error(Sms::Errors::TransportError)
      end
    end

    it "retains the real SDK's known SID and selected payload when a 201 status is malformed" do
      stub_request(:post, messages_url).to_return(status: 201, body: {
        sid: "SM_VALID", status: [], to: "+14155552671", auth_token: "SECRET_ECHO"
      }.to_json)
      expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
        .to raise_error(Sms::Errors::TransportError) { |error|
          expect(error.vendor_message_id).to eq("SM_VALID")
          expect(error.payload).to include("sid" => "SM_VALID", "status" => [], "to" => "+14155552671")
          expect(error.payload).not_to have_key("auth_token")
        }
    end

    ["SM/other", "a" * 129, []].each do |sid|
      it "does not retain malformed SID #{sid.inspect} from an ambiguous 201" do
        stub_request(:post, messages_url).to_return(status: 201, body: { sid: sid, status: [] }.to_json)
        expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
          .to raise_error(Sms::Errors::TransportError) { |error| expect(error.vendor_message_id).to be_nil }
      end
    end

    [{ status: [] }, { date_updated: "not-a-date" }, { date_created: "not-a-date" }, { date_sent: [] },
     { error_code: [21610] }, { error_code: "not-a-number" }, { error_code: 0 }, { num_segments: "many" }].each do |malformed|
      it "validates original 201 fields before trusting SDK coercion: #{malformed.inspect}" do
        stub_request(:post, messages_url).to_return(status: 201, body: {
          sid: "SM_VALID", status: "queued", to: "+14155552671", body: "PRIVATE_TEXT", auth_token: "SECRET_ECHO"
        }.merge(malformed).to_json)
        expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
          .to raise_error(Sms::Errors::TransportError) { |error|
            expect(error.vendor_message_id).to eq("SM_VALID")
            expect(error.payload).to include(malformed.stringify_keys)
            expect(error.payload).not_to have_key("body")
            expect(error.payload).not_to have_key("auth_token")
          }
      end
    end

    it "accepts null dates/codes and valid RFC 2822 resource timestamps without strict SID assumptions" do
      raw = { sid: "SM_FAKE_VALID", status: "queued", error_code: nil, date_updated: nil,
              date_sent: nil, date_created: "Tue, 13 Oct 2026 10:00:00 +0000", num_segments: "0" }
      stub_request(:post, messages_url).to_return(status: 201, body: raw.to_json)
      expect(adapter.send_message(to: "+14155552671", template: template, template_params: {}))
        .to include(vendor_message_id: "SM_FAKE_VALID", raw: raw.stringify_keys)
    end

    it "does not swallow argument errors from application request preparation" do
      allow(adapter).to receive(:message_params).and_raise(ArgumentError, "application preparation bug")
      expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
        .to raise_error(ArgumentError, "application preparation bug")
      expect(WebMock).not_to have_requested(:post, messages_url)
    end

    it "does not relabel an SDK construction bug when its original response is valid" do
      stub_request(:post, messages_url).to_return(status: 201, body: { sid: "SM_VALID", status: "queued" }.to_json)
      allow(::Twilio).to receive(:deserialize_rfc2822).and_raise(ArgumentError, "SDK construction bug")
      expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
        .to raise_error(ArgumentError, "SDK construction bug")
    end

    it "does not reuse a previous call's SID when the next SDK JSON response cannot be parsed" do
      stub_request(:post, messages_url).to_return(
        { status: 201, body: { sid: "SM_PREVIOUS", status: "queued" }.to_json },
        { status: 201, body: "not-json" }
      )
      expect(adapter).to receive(:rest_client).twice.and_call_original
      expect(adapter.send_message(to: "+14155552671", template: template, template_params: {})[:vendor_message_id]).to eq("SM_PREVIOUS")
      expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
        .to raise_error(Sms::Errors::TransportError) { |error| expect(error.vendor_message_id).to be_nil }
      expect(WebMock).to have_requested(:post, messages_url).twice
    end

    it "does not relabel request configuration errors before any SDK response exists" do
      messages = double("messages")
      allow(messages).to receive(:create).and_raise(TypeError, "SDK request configuration bug")
      client = double("client", messages: messages)
      allow(adapter).to receive(:rest_client).and_return(client)
      expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
        .to raise_error(TypeError, "SDK request configuration bug")
    end

    it "keeps a nonnumeric original rejection code ambiguous without coercing it into failure" do
      stub_request(:post, messages_url).to_return(status: 400, body: {
        sid: "SM_VALID", code: "not-a-number", message: "Unclassified", auth_token: "SECRET_ECHO"
      }.to_json)
      expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
        .to raise_error(Sms::Errors::TransportError) { |error|
          expect(error.vendor_message_id).to eq("SM_VALID")
          expect(error.payload).to include("code" => "not-a-number")
          expect(error.payload).not_to have_key("auth_token")
        }
    end

    context "documented REST exception envelopes" do
      [21610, 21211].each do |code|
        [nil, "SM_OPTIONAL"].each do |sid|
          it "preserves HTTP 400 rejection #{code} with optional SID #{sid.inspect}" do
            body = { status: 400, code: code, message: "Documented rejection", more_info: "https://www.twilio.com/docs/api/errors/#{code}" }
            body[:sid] = sid if sid
            stub_request(:post, messages_url).to_return(status: 400, body: body.to_json)
            expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
              .to raise_error(Sms::Errors::ApiError) { |error|
                expect(error.code).to eq(code)
                expect(error.payload).to include("status" => 400, "code" => code)
                expect(error.payload).not_to have_key("more_info")
              }
          end
        end
      end

      it "accepts error_code as the alternate positive code without applying resource validation" do
        stub_request(:post, messages_url).to_return(status: 400, body: {
          status: 400, error_code: 21610, message: "Recipient opted out", sid: "SM_OPTIONAL", date_updated: "not-a-resource-date"
        }.to_json)
        expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
          .to raise_error(Sms::Errors::ApiError) { |error| expect(error.code).to eq(21610) }
      end

      [422, 600, "400", []].each do |status|
        it "keeps inconsistent or malformed exception status #{status.inspect} ambiguous" do
          stub_request(:post, messages_url).to_return(status: 400, body: {
            status: status, code: 21610, message: "Unconfirmed", sid: "SM_AMBIGUOUS"
          }.to_json)
          expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
            .to raise_error(Sms::Errors::TransportError) { |error| expect(error.vendor_message_id).to eq("SM_AMBIGUOUS") }
        end
      end

      [nil, 400].each do |code|
        it "keeps an unclassified HTTP rejection with code #{code.inspect} unknown" do
          stub_request(:post, messages_url).to_return(status: 400, body: { message: "Unclassified", code: code }.compact.to_json)
          expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
            .to raise_error(Sms::Errors::TransportError)
        end
      end

      it "does not mask an SDK construction bug behind a valid HTTP exception envelope" do
        stub_request(:post, messages_url).to_return(status: 400, body: {
          status: 400, code: 21610, message: "Recipient opted out"
        }.to_json)
        allow_any_instance_of(::Twilio::REST::RestError).to receive(:format_message).and_raise(ArgumentError, "SDK exception construction bug")
        expect { adapter.send_message(to: "+14155552671", template: template, template_params: {}) }
          .to raise_error(ArgumentError, "SDK exception construction bug")
      end
    end
  end

  describe "#query" do
    let(:message) { build_stubbed(:sms_message, provider: "twilio", vendor_message_id: "SM1", to: "+14155552671") }
    let(:query_url) { "https://api.twilio.com/2010-04-01/Accounts/AC_TEST/Messages/SM1.json" }

    it "fetches the actual message resource and normalizes all delivery facts" do
      raw = { sid: "SM1", status: "undelivered", to: "+14155552671", error_code: 21610,
              error_message: "Recipient opted out", num_segments: "2", date_updated: "Tue, 13 Oct 2026 10:00:00 +0000" }
      stub_request(:get, query_url).to_return(status: 200, body: raw.to_json)

      expect(adapter.query(message: message)).to include(
        status: :failed, provider_status: "undelivered", phone: "+14155552671", failure_code: "21610",
        failure_message: "Recipient opted out", segments: 2, occurred_at: Time.utc(2026, 10, 13, 10)
      )
      expect(WebMock).to have_requested(:get, query_url)
    end

    it "safely handles a resource without optional SDK attributes" do
      resource = Struct.new(:sid, :status, :to).new("SM1", "delivered", "+14155552671")
      context = double(fetch: resource)
      client = double("client")
      allow(client).to receive(:messages).with("SM1").and_return(context)
      allow(adapter).to receive(:rest_client).and_return(client)
      expect(adapter.query(message: message)).to include(status: :delivered, phone: "+14155552671")
      expect(adapter.query(message: message)).not_to have_key(:segments)
    end

    it "raises a controlled error for missing or mismatched resource identity" do
      stub_request(:get, query_url).to_return(status: 200, body: { sid: "OTHER", status: "delivered" }.to_json)
      expect { adapter.query(message: message) }.to raise_error(Sms::Errors::TransportError)
    end

    it "maps REST query failures and transport errors" do
      stub_request(:get, query_url).to_return(status: 404, body: { code: 20404, message: "Not found" }.to_json)
      expect { adapter.query(message: message) }.to raise_error(Sms::Errors::ApiError, /Not found/)
      stub_request(:get, query_url).to_timeout
      expect { adapter.query(message: message) }.to raise_error(Sms::Errors::TransportError)
    end

    [{ status: [] }, { date_updated: "not-a-date" }, { date_created: "not-a-date" }, { date_sent: [] },
     { error_code: [21610] }, { error_code: "not-a-number" }, { error_code: 0 }, { num_segments: "many" }].each do |malformed|
      it "rejects malformed original query fields without a false failure: #{malformed.inspect}" do
        stub_request(:get, query_url).to_return(status: 200, body: {
          sid: "SM1", status: "failed", to: message.to, body: "PRIVATE_TEXT", auth_token: "SECRET_ECHO"
        }.merge(malformed).to_json)
        expect { adapter.query(message: message) }.to raise_error(Sms::Errors::TransportError) { |error|
          expect(error.vendor_message_id).to eq("SM1")
          expect(error.payload).to include(malformed.stringify_keys)
          expect(error.payload).not_to have_key("body")
          expect(error.payload).not_to have_key("auth_token")
        }
      end
    end

    it "does not swallow application projection bugs after a valid SDK response" do
      stub_request(:get, query_url).to_return(status: 200, body: { sid: "SM1", status: "delivered" }.to_json)
      allow(adapter).to receive(:delivery_event).and_raise(NoMethodError, "application projection bug")
      expect { adapter.query(message: message) }.to raise_error(NoMethodError, /application projection bug/)
    end

    it "accepts the documented numeric HTTP status on a query REST exception" do
      stub_request(:get, query_url).to_return(status: 404, body: {
        status: 404, code: 20404, message: "Not found", more_info: "https://www.twilio.com/docs/api/errors/20404"
      }.to_json)
      expect { adapter.query(message: message) }.to raise_error(Sms::Errors::ApiError) { |error|
        expect(error.code).to eq(20404)
        expect(error.payload).not_to have_key("more_info")
      }
    end
  end

  describe "#verify_webhook!" do
    def fake_request(url:, params:, signature:)
      double("request",
             headers: { "X-Twilio-Signature" => signature },
             original_url: url,
             request_parameters: params)
    end

    def compute_signature(url, params, secret)
      data = url.to_s + params.sort_by(&:first).map { |k, v| "#{k}#{v}" }.join
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", secret, data))
    end

    it "does not raise for a valid signature" do
      url    = "https://example.test/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM1", "MessageStatus" => "delivered" }
      sig    = compute_signature(url, params, "AUTH_TOKEN")

      expect { adapter.verify_webhook!(fake_request(url: url, params: params, signature: sig)) }.not_to raise_error
    end

    it "raises SignatureInvalid for a forged/wrong signature" do
      url    = "https://example.test/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM1", "MessageStatus" => "delivered" }

      expect {
        adapter.verify_webhook!(fake_request(url: url, params: params, signature: "forged"))
      }.to raise_error(Sms::Errors::SignatureInvalid)
    end

    it "raises SignatureInvalid when the header is missing" do
      url    = "https://example.test/sms/webhooks/twilio/delivery"
      params = { "MessageSid" => "SM1" }

      expect {
        adapter.verify_webhook!(fake_request(url: url, params: params, signature: ""))
      }.to raise_error(Sms::Errors::SignatureInvalid)
    end
  end

  describe "#parse_delivery_receipt" do
    def request_with(params)
      double("request", request_parameters: params)
    end

    it "maps MessageStatus=delivered to :delivered, keyed by MessageSid" do
      out = adapter.parse_delivery_receipt(request_with("MessageSid" => "SM1", "MessageStatus" => "delivered"))
      expect(out.first).to include(vendor_message_id: "SM1", status: :delivered, provider_status: "delivered", raw: { "MessageSid" => "SM1", "MessageStatus" => "delivered" })
    end

    %w[undelivered failed].each do |status|
      it "maps MessageStatus=#{status} to :failed" do
        out = adapter.parse_delivery_receipt(request_with("MessageSid" => "SM1", "MessageStatus" => status))
        expect(out.first[:status]).to eq(:failed)
      end
    end

    %w[sent queued sending accepted received].each do |status|
      it "maps interim MessageStatus=#{status} to :unknown" do
        out = adapter.parse_delivery_receipt(request_with("MessageSid" => "SM1", "MessageStatus" => status))
        expect(out.first[:status]).to eq(:unknown)
      end
    end

    it "maps an unrecognized MessageStatus to :unknown" do
      out = adapter.parse_delivery_receipt(request_with("MessageSid" => "SM1", "MessageStatus" => "something_new"))
      expect(out.first[:status]).to eq(:unknown)
    end

    it "falls back to SmsSid when MessageSid is absent" do
      out = adapter.parse_delivery_receipt(request_with("SmsSid" => "SM2", "MessageStatus" => "delivered"))
      expect(out.first[:vendor_message_id]).to eq("SM2")
    end

    it "returns [] when no sid is present" do
      out = adapter.parse_delivery_receipt(request_with("MessageStatus" => "delivered"))
      expect(out).to eq([])
    end

    it "normalizes recipient, error details, actual segments and zoned event time" do
      params = { "MessageSid" => "SM1", "MessageStatus" => "undelivered", "To" => "+1 (415) 555-2671",
                 "ErrorCode" => "21610", "ErrorMessage" => "Recipient opted out", "NumSegments" => "3",
                 "DateUpdated" => "2026-10-13T10:00:00Z", "AccountSid" => "AC_TEST", "MessagingServiceSid" => "MG123" }
      expect(adapter.parse_delivery_receipt(request_with(params)).first).to include(
        phone: "+14155552671", provider_status: "undelivered", failure_code: "21610", failure_message: "Recipient opted out",
        segments: 3, occurred_at: Time.utc(2026, 10, 13, 10), account_sid: "AC_TEST", messaging_service_sid: "MG123"
      )
    end

    it "retains carrier done-date without inventing an undocumented timezone or segment count" do
      params = { "MessageSid" => "SM1", "MessageStatus" => "delivered", "RawDlrDoneDate" => "2610131000", "NumSegments" => "0" }
      event = adapter.parse_delivery_receipt(request_with(params)).first
      expect(event).not_to have_key(:occurred_at)
      expect(event).not_to have_key(:segments)
      expect(event[:raw]["RawDlrDoneDate"]).to eq("2610131000")
    end
  end

  describe "#parse_inbound" do
    def request_with(params)
      double("request", request_parameters: params)
    end

    Sms::Adapters::Twilio::STOP_WORDS.each do |word|
      it "recognizes '#{word}' (case-insensitive, trimmed) as an opt-out" do
        out = adapter.parse_inbound(request_with("From" => "+15559876543", "Body" => " #{word.downcase} "))
        expect(out).to include(phone: "+15559876543", keyword: word)
      end
    end

    it "returns nil for a non-STOP body" do
      out = adapter.parse_inbound(request_with("From" => "+15559876543", "Body" => "hello there"))
      expect(out).to be_nil
    end

    it "accepts a signed authoritative STOP classification with localized body and inbound identity" do
      params = { "From" => "+1 (415) 555-2671", "Body" => "退订", "OptOutType" => "STOP", "MessageSid" => "SM_INBOUND",
                 "AccountSid" => "AC_TEST", "MessagingServiceSid" => "MG123" }
      url = "https://example.test/sms/webhooks/twilio/inbound"
      signature = ::Twilio::Security::RequestValidator.new("AUTH_TOKEN").build_signature_for(url, params)
      request = double(headers: { "X-Twilio-Signature" => signature }, original_url: url, request_parameters: params)
      adapter.verify_webhook!(request)
      expect(adapter.parse_inbound(request)).to include(phone: "+14155552671", keyword: "STOP", vendor_message_id: "SM_INBOUND",
                                                       account_sid: "AC_TEST", messaging_service_sid: "MG123", raw: params)
    end

    %w[START HELP].each do |classification|
      it "ignores authoritative #{classification}, including contradictory STOP body" do
        expect(adapter.parse_inbound(request_with("From" => "+14155552671", "Body" => "STOP", "OptOutType" => classification))).to be_nil
      end
    end
  end
end
