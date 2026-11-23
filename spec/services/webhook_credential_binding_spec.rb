# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookCredentialBinding do
  let(:first) { create(:email_credential) }
  let(:second) { create(:email_credential, mode: "production") }

  it "retains a unique verified account for an unmatched receipt" do
    expect(described_class.call(credentials: [first], messages: Emails::Message.none)).to eq(first)
  end

  it "rejects ambiguity instead of guessing the first mode" do
    expect { described_class.call(credentials: [first, second], messages: Emails::Message.none) }
      .to raise_error(WebhookCredentialBinding::Ambiguous)
  end

  it "never uses a recorded credential that did not authenticate the callback" do
    message = create(:email_message, provider: second.provider, metadata: { credential_id: second.id, credential_mode: second.mode })

    expect(described_class.call(credentials: [first], messages: [message])).to eq(first)
    expect(described_class.recorded_match?(message, first)).to be(false)
  end

  it "matches authenticated receipt recipients against the preserved envelope including CC/BCC" do
    message = create(:email_message, to: "Other <other@example.com>", cc: "Carbon <cc@example.com>", bcc: "hidden@example.com")

    expect(described_class.email_recipient?(message, "CC@EXAMPLE.COM")).to be(true)
    expect(described_class.email_recipient?(message, "hidden@example.com")).to be(true)
    expect(described_class.email_recipient?(message, "foreign@example.com")).to be(false)
  end
end
