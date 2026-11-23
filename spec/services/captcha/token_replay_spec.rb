# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::TokenReplay do
  around do |example|
    prior = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = prior
  end

  it "treats a blank digest as not consumed and as a no-op consume" do
    expect(described_class.consumed?(nil)).to eq(false)
    expect(described_class.consumed?("")).to eq(false)
    expect(described_class.consume!(nil)).to eq(true)
    expect(described_class.consume!("")).to eq(true)
  end

  it "records a digest as consumed after the first write" do
    expect(described_class.consumed?("abc")).to eq(false)
    expect(described_class.consume!("abc")).to eq(true)
    expect(described_class.consumed?("abc")).to eq(true)
  end

  it "returns false when the same digest is consumed twice" do
    described_class.consume!("abc")
    expect(described_class.consume!("abc")).to eq(false)
  end
end
