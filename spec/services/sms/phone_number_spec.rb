# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::PhoneNumber do
  {
    "+86 138-0013-8000" => "+8613800138000",
    "13800138000" => "+8613800138000",
    "00 86 138.0013.8000" => "+8613800138000",
    "+1 (415) 555-2671" => "+14155552671",
    "+44 20 7946 0958" => "+442079460958",
    "(010) 1234-5678" => "+861012345678"
  }.each do |input, output|
    it "normalizes #{input.inspect} against numbering-plan data" do
      phone = described_class.new(input)
      expect(phone).to be_valid
      expect(phone.e164).to eq(output)
      expect(described_class.normalize(input)).to eq(output)
    end
  end

  [nil, "", " ", [], ["+8613800138000"], 13800138000, {},
   "call +8613800138000", "+8613800138000 ext 1", "+8613800138000;1",
   "+8613800138000#1", "+8613800138000x1", "++8613800138000", "13800138000+",
   "8613800138000", "+15559876543", "+999123456789", "+8611100138000",
   "+123", "+1234567890123456", "138(00138000", "138)00138000(",
   "138\n00138000", "+86 138/0013/8000", "１3800138000", "\xFF".dup.force_encoding("UTF-8"),
   "13800138000".encode("UTF-16LE")].each do |input|
    it "returns nil for invalid input #{input.inspect}" do
      expect(described_class.normalize(input)).to be_nil
      expect(described_class.new(input).valid?).to be(false)
    end
  end

  it "accepts national numbers only in the explicit country context" do
    expect(described_class.normalize("4155552671", country: "US")).to eq("+14155552671")
    expect(described_class.normalize("4155552671")).not_to eq("+14155552671")
  end

  it "does not change Phonelib's global default country" do
    before = Phonelib.default_country
    described_class.normalize("13800138000")
    expect(Phonelib.default_country).to eq(before)
  end
end
