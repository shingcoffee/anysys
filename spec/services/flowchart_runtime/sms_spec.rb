# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Sms do
  let(:customer) { create(:customer) }

  describe ".send_template" do
    it "delegates only approved template inputs to the tenant gateway" do
      message = instance_double(Sms::Message, id: 42, status: "queued")
      expires_at = 10.minutes.from_now
      expect(Sms::Gateway).to receive(:send).with(
        customer: customer, to: "+15559876543", template_key: "verify_code", vars: { "code" => "1234" },
        idempotency_key: "workflow-1", expires_at: expires_at
      ).and_return(message)

      expect(described_class.send_template(
        customer: customer, to: "+15559876543", template_key: "verify_code", vars: { "code" => "1234" },
        idempotency_key: "workflow-1", expires_at: expires_at
      )).to equal(message)
    end

    it "defaults to empty vars and no explicit key or expiry" do
      expect(Sms::Gateway).to receive(:send).with(
        customer: customer, to: "+15559876543", template_key: "plain_notice", vars: {}, idempotency_key: nil, expires_at: nil
      )
      described_class.send_template(customer: customer, to: "+15559876543", template_key: "plain_notice")
    end

    it "requires an explicit tenant customer" do
      expect(Sms::Gateway).not_to receive(:send)
      expect { described_class.send_template(to: "+15559876543", template_key: "verify_code") }
        .to raise_error(ArgumentError, /customer/)
    end

    it "cannot accept arbitrary credentials, a sender or a raw message body" do
      expect(Sms::Gateway).not_to receive(:send)
      expect {
        described_class.send_template(customer: customer, to: "+15559876543", template_key: "verify_code",
                                      account_sid: "AC_UNTRUSTED", auth_token: "secret", from: "+15550000000", body: "raw")
      }.to raise_error(ArgumentError, /unknown keywords/)
      expect(described_class).not_to respond_to(:send_twilio_message)
    end

    it "propagates gateway policy failures without converting them to acceptance" do
      expect(Sms::Gateway).to receive(:send).and_raise(Sms::Errors::DailyCapExceeded)
      expect { described_class.send_template(customer: customer, to: "+15559876543", template_key: "verify_code") }
        .to raise_error(Sms::Errors::DailyCapExceeded)
    end
  end
end
