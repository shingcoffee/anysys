# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Sources::Modules do
  let_it_be(:customer) { create(:customer) }

  describe "metadata" do
    it_behaves_like "member source metadata", key: :modules, editable: true, position: 10

    it { expect(described_class.name).to eq("Modules") }
    it { expect(described_class.description).to eq("Read-only surfaces shipped by feature modules.") }
  end

  describe "#surfaces" do
    before { enable_module!("payment", customer, name: "Payments") }

    it "includes the Payments descriptor when payment module is enabled" do
      keys = described_class.new(customer: customer).surfaces.map(&:key)
      expect(keys).to include(:payments)
    end

    it "skips modules that are not available for the customer" do
      other_customer = create(:customer)
      keys = described_class.new(customer: other_customer).surfaces.map(&:key)
      expect(keys).not_to include(:payments)
    end

    it "yields Member::Surface descriptors" do
      surfaces = described_class.new(customer: customer).surfaces
      expect(surfaces.first).to be_a(Member::Surface)
    end
  end
end
