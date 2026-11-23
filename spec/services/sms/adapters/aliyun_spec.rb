# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Adapters::Aliyun do
  let(:credential) do
    build_stubbed(:sms_credential, provider: "aliyun",
                  access_key_id: "AKID", access_key_secret: "AKS",
                  config: { "sign_name" => "TestCo", "region" => "cn-hangzhou" }, mode: "sandbox")
  end
  let(:template) do
    build_stubbed(:sms_template, provider_template_codes: { "aliyun" => "SMS_1" })
  end
  let(:adapter)  { described_class.new(credential: credential) }
  let(:endpoint) { "https://dysmsapi.aliyuncs.com/" }

  describe "class interface" do
    it_behaves_like "an SMS adapter class interface",
                    key: "aliyun", delivery_mechanism: :poll,
                    config_fields: %i[sign_name region]

    describe ".configured?" do
      it "is true when key/secret/sign_name are all present" do
        cred = build_stubbed(:sms_credential, provider: "aliyun",
                             access_key_id: "id", access_key_secret: "secret",
                             config: { "sign_name" => "TestCo" })
        expect(described_class.configured?(cred)).to be(true)
      end

      it "is false when sign_name is missing" do
        cred = build_stubbed(:sms_credential, provider: "aliyun",
                             access_key_id: "id", access_key_secret: "secret", config: {})
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false when access_key_id is missing" do
        cred = build_stubbed(:sms_credential, provider: "aliyun",
                             access_key_id: nil, access_key_secret: "secret",
                             config: { "sign_name" => "TestCo" })
        expect(described_class.configured?(cred)).to be(false)
      end
    end
  end

  describe "#send_message" do
    it "POSTs to dysmsapi and maps Code=OK to a vendor_message_id" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "Code" => "OK", "BizId" => "BIZ-1", "Message" => "OK" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = adapter.send_message(
        to: "+8613800138000", template: template, template_params: { "code" => "1234" }
      )

      expect(result[:vendor_message_id]).to eq("BIZ-1")
      expect(WebMock).to have_requested(:post, endpoint).with { |req|
        body = URI.decode_www_form(req.body).to_h
        body["Action"] == "SendSms" &&
          body["PhoneNumbers"] == "+8613800138000" &&
          body["TemplateCode"] == "SMS_1" &&
          body["SignName"] == "TestCo" &&
          body["TemplateParam"] == '{"code":"1234"}' &&
          body["Signature"].present?
      }
    end

    it "raises ApiError when Code != OK" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "Code" => "isv.OUT_OF_SERVICE", "Message" => "out of service" }.to_json
      )
      expect {
        adapter.send_message(to: "+8613800138000", template: template, template_params: { "code" => "1" })
      }.to raise_error(Sms::Errors::ApiError, /out of service/)
    end

    it "raises TransportError on network failure" do
      stub_request(:post, endpoint).to_raise(Errno::ECONNREFUSED.new("boom"))
      expect {
        adapter.send_message(to: "+8613800138000", template: template, template_params: { "code" => "1" })
      }.to raise_error(Sms::Errors::TransportError)
    end

    ["null", "[]", "not-json", { Code: "OK" }.to_json, { Code: "OK", BizId: " " }.to_json,
     { Code: "OK", BizId: [] }.to_json].each do |body|
      it "treats malformed success #{body.inspect} as ambiguous, never definitive rejection" do
        stub_request(:post, endpoint).to_return(status: 200, body: body)
        expect { adapter.send_message(to: "+8613800138000", template: template, template_params: {}) }
          .to raise_error(Sms::Errors::TransportError)
      end
    end

    it "rejects successful-looking body on HTTP failure as ambiguous" do
      stub_request(:post, endpoint).to_return(status: 502, body: { Code: "OK", BizId: "BIZ-1", AccessKeySecret: "SECRET_ECHO" }.to_json)
      expect { adapter.send_message(to: "+8613800138000", template: template, template_params: {}) }
        .to raise_error(Sms::Errors::TransportError) { |error|
          expect(error.vendor_message_id).to eq("BIZ-1")
          expect(error.payload).to eq("Code" => "OK", "BizId" => "BIZ-1")
        }
    end

    ["id/other", "id\n", "a" * 257, []].each do |biz_id|
      it "does not retain unsafe BizId #{biz_id.inspect} across HTTP mismatch" do
        stub_request(:post, endpoint).to_return(status: 502, body: { Code: "OK", BizId: biz_id }.to_json)
        expect { adapter.send_message(to: "+8613800138000", template: template, template_params: {}) }
          .to raise_error(Sms::Errors::TransportError) { |error| expect(error.vendor_message_id).to be_nil }
      end
    end

    it "accepts Aliyun's caret-delimited bounded BizId syntax" do
      stub_request(:post, endpoint).to_return(status: 200, body: { Code: "OK", BizId: "12345^67890" }.to_json)
      expect(adapter.send_message(to: "+8613800138000", template: template, template_params: {})[:vendor_message_id]).to eq("12345^67890")
    end
  end

  describe "#query" do
    let(:message) do
      build_stubbed(:sms_message, provider: "aliyun", to: "+8613800138000",
                    vendor_message_id: "BIZ-1", sent_at: Time.zone.now, created_at: Time.zone.now)
    end

    it "maps SendStatus=3 to :delivered" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: {
          "Code" => "OK",
          "SmsSendDetailDTOs" => {
            "SmsSendDetailDTO" => [{ "SendStatus" => 3, "PhoneNum" => "+8613800138000" }]
          }
        }.to_json
      )
      out = adapter.query(message: message)
      expect(out[:status]).to eq(:delivered)
    end

    it "maps SendStatus=2 to :failed" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { "Code" => "OK", "SmsSendDetailDTOs" => { "SmsSendDetailDTO" => [{ "SendStatus" => 2 }] } }.to_json
      )
      expect(adapter.query(message: message)[:status]).to eq(:failed)
    end

    it "maps any other SendStatus to :unknown" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { "Code" => "OK", "SmsSendDetailDTOs" => { "SmsSendDetailDTO" => [{ "SendStatus" => 1 }] } }.to_json
      )
      expect(adapter.query(message: message)[:status]).to eq(:unknown)
    end

    it "falls back to :unknown when no detail rows are returned" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "Code" => "OK", "SmsSendDetailDTOs" => {} }.to_json
      )
      expect(adapter.query(message: message)[:status]).to eq(:unknown)
    end

    it "raises ApiError when Code != OK" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "Code" => "isv.SYSTEM_ERROR", "Message" => "system error" }.to_json
      )
      expect {
        adapter.query(message: message)
      }.to raise_error(Sms::Errors::ApiError, /system error/)
    end

    it "falls back to message.created_at when sent_at is absent" do
      unsent = build_stubbed(:sms_message, provider: "aliyun", to: "+8613800138000",
                             vendor_message_id: "BIZ-1", sent_at: nil, created_at: Time.zone.now)
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "Code" => "OK", "SmsSendDetailDTOs" => {} }.to_json
      )
      expect { adapter.query(message: unsent) }.not_to raise_error
    end

    it "queries domestic phones and dates in China Standard Time and preserves carrier facts" do
      message.sent_at = Time.utc(2026, 10, 12, 17)
      row = { "PhoneNum" => "13800138000", "SendStatus" => 2, "ErrCode" => "MOBILE_NOT_AVAILABLE",
              "ReceiveDate" => "2026-10-13 01:05:00" }
      stub_request(:post, endpoint).to_return(status: 200, body: { Code: "OK", SmsSendDetailDTOs: { SmsSendDetailDTO: [row] } }.to_json)
      expect(adapter.query(message: message)).to include(status: :failed, phone: "+8613800138000", provider_status: "2",
                                                       failure_code: "MOBILE_NOT_AVAILABLE", occurred_at: Time.utc(2026, 10, 12, 17, 5))
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        params = URI.decode_www_form(request.body).to_h
        params["PhoneNumber"] == "13800138000" && params["SendDate"] == "20261013" && params["BizId"] == "BIZ-1"
      }
    end

    it "uses dispatch date when API acceptance arrives after China Standard Time midnight" do
      message.created_at = Time.utc(2026, 10, 11, 15)
      message.dispatch_started_at = Time.utc(2026, 10, 12, 15, 59, 59)
      message.sent_at = Time.utc(2026, 10, 12, 16, 0, 1)
      stub_request(:post, endpoint).to_return(status: 200, body: { Code: "OK" }.to_json)
      adapter.query(message: message)
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        URI.decode_www_form(request.body).to_h["SendDate"] == "20261012"
      }
    end

    it "uses dispatch date after long admission delay even when acceptance time is unknown" do
      message.created_at = Time.utc(2026, 10, 11, 15)
      message.dispatch_started_at = Time.utc(2026, 10, 12, 17)
      message.sent_at = nil
      stub_request(:post, endpoint).to_return(status: 200, body: { Code: "OK" }.to_json)
      adapter.query(message: message)
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        URI.decode_www_form(request.body).to_h["SendDate"] == "20261013"
      }
    end

    it "uses historical admission date only when both dispatch and acceptance clocks are missing" do
      message.created_at = Time.utc(2026, 10, 11, 17)
      message.dispatch_started_at = nil
      message.sent_at = nil
      stub_request(:post, endpoint).to_return(status: 200, body: { Code: "OK" }.to_json)
      adapter.query(message: message)
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        URI.decode_www_form(request.body).to_h["SendDate"] == "20261012"
      }
    end

    it "returns international country code plus number without + for query" do
      message.to = "+14155552671"
      row = { "PhoneNum" => "14155552671", "SendStatus" => 3 }
      stub_request(:post, endpoint).to_return(status: 200, body: { Code: "OK", SmsSendDetailDTOs: { SmsSendDetailDTO: [row] } }.to_json)
      expect(adapter.query(message: message)).to include(status: :delivered, phone: "+14155552671")
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        URI.decode_www_form(request.body).to_h["PhoneNumber"] == "14155552671"
      }
    end

    it "ignores malformed/absent ReceiveDate and keeps wrong recipient for projection rejection" do
      row = { "PhoneNum" => "13800139999", "SendStatus" => 3, "ReceiveDate" => "invalid" }
      stub_request(:post, endpoint).to_return(status: 200, body: { Code: "OK", SmsSendDetailDTOs: { SmsSendDetailDTO: [row] } }.to_json)
      event = adapter.query(message: message)
      expect(event[:phone]).to eq("+8613800139999")
      expect(event).not_to have_key(:occurred_at)
    end
  end

  describe "signing" do
    it "produces a deterministic signature for known inputs (regression-lock)" do
      # Golden test — pins the exact HMAC-SHA1 output for a controlled set
      # of inputs. Any accidental change to the encoding rules (+/space,
      # */asterisk, %7E/tilde) or to the HMAC key format (trailing &) will
      # break this test loudly.
      params = {
        "AccessKeyId"      => "testid",
        "Action"           => "SendSms",
        "Format"           => "JSON",
        "PhoneNumbers"     => "+8613800138000",
        "RegionId"         => "cn-hangzhou",
        "SignName"         => "TestCo",
        "SignatureMethod"  => "HMAC-SHA1",
        "SignatureNonce"   => "fixed-nonce",
        "SignatureVersion" => "1.0",
        "TemplateCode"     => "SMS_1",
        "TemplateParam"    => '{"code":"1234"}',
        "Timestamp"        => "2026-04-28T00:00:00Z",
        "Version"          => "2017-05-25"
      }
      stub_credential = build_stubbed(:sms_credential, provider: "aliyun",
                                      access_key_id: "testid", access_key_secret: "testsecret")
      a = described_class.new(credential: stub_credential)
      sig = a.sign_params(params)["Signature"]

      # Recompute via the documented algorithm to verify the golden value.
      sorted = params.sort.map { |k, v|
        [k, v].map { |s| CGI.escape(s.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~") }.join("=")
      }.join("&")
      to_sign  = "POST&#{CGI.escape('/')}&#{CGI.escape(sorted).gsub('+', '%20').gsub('*', '%2A').gsub('%7E', '~')}"
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", "testsecret&", to_sign))
      expect(sig).to eq(expected)
    end
  end
end
