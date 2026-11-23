# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Providers::Aliyun do
  let(:credential) do
    build_stubbed(:email_credential, provider: "aliyun", host: nil, username: nil,
                  password: "AKS", mode: "sandbox", webhook_secret: "whsec",
                  config: { "access_key_id" => "AKID", "region" => "cn-hangzhou",
                            "from_email" => "noreply@example.com" })
  end
  let(:provider) { described_class.new(credential: credential) }
  let(:endpoint) { described_class::DEFAULT_HOST }

  describe "class interface" do
    it_behaves_like "an email provider class interface",
                    key: "aliyun", delivery_mechanism: :webhook,
                    config_fields: %i[access_key_id region from_email from_alias]

    describe ".configured?" do
      it "is true with password + access_key_id + from_email" do
        expect(described_class.configured?(credential)).to be(true)
      end

      it "is false without password" do
        cred = build_stubbed(:email_credential, provider: "aliyun", password: nil,
                             config: { "access_key_id" => "AKID", "from_email" => "a@b.com" })
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false without from_email" do
        cred = build_stubbed(:email_credential, provider: "aliyun", password: "s",
                             config: { "access_key_id" => "AKID" })
        expect(described_class.configured?(cred)).to be(false)
      end
    end
  end

  describe "#deliver" do
    let(:message) do
      build_stubbed(:email_message, to: "r@example.com", from: "s@example.com",
                    subject: "Hi", body_html: "<p>Hi</p>", body_text: "Hi")
    end

    it "POSTs SingleSendMail and returns EnvId as provider_message_id" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "EnvId" => "env-123", "RequestId" => "req-1" }.to_json
      )

      result = provider.deliver(message: message)

      expect(result).to eq(provider_message_id: "env-123", raw: { "EnvId" => "env-123", "RequestId" => "req-1" })
      expect(WebMock).to have_requested(:post, endpoint).with { |req|
        body = URI.decode_www_form(req.body).to_h
        body["Action"] == "SingleSendMail" &&
          body["AccountName"] == "s@example.com" &&
          body["ToAddress"] == "r@example.com" &&
          body["Subject"] == "Hi" &&
          body["HtmlBody"] == "<p>Hi</p>" &&
          body["TextBody"] == "Hi" &&
          body["AddressType"] == "1" &&
          body["ReplyToAddress"] == "false" &&
          body["Signature"].present?
      }
    end

    it "sets FromAlias when configured" do
      cred = build_stubbed(:email_credential, provider: "aliyun", password: "AKS",
                           webhook_secret: "whsec",
                           config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com",
                                     "from_alias" => "Support" })
      aliased = described_class.new(credential: cred)
      cc_message = build_stubbed(:email_message, to: "r@example.com", from: "s@example.com",
                                  subject: "Hi", body_html: "<p>Hi</p>")
      stub_request(:post, endpoint).to_return(status: 200, body: { "EnvId" => "env-124" }.to_json)

      aliased.deliver(message: cc_message)

      expect(WebMock).to have_requested(:post, endpoint).with { |req|
        body = URI.decode_www_form(req.body).to_h
        body["ToAddress"] == "r@example.com" &&
          body["FromAlias"] == "Support" &&
          body["ReplyToAddress"] == "false"
      }
    end

    %i[cc bcc reply_to].each do |field|
      it "rejects unsupported #{field} rather than flattening or dropping its meaning" do
        message.public_send("#{field}=", "private@example.com")
        expect(provider).not_to receive(:http_post_form)

        expect { provider.deliver(message: message) }.to raise_error(Email::Errors::ApiError) do |error|
          expect(error.code).to eq("UNSUPPORTED_FEATURE")
          expect(error.payload).to eq("features" => [field.to_s])
        end
      end
    end

    it "rejects CID bodies even when attachment metadata is absent" do
      message.body_html = '<img src="cid:blob-123">'
      expect(provider).not_to receive(:http_post_form)
      expect { provider.deliver(message: message) }.to raise_error(Email::Errors::ApiError) do |error|
        expect(error.code).to eq("UNSUPPORTED_FEATURE")
        expect(error.payload).to eq("features" => ["inline_attachments"])
      end
    end

    it "rejects attachments even when the HTML happens not to reference them" do
      message.metadata = { "attachment_blob_ids" => [123] }
      expect { provider.deliver(message: message) }.to raise_error(Email::Errors::ApiError) do |error|
        expect(error.code).to eq("UNSUPPORTED_FEATURE")
      end
    end

    it "rejects campaign transport before any RPC call instead of sending without RFC 8058 headers" do
      message.message_type = "campaign"
      expect(provider).not_to receive(:http_post_form)

      expect(provider.supports_message?(message: message)).to be(false)
      expect { provider.deliver(message: message) }.to raise_error(Email::Errors::UnsupportedMessage) do |error|
        expect(error.code).to eq("UNSUPPORTED_FEATURE")
        expect(error.payload).to eq("features" => ["one_click_unsubscribe"])
        expect(error.message).to eq(I18n.t("email.providers.errors.unsupported_campaign", provider: described_class.display_name))
      end
    end

    it "shares localized admission rejection with dispatch in both locales" do
      message.bcc = "private@example.com"
      %i[en zh-CN].each do |locale|
        I18n.with_locale(locale) do
          expect { provider.validate_message!(message: message) }.to raise_error(Email::Errors::UnsupportedMessage) do |error|
            expect(error.message).to eq(I18n.t("email.providers.errors.unsupported_message", provider: described_class.display_name))
            expect(error.payload).to eq("features" => ["bcc"])
          end
        end
      end
    end

    it "posts to the regional endpoint when region is not cn-hangzhou" do
      cred = build_stubbed(:email_credential, provider: "aliyun", password: "AKS",
                           config: { "access_key_id" => "AKID", "region" => "ap-southeast-1",
                                     "from_email" => "noreply@example.com" })
      regional = described_class.new(credential: cred)
      stub_request(:post, "https://dm.ap-southeast-1.aliyuncs.com/").to_return(
        status: 200, body: { "EnvId" => "env-sg" }.to_json
      )

      expect(regional.deliver(message: message)[:provider_message_id]).to eq("env-sg")
    end

    it "treats Code=OK with EnvId as success" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "Code" => "OK", "EnvId" => "env-ok" }.to_json
      )
      expect(provider.deliver(message: message)[:provider_message_id]).to eq("env-ok")
    end

    it "raises Email::Errors::ApiError when Code is not OK" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { "Code" => "InvalidToAddress", "Message" => "bad recipient" }.to_json
      )

      expect { provider.deliver(message: message) }
        .to raise_error(Email::Errors::ApiError, "bad recipient") do |e|
          expect(e.code).to eq("InvalidToAddress")
        end
    end

    it "raises Email::Errors::ApiError when EnvId is missing on an otherwise empty success" do
      stub_request(:post, endpoint).to_return(status: 200, body: { "RequestId" => "req" }.to_json)

      expect { provider.deliver(message: message) }
        .to raise_error(Email::Errors::ApiError, "Aliyun DirectMail send failed")
    end

    it "wraps a transport failure in Email::Errors::TransportError" do
      stub_request(:post, endpoint).to_timeout
      expect { provider.deliver(message: message) }.to raise_error(Email::Errors::TransportError)
    end
  end

  describe "#verify_webhook!" do
    def request_with(auth: nil, token: nil)
      headers = { "Authorization" => auth }
      double("request",
             headers: headers,
             query_parameters: { "token" => token }.compact,
             params: { "token" => token }.compact)
    end

    it "does not raise for a valid Basic-Auth header" do
      valid = "Basic #{Base64.strict_encode64('aliyun:whsec')}"
      expect { provider.verify_webhook!(request_with(auth: valid)) }.not_to raise_error
    end

    it "does not raise for a matching token query parameter" do
      expect { provider.verify_webhook!(request_with(token: "whsec")) }.not_to raise_error
    end

    it "reads token from params when query_parameters is unavailable" do
      req = double("request", headers: { "Authorization" => nil }, params: { "token" => "whsec" })
      expect { provider.verify_webhook!(req) }.not_to raise_error
    end

    it "raises SignatureInvalid for a wrong secret" do
      wrong = "Basic #{Base64.strict_encode64('aliyun:wrong')}"
      expect { provider.verify_webhook!(request_with(auth: wrong)) }
        .to raise_error(Email::Errors::SignatureInvalid)
    end

    it "raises SignatureInvalid when the credential has no webhook_secret" do
      cred = build_stubbed(:email_credential, provider: "aliyun", password: "AKS", webhook_secret: nil,
                           config: { "access_key_id" => "AKID", "from_email" => "a@b.com" })
      bare = described_class.new(credential: cred)
      expect { bare.verify_webhook!(request_with(token: "")) }
        .to raise_error(Email::Errors::SignatureInvalid, /not configured/)
    end
  end

  describe "#parse_events" do
    def request_with(raw:, params: {})
      double("request", raw_post: raw, request_parameters: params)
    end

    it "maps MNS query-string status 0 to :delivered" do
      raw = "env_id=env-1&rcpt=r@example.com&status=0&event=deliver"
      events = provider.parse_events(request_with(raw: raw))
      expect(events.first).to include(type: :delivered, provider_message_id: "env-1",
                                      email: "r@example.com", suppress: false)
    end

    it "maps status 2 (invalid address) to :bounced with suppress: true" do
      raw = "env_id=env-2&rcpt=bad@example.com&status=2&err_code=SmtpNxBox&err_msg=no box"
      events = provider.parse_events(request_with(raw: raw))
      expect(events.first).to include(type: :bounced, suppress: true, code: "SmtpNxBox")
    end

    it "maps status 3 (spam) to :complained with suppress: true" do
      raw = "env_id=env-3&rcpt=spam@example.com&status=3&err_code=spam"
      events = provider.parse_events(request_with(raw: raw))
      expect(events.first).to include(type: :complained, suppress: true)
    end

    it "maps status 4 (failed) to :bounced with suppress: false" do
      raw = "env_id=env-4&rcpt=tmp@example.com&status=4&err_code=421"
      events = provider.parse_events(request_with(raw: raw))
      expect(events.first).to include(type: :bounced, suppress: false)
    end

    it "parses an EventBridge CloudEvents JSON body" do
      body = {
        "specversion" => "1.0",
        "type" => "dm:Deliver:Fail",
        "data" => { "env_id" => "env-5", "rcpt" => "x@y.com", "status" => "2", "err_code" => "554" }
      }.to_json
      events = provider.parse_events(request_with(raw: body))
      expect(events.first).to include(type: :bounced, provider_message_id: "env-5", suppress: true)
    end

    it "returns [] for an unrecognized status" do
      expect(provider.parse_events(request_with(raw: "env_id=x&status=9"))).to eq([])
    end

    it "reads status from request_parameters when the body is not JSON or a query string" do
      req = double("request", raw_post: "not-json-or-query",
                   request_parameters: { "env_id" => "env-6", "rcpt" => "a@b.com", "status" => "0" })
      events = provider.parse_events(req)
      expect(events.first).to include(type: :delivered, provider_message_id: "env-6")
    end
  end
end
