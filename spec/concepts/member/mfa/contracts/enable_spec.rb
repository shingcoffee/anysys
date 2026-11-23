# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::Contracts::Enable do
  let(:form) { described_class.new(OpenStruct.new(code: nil)) }

  it "is invalid without a code"            do form.validate(code: "");        expect(form.errors[:code]).to be_present end
  it "is invalid when code is non-digits"   do form.validate(code: "abcdef");  expect(form.errors[:code]).to be_present end
  it "is invalid when code is wrong length" do form.validate(code: "12345");   expect(form.errors[:code]).to be_present end
  it "is valid for 6 digits"                do form.validate(code: "123456");  expect(form.errors[:code]).to be_empty   end
end
