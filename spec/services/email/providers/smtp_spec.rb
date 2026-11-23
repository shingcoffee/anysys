# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Providers::Smtp do
  let(:credential) { build_stubbed(:email_credential, mode: "sandbox") }
  let(:provider)   { described_class.new(credential: credential) }

  describe "class interface" do
    it_behaves_like "an email provider class interface",
                    key: "smtp", delivery_mechanism: :none, config_fields: []

    it "registers as the default provider" do
      expect(Email::Providers.default_key).to eq(:smtp)
      expect(Email::Providers.for("smtp")).to eq(described_class)
    end

    describe ".configured?" do
      it "is true with host, username, password present" do
        cred = build_stubbed(:email_credential, host: "smtp.test", username: "u@example.com", password: "p")
        expect(described_class.configured?(cred)).to be(true)
      end

      it "is false without host" do
        cred = build_stubbed(:email_credential, host: nil, username: "u", password: "p")
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false without username" do
        cred = build_stubbed(:email_credential, host: "smtp.test", username: nil, password: "p")
        expect(described_class.configured?(cred)).to be(false)
      end

      it "is false without password" do
        cred = build_stubbed(:email_credential, host: "smtp.test", username: "u", password: nil)
        expect(described_class.configured?(cred)).to be(false)
      end
    end
  end

  describe "#deliver" do
    let(:message) { create(:email_message, :queued) }

    it "delegates to Emails::DeliveryMailer.deliver_now and returns no provider_message_id" do
      mailer_double = double("mailer")
      expect(Emails::DeliveryMailer).to receive(:with)
        .with(message_id: message.id, mode: credential.mode, credential_id: credential.id)
        .and_return(double(deliver_email: mailer_double))
      expect(mailer_double).to receive(:deliver_now)

      result = provider.deliver(message: message)
      expect(result).to eq({ provider_message_id: nil, raw: {} })
    end

    it "propagates a raise from the mailer (owned by the caller job's retry/dead-letter logic)" do
      allow(Emails::DeliveryMailer).to receive(:with).and_raise(StandardError, "smtp down")
      expect { provider.deliver(message: message) }.to raise_error(StandardError, "smtp down")
    end
  end

  describe "abstract webhook interface" do
    it "raises NotImplementedError on #verify_webhook! (SMTP has no webhooks)" do
      expect { provider.verify_webhook!(double("request")) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on #parse_events (SMTP has no webhooks)" do
      expect { provider.parse_events(double("request")) }.to raise_error(NotImplementedError)
    end
  end
end
