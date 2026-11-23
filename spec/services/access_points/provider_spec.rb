# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::Provider do
  subject(:provider) { concrete_class.new }

  let(:concrete_class) do
    Class.new(described_class) do
      def call(customer_id:)    = []
      def group_key             = :test
      def group_label           = "Test"
    end
  end

  describe "#applicable? defaults to true" do
    it "returns true for any customer_id" do
      expect(provider.applicable?(customer_id: 99)).to be true
    end
  end

  describe "abstract interface on base class" do
    let(:base) { described_class.new }

    it "#call raises NotImplementedError" do
      expect { base.call(customer_id: 1) }.to raise_error(NotImplementedError)
    end

    it "#group_key raises NotImplementedError" do
      expect { base.group_key }.to raise_error(NotImplementedError)
    end

    it "#group_label raises NotImplementedError" do
      expect { base.group_label }.to raise_error(NotImplementedError)
    end
  end

  describe "concrete subclass" do
    it "#call returns a value without error" do
      expect(provider.call(customer_id: 1)).to eq([])
    end

    it "#group_key returns expected value" do
      expect(provider.group_key).to eq(:test)
    end

    it "#group_label returns expected value" do
      expect(provider.group_label).to eq("Test")
    end

    it "#label_for_group returns group_label when the key matches group_key" do
      expect(provider.label_for_group(:test)).to eq("Test")
      expect(provider.label_for_group("other")).to be_nil
    end
  end
end
