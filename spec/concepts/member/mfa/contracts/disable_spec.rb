# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::Contracts::Disable do
  let(:form) { described_class.new(OpenStruct.new(code: nil)) }

  it "is invalid without a code" do form.validate(code: ""); expect(form.errors[:code]).to be_present end
  it "is valid for 6 digits"     do form.validate(code: "123456"); expect(form.errors[:code]).to be_empty end
end
