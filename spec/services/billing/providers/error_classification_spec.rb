# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Providers do
  it "does not release an attempt for an unclassified API error even if its payload resembles not-found" do
    error = Payments::Errors::ApiError.new("unclassified query response", code: "40004",
      payload: { "sub_code" => "ACQ.TRADE_NOT_EXIST" }, definitive: false)
    expect(described_class.not_found?(error, "alipay")).to be(false)
  end

  it "recognizes an authoritative vendor not-found rejection" do
    error = Payments::Errors::ApiError.new("trade does not exist", code: "40004",
      payload: { "sub_code" => "ACQ.TRADE_NOT_EXIST" }, definitive: true)
    expect(described_class.not_found?(error, "alipay")).to be(true)
  end
end
