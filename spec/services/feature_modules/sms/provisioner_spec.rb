# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Sms::Provisioner do
  let_it_be(:customer) { create(:customer) }

  describe ".call" do
    it "returns nil (no per-tenant provisioning for SMS)" do
      expect(described_class.call(customer)).to be_nil
    end

    it "is idempotent — calling multiple times does not raise" do
      expect {
        described_class.call(customer)
        described_class.call(customer)
      }.not_to raise_error
    end

    it "does not create any customer-scoped records" do
      expect { described_class.call(customer) }.not_to change(Sms::Message, :count)
    end
  end

  describe ".revoke" do
    it "returns nil (no per-tenant cleanup for SMS)" do
      expect(described_class.revoke(customer)).to be_nil
    end

    it "is idempotent — calling multiple times does not raise" do
      expect {
        described_class.revoke(customer)
        described_class.revoke(customer)
      }.not_to raise_error
    end

    it "does not destroy any records" do
      described_class.call(customer)
      expect { described_class.revoke(customer) }.not_to change(Sms::Message, :count)
    end
  end
end
