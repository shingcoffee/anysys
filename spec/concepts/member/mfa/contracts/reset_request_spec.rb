# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::Contracts::ResetRequest do
  let(:form) { described_class.new(OpenStruct.new(email: nil)) }

  it "is invalid without email"       do form.validate(email: "");       expect(form.errors[:email]).to be_present end
  it "is invalid for malformed email" do form.validate(email: "not-an-email"); expect(form.errors[:email]).to be_present end
  it "is valid for a real email"      do form.validate(email: "alice@example.com"); expect(form.errors[:email]).to be_empty end
end
