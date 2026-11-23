require "rails_helper"

RSpec.describe Payments::OutTradeNo do
  it "is unique, ≤ 32 chars, with a prefix" do
    a = described_class.generate(prefix: "ch", customer_id: 10_000_001)
    b = described_class.generate(prefix: "ch", customer_id: 10_000_001)
    expect(a).not_to eq(b)
    expect(a.length).to be <= 32
    expect(a).to start_with("ch-")
  end
end
