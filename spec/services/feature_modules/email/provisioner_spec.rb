# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Email::Provisioner do
  let_it_be(:customer) { create(:customer) }

  describe ".call" do
    it "is a no-op" do
      expect { described_class.call(customer) }.not_to raise_error
    end
  end

  describe ".revoke" do
    it "is a no-op (tenant data is deleted via FK cascade)" do
      expect { described_class.revoke(customer) }.not_to raise_error
    end
  end
end
