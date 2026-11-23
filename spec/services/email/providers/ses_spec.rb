# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Providers::Ses do
  let(:credential) do
    build_stubbed(:email_credential, provider: "ses", host: nil, username: nil,
                  password: "secret", mode: "sandbox",
                  config: { "access_key_id" => "AKID", "region" => "us-east-1",
                            "from_email" => "noreply@example.com",
                            "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
  end
  let(:provider) { described_class.new(credential: credential) }
  let(:ses_client) { instance_double(Aws::SESV2::Client) }
  let(:verifier) { instance_double(Aws::SNS::MessageVerifier, authentic?: true) }

  before do
    allow(Aws::SESV2::Client).to receive(:new).and_return(ses_client)
    allow(Aws::SNS::MessageVerifier).to receive(:new).and_return(verifier)
  end

  describe "class interface" do
    it_behaves_like "an email provider class interface",
                    key: "ses", delivery_mechanism: :webhook,
                    config_fields: %i[access_key_id region from_email sns_topic_arn]

    it ".uses_webhook_secret? is false (SNS cert verification)" do
      expect(described_class.uses_webhook_secret?).to be(false)
    end

    describe ".configured?" do
      it "is true with password + access_key_id + from_email + sns_topic_arn" do
        expect(described_class.configured?(credential)).to be(true)
      end

      it "is false without password" do
        cred = build_stubbed(:email_credential, provider: "ses", password: nil,
                             config: { "access_key_id" => "AKID", "from_email" => "a@b.com" })
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false without access_key_id" do
        cred = build_stubbed(:email_credential, provider: "ses", password: "s",
                             config: { "from_email" => "a@b.com" })
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false without from_email" do
        cred = build_stubbed(:email_credential, provider: "ses", password: "s",
                             config: { "access_key_id" => "AKID" })
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false without sns_topic_arn" do
        cred = build_stubbed(:email_credential, provider: "ses", password: "s",
                             config: { "access_key_id" => "AKID", "from_email" => "a@b.com" })
        expect(described_class.configured?(cred)).to be(false)
      end
    end
  end

  describe "#deliver" do
    let(:message) do
      build_stubbed(:email_message, to: "r@example.com", from: "s@example.com",
                    subject: "Hi", body_html: "<p>Hi</p>", body_text: "Hi")
    end
    let(:response) do
      double("SendEmailResponse", message_id: "ses-123", to_h: { message_id: "ses-123" })
    end

    it "calls SESv2 SendEmail and returns the provider_message_id" do
      expect(ses_client).to receive(:send_email) do |params|
        expect(params[:from_email_address]).to eq("s@example.com")
        expect(params[:destination][:to_addresses]).to eq(["r@example.com"])
        expect(params[:content][:simple][:subject][:data]).to eq("Hi")
        expect(params[:content][:simple][:body][:html][:data]).to eq("<p>Hi</p>")
        expect(params[:content][:simple][:body][:text][:data]).to eq("Hi")
        expect(params).not_to have_key(:reply_to_addresses)
        response
      end

      result = provider.deliver(message: message)
      expect(result[:provider_message_id]).to eq("ses-123")
      expect(Aws::SESV2::Client).to have_received(:new).with(
        hash_including(access_key_id: "AKID", secret_access_key: "secret", region: "us-east-1")
      )
    end

    it "includes Cc/Bcc/ReplyTo only when present" do
      cc_message = build_stubbed(:email_message, to: "r@example.com", from: "s@example.com",
                                 subject: "Hi", body_html: "<p>Hi</p>",
                                 cc: "cc@example.com", bcc: "bcc@example.com", reply_to: "reply@example.com")
      expect(ses_client).to receive(:send_email) do |params|
        expect(params[:destination][:cc_addresses]).to eq(["cc@example.com"])
        expect(params[:destination][:bcc_addresses]).to eq(["bcc@example.com"])
        expect(params[:reply_to_addresses]).to eq(["reply@example.com"])
        response
      end

      provider.deliver(message: cc_message)
    end

    it "omits text body when blank" do
      html_only = build_stubbed(:email_message, to: "r@example.com", from: "s@example.com",
                                subject: "Hi", body_html: "<p>Hi</p>", body_text: nil)
      expect(ses_client).to receive(:send_email) do |params|
        expect(params[:content][:simple][:body]).not_to have_key(:text)
        response
      end

      provider.deliver(message: html_only)
    end

    it "stamps RFC 8058 List-Unsubscribe headers on campaign mail" do
      recipient = create(:user)
      campaign = build_stubbed(:email_message, :campaign, to: recipient.email,
                               from: "s@example.com", subject: "Hi",
                               body_html: "<p>Hi</p>", body_text: "Hi",
                               metadata: { "user_id" => recipient.id })
      expect(ses_client).to receive(:send_email) do |params|
        headers = params.dig(:content, :simple, :headers)
        expect(headers).to include(
          hash_including(name: "List-Unsubscribe-Post", value: "List-Unsubscribe=One-Click")
        )
        unsub = headers.find { |h| h[:name] == "List-Unsubscribe" }
        expect(unsub[:value]).to match(%r{\A<https?://.+/unsubscribe/.+>\z})
        response
      end

      provider.deliver(message: campaign)
    end

    it "uses the queued recipient in unsubscribe headers after a profile edit" do
      recipient = create(:user)
      campaign = build_stubbed(:email_message, :campaign, customer: recipient.customer, to: recipient.email,
                               metadata: { "user_id" => recipient.id })
      original = recipient.email
      recipient.update!(email: "changed@example.com")
      expect(ses_client).to receive(:send_email) do |params|
        url = params.dig(:content, :simple, :headers).find { |header| header[:name] == "List-Unsubscribe" }[:value]
        token = CGI.unescape(url[%r{/unsubscribe/([^>]+)>}, 1])
        expect(Emails::SendActivities::SendActivityUnsubscribe.emailed_address(token)).to eq(original)
        response
      end

      provider.deliver(message: campaign)
    end

    it "sends CID images as raw MIME, preserving envelope and unsubscribe headers without leaking Bcc" do
      recipient = create(:user)
      own = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("own-image"), filename: "own.png", content_type: "image/png")
      own.update!(customer_id: recipient.customer_id)
      foreign = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("foreign-image"), filename: "foreign.png", content_type: "image/png")
      foreign.update!(customer_id: create(:customer).id)
      campaign = build_stubbed(:email_message, :campaign, customer: recipient.customer, to: recipient.email,
                               from: "s@example.com", cc: "cc@example.com", bcc: "hidden@example.com", reply_to: "reply@example.com",
                               subject: "Inline image", body_text: "Plain body", body_html: %(<p>HTML body<img src="cid:blob-#{own.id}"></p>),
                               metadata: { "user_id" => recipient.id, "attachment_blob_ids" => [own.id, foreign.id] })
      expect(ses_client).to receive(:send_email) do |params|
        expect(params.dig(:destination, :bcc_addresses)).to eq(["hidden@example.com"])
        expect(params[:content]).not_to have_key(:simple)
        mime = Mail.read_from_string(params.dig(:content, :raw, :data))
        expect(mime.mime_type).to eq("multipart/related")
        expect(mime.parts.first.mime_type).to eq("multipart/alternative")
        expect(mime.subject).to eq("Inline image")
        expect(mime.cc).to eq(["cc@example.com"])
        expect(mime.reply_to).to eq(["reply@example.com"])
        expect(mime["Bcc"]).to be_nil
        expect(mime.text_part.body.decoded.strip).to eq("Plain body")
        expect(mime.html_part.body.decoded).to include("cid:blob-#{own.id}")
        expect(mime["List-Unsubscribe"]).to be_present
        expect(mime["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
        expect(mime.attachments.map(&:content_id)).to contain_exactly("<blob-#{own.id}>")
        expect(mime.attachments.first.mime_type).to eq("image/png")
        expect(mime.attachments.first.body.decoded).to eq("own-image")
        response
      end

      provider.deliver(message: campaign)
    end

    it "omits List-Unsubscribe headers on transactional mail" do
      expect(ses_client).to receive(:send_email) do |params|
        expect(params.dig(:content, :simple)).not_to have_key(:headers)
        response
      end

      provider.deliver(message: message)
    end


    it "raises Email::Errors::ApiError on a SES service error" do
      ctx = Seahorse::Client::RequestContext.new
      allow(ses_client).to receive(:send_email)
        .and_raise(Aws::SESV2::Errors::MessageRejected.new(ctx, "Email address not verified"))

      expect { provider.deliver(message: message) }
        .to raise_error(Email::Errors::ApiError, /not verified/)
    end

    it "wraps a networking failure in Email::Errors::TransportError" do
      allow(ses_client).to receive(:send_email)
        .and_raise(Seahorse::Client::NetworkingError.new(StandardError.new("timeout")))

      expect { provider.deliver(message: message) }.to raise_error(Email::Errors::TransportError)
    end

    it "wraps Aws::Errors::NoSuchEndpointError in TransportError" do
      allow(ses_client).to receive(:send_email)
        .and_raise(Aws::Errors::NoSuchEndpointError.new(context: Seahorse::Client::RequestContext.new))

      expect { provider.deliver(message: message) }.to raise_error(Email::Errors::TransportError)
    end
  end

  describe "#verify_webhook!" do
    def request_with(body)
      double("request", raw_post: body.to_json, request_parameters: body)
    end

    let(:envelope) do
      { "Type" => "Notification", "TopicArn" => "arn:aws:sns:us-east-1:1:ses",
        "Message" => { "notificationType" => "Delivery" }.to_json,
        "MessageId" => "sns-message", "Timestamp" => "2026-10-11T00:00:00Z",
        "SignatureVersion" => "2", "Signature" => Base64.strict_encode64("signature"),
        "SigningCertURL" => "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-cert.pem" }
    end

    it "does not raise when the SNS signature is authentic" do
      expect { provider.verify_webhook!(request_with(envelope)) }.not_to raise_error
    end

    it "raises SignatureInvalid when the SNS signature is forged" do
      allow(verifier).to receive(:authentic?).and_return(false)
      expect { provider.verify_webhook!(request_with(envelope)) }
        .to raise_error(Email::Errors::SignatureInvalid, /invalid SES SNS signature/)
    end

    it "raises SignatureInvalid for an unrecognized SNS Type" do
      expect { provider.verify_webhook!(request_with("Type" => "Nope")) }
        .to raise_error(Email::Errors::SignatureInvalid, /unrecognized SNS type/)
    end

    it "raises SignatureInvalid for a JSON array body instead of TypeError" do
      req = double("request", raw_post: "[]", request_parameters: [])
      expect { provider.verify_webhook!(req) }
        .to raise_error(Email::Errors::SignatureInvalid, /unrecognized SNS type/)
    end

    it "raises SignatureInvalid when a configured sns_topic_arn does not match" do
      cred = build_stubbed(:email_credential, provider: "ses", password: "secret",
                           config: { "access_key_id" => "AKID", "from_email" => "a@b.com",
                                     "sns_topic_arn" => "arn:aws:sns:us-east-1:1:other" })
      mismatched = described_class.new(credential: cred)
      expect { mismatched.verify_webhook!(request_with(envelope)) }
        .to raise_error(Email::Errors::SignatureInvalid, /topic mismatch/)
    end

    it "raises SignatureInvalid when sns_topic_arn is not configured" do
      cred = build_stubbed(:email_credential, provider: "ses", password: "secret",
                           config: { "access_key_id" => "AKID", "from_email" => "a@b.com" })
      unbound = described_class.new(credential: cred)
      expect { unbound.verify_webhook!(request_with(envelope)) }
        .to raise_error(Email::Errors::SignatureInvalid, /not configured/)
    end

    [nil, [], {}, 123, "https://", "https://sns.us-east-1.amazonaws.com:8443/cert.pem",
     "https://user@sns.us-east-1.amazonaws.com/cert.pem", "https://evil.example/cert.pem"].each do |url|
      it "controls malformed or unsafe SigningCertURL #{url.inspect} before verification/fetch" do
        expect(verifier).not_to receive(:authentic?)
        expect { provider.verify_webhook!(request_with(envelope.merge("SigningCertURL" => url))) }
          .to raise_error(Email::Errors::SignatureInvalid)
      end
    end

    %w[Message MessageId Timestamp TopicArn Signature SignatureVersion Subject Token SubscribeURL].each do |field|
      it "rejects a non-string #{field} field with SignatureInvalid" do
        expect { provider.verify_webhook!(request_with(envelope.merge(field => { "bad" => true }))) }
          .to raise_error(Email::Errors::SignatureInvalid)
      end
    end

    it "rejects an alternate certificate-key spelling that would override the validated URL in the SDK" do
      expect(verifier).not_to receive(:authentic?)
      expect { provider.verify_webhook!(request_with(envelope.merge("SigningCertUrl" => "https://evil.example/cert.pem"))) }
        .to raise_error(Email::Errors::SignatureInvalid)
    end

    it "controls an SDK certificate parser failure" do
      allow(verifier).to receive(:authentic?).and_raise(OpenSSL::X509::CertificateError, "bad certificate")
      expect { provider.verify_webhook!(request_with(envelope)) }.to raise_error(Email::Errors::SignatureInvalid)
    end
  end

  describe "#parse_events" do
    def request_with(envelope)
      double("request", raw_post: envelope.to_json, request_parameters: envelope)
    end

    def notification(inner)
      { "Type" => "Notification", "Message" => inner.to_json, "TopicArn" => "arn:aws:sns:us-east-1:1:ses" }
    end

    it "maps a Delivery notification to :delivered" do
      inner = { "notificationType" => "Delivery", "mail" => { "messageId" => "ses-1" },
                "delivery" => { "recipients" => ["r@example.com"] } }
      events = provider.parse_events(request_with(notification(inner)))
      expect(events.first).to include(type: :delivered, provider_message_id: "ses-1",
                                      email: "r@example.com", suppress: false)
    end

    it "maps a Permanent Bounce to :bounced with suppress: true" do
      inner = { "notificationType" => "Bounce", "mail" => { "messageId" => "ses-2" },
                "bounce" => { "bounceType" => "Permanent",
                              "bouncedRecipients" => [{ "emailAddress" => "bad@example.com",
                                                        "diagnosticCode" => "5.1.1" }] } }
      events = provider.parse_events(request_with(notification(inner)))
      expect(events.first).to include(type: :bounced, provider_message_id: "ses-2",
                                      email: "bad@example.com", suppress: true, code: "Permanent")
    end

    it "maps a Transient Bounce to :bounced with suppress: false" do
      inner = { "eventType" => "Bounce", "mail" => { "messageId" => "ses-3" },
                "bounce" => { "bounceType" => "Transient",
                              "bouncedRecipients" => [{ "emailAddress" => "soft@example.com" }] } }
      events = provider.parse_events(request_with(notification(inner)))
      expect(events.first).to include(type: :bounced, suppress: false)
    end

    it "maps a Complaint to :complained with suppress: true" do
      inner = { "notificationType" => "Complaint", "mail" => { "messageId" => "ses-4" },
                "complaint" => { "complainedRecipients" => [{ "emailAddress" => "spam@example.com" }] } }
      events = provider.parse_events(request_with(notification(inner)))
      expect(events.first).to include(type: :complained, email: "spam@example.com", suppress: true)
    end

    it "emits every bounced recipient with its own diagnostic and suppression flag" do
      inner = { "notificationType" => "Bounce", "mail" => { "messageId" => "ses-multi" },
                "bounce" => { "bounceType" => "Permanent", "bouncedRecipients" => [
                  { "emailAddress" => "a@example.com", "diagnosticCode" => "5.1.1 a" },
                  { "emailAddress" => "b@example.com", "diagnosticCode" => "5.1.1 b" }
                ] } }
      events = provider.parse_events(request_with(notification(inner)))

      expect(events.map { |event| event.slice(:email, :message, :suppress) }).to eq([
        { email: "a@example.com", message: "5.1.1 a", suppress: true },
        { email: "b@example.com", message: "5.1.1 b", suppress: true }
      ])
    end

    it "emits every complained recipient" do
      inner = { "eventType" => "Complaint", "mail" => { "messageId" => "ses-multi" },
                "complaint" => { "complainedRecipients" => [
                  { "emailAddress" => "a@example.com" }, { "emailAddress" => "b@example.com" }
                ] } }
      events = provider.parse_events(request_with(notification(inner)))

      expect(events.map { |event| event[:email] }).to eq(%w[a@example.com b@example.com])
      expect(events).to all(include(type: :complained, suppress: true, provider_message_id: "ses-multi"))
    end

    it "ignores malformed recipient records instead of raising or suppressing unrelated recipients" do
      inner = { "notificationType" => "Bounce", "mail" => { "messageId" => "ses-shape" },
                "bounce" => { "bounceType" => "Permanent", "bouncedRecipients" => [nil, "wrong", { "emailAddress" => [] }] } }
      expect(provider.parse_events(request_with(notification(inner)))).to eq([])
      inner["bounce"] = []
      expect(provider.parse_events(request_with(notification(inner)))).to eq([])
    end

    it "returns [] for an unrecognized notification type" do
      inner = { "notificationType" => "Open", "mail" => { "messageId" => "ses-5" } }
      expect(provider.parse_events(request_with(notification(inner)))).to eq([])
    end

    it "maps a Delivery that only lists destination on mail" do
      inner = { "notificationType" => "Delivery", "mail" => { "messageId" => "ses-dest",
                                                              "destination" => ["r@example.com"] } }
      events = provider.parse_events(request_with(notification(inner)))
      expect(events.first).to include(email: "r@example.com")
    end

    it "accepts an already-parsed Message hash" do
      envelope = { "Type" => "Notification",
                   "Message" => { "notificationType" => "Delivery",
                                  "mail" => { "messageId" => "ses-hash" },
                                  "delivery" => { "recipients" => ["r@example.com"] } } }
      events = provider.parse_events(request_with(envelope))
      expect(events.first).to include(provider_message_id: "ses-hash")
    end

    it "reads request_parameters when raw_post is blank" do
      envelope = notification("notificationType" => "Delivery", "mail" => { "messageId" => "ses-raw" },
                              "delivery" => { "recipients" => ["r@example.com"] })
      req = double("request", raw_post: "", request_parameters: envelope)
      events = provider.parse_events(req)
      expect(events.first).to include(provider_message_id: "ses-raw")
    end

    it "confirms an SNS subscription against an AWS SubscribeURL and returns []" do
      url = "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc"
      allow(OutboundHttp).to receive(:request).and_return(double(status: 200, body: "ok"))
      events = provider.parse_events(request_with(
        "Type" => "SubscriptionConfirmation", "SubscribeURL" => url
      ))
      expect(events).to eq([])
      expect(OutboundHttp).to have_received(:request).with(:get, url, hash_including(:open_timeout, :read_timeout))
    end

    it "rejects a SubscribeURL that is not an SNS host" do
      expect {
        provider.parse_events(request_with(
          "Type" => "SubscriptionConfirmation", "SubscribeURL" => "https://evil.example/confirm"
        ))
      }.to raise_error(Email::Errors::SignatureInvalid, /SubscribeURL/)
    end

    it "rejects a malformed SubscribeURL" do
      expect {
        provider.parse_events(request_with(
          "Type" => "SubscriptionConfirmation", "SubscribeURL" => "http://"
        ))
      }.to raise_error(Email::Errors::SignatureInvalid, /SubscribeURL/)
    end

    it "wraps SubscribeURL fetch failures in TransportError" do
      url = "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc"
      allow(OutboundHttp).to receive(:request).and_raise(OutboundHttp::TransportError.new("down"))
      expect {
        provider.parse_events(request_with("Type" => "SubscriptionConfirmation", "SubscribeURL" => url))
      }.to raise_error(Email::Errors::TransportError, "down")
    end

    it "returns [] for UnsubscribeConfirmation" do
      expect(provider.parse_events(request_with("Type" => "UnsubscribeConfirmation"))).to eq([])
    end
  end
end
