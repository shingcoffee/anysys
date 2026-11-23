# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::MessageAdmission do
  let(:customer) { create(:customer) }
  let(:template) { create(:email_template, customer: customer) }
  let(:credential) do
    build_stubbed(:email_credential, provider: "aliyun", username: nil,
                  config: { "access_key_id" => "AKID", "from_email" => "sender@example.com" })
  end

  it "rejects campaign transport without persisting an envelope or reserving quota" do
    expect(Emails::Quota).not_to receive(:reserve)
    expect {
      expect { described_class.validate_campaign!(template: template, credential: credential) }
        .to raise_error(Email::Errors::UnsupportedMessage)
    }.not_to change(Emails::Message, :count)
  end

  %w[smtp ses].each do |provider|
    it "accepts campaign capability inspection for #{provider}" do
      credential.provider = provider
      expect { described_class.validate_campaign!(template: template, credential: credential) }.not_to raise_error
    end
  end
end
