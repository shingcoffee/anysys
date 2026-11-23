require "rails_helper"
require "ostruct"

RSpec.describe Payments::Contracts::Refund do
  def form(attrs = {}) = described_class.new(OpenStruct.new).tap { |f| f.validate(attrs) }

  it "accepts a valid refund request" do
    f = form(amount: 1.00, reason: "customer request")
    expect(f.errors).to be_empty
  end

  it "rejects missing amount" do
    f = form(reason: "missing")
    expect(f.errors[:amount]).to be_present
  end

  it "rejects zero or negative amount" do
    f = form(amount: 0.00)
    expect(f.errors[:amount]).to be_present
  end

  it "accepts a decimal amount" do
    f = form(amount: 0.50)
    expect(f.errors[:amount]).to be_blank
  end

  it "rounds amounts to two decimal places" do
    contract = form(amount: "0.505")
    expect(contract.errors[:amount]).to be_empty
    expect(contract.amount).to eq(0.51)
  end

  it "rejects a non-numeric amount" do
    f = form(amount: "abc")
    expect(f.errors[:amount]).to be_present
  end
end
