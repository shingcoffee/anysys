# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::Registry do
  before { described_class.reset! }
  after  { described_class.install_default_providers! }

  let(:provider_class) do
    Class.new(AccessPoints::Provider) do
      def call(customer_id:) = []
      def group_key   = "x"
      def group_label = "X"
    end
  end

  it "registers and lists providers" do
    p = provider_class.new
    described_class.register(p)
    expect(described_class.providers).to contain_exactly(p)
  end

  it "filters out non-applicable providers for given customer" do
    skip_provider = Class.new(AccessPoints::Provider) do
      def call(customer_id:) = []
      def group_key   = "skip"
      def group_label = "Skip"
      def applicable?(customer_id:) = false
    end.new

    described_class.register(provider_class.new)
    described_class.register(skip_provider)

    applicable = described_class.applicable_for(customer_id: 12_345_678)
    expect(applicable.map(&:group_key)).to eq(["x"])
  end

  it "reset! clears providers" do
    described_class.register(provider_class.new)
    described_class.reset!
    expect(described_class.providers).to be_empty
  end
end
