# frozen_string_literal: true

require "rails_helper"
require "cgi"

RSpec.describe Emails::VariableContext do
  it "builds a symbol-keyed hash with authentication_user, customer, and unsubscribe_url" do
    customer = create(:customer)
    user = create(:user, customer: customer, first_name: "Ada", last_name: "L", email: "ada@x.com")
    vars = described_class.for(user: user)

    expect(vars[:authentication_user][:email]).to eq("ada@x.com")
    expect(vars[:authentication_user][:first_name]).to eq("Ada")
    expect(vars[:customer][:name]).to eq(customer.name)

    expect(vars[:unsubscribe_url]).to match(%r{/unsubscribe/.+\z})
  end

  it "omits credential columns from authentication_user" do
    customer = create(:customer)
    user = create(:user, :with_mfa, customer: customer)
    vars = described_class.for(user: user)

    expect(vars[:authentication_user]).not_to have_key(:otp_secret)
    expect(vars[:authentication_user]).not_to have_key(:encrypted_password)
    expect(vars[:authentication_user]).not_to have_key(:sign_in_token)
    expect(vars[:authentication_user]).not_to have_key(:reset_password_token)
    expect(vars[:authentication_user][:email]).to eq(user.email)
  end
end

RSpec.describe Emails::PlatformTokenSeeds do
  describe ".ensure!" do
    it "idempotently creates only the unsubscribe_url platform token" do
      described_class.ensure!
      described_class.ensure!

      platform_keys = Emails::TemplateToken.platform.pluck(:source_key)
      expect(platform_keys).to contain_exactly("unsubscribe_url")
    end
  end
end
